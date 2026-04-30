import Foundation

// MARK: - Public types

/// Controls whether SimulatorRecovery probes sim state before a build.
public enum SimRecoveryMode: String, Sendable, CaseIterable {
  case auto
  case off
}

/// Result of a probeAndRecover call.
public struct RecoveryOutcome: Sendable {
  /// Whether recovery actions were taken.
  public let fired: Bool
  /// Human-readable reason the recovery fired, or nil when it did not fire.
  public let reason: String?
  /// Non-nil when recovery was attempted but failed.
  public let failureReason: String?
  /// Detail about what the health check found (e.g. "state=Shutdown", "list query timed out - recovery skipped").
  public let healthCheckDetail: String?

  static let healthy = RecoveryOutcome(fired: false, reason: nil, failureReason: nil, healthCheckDetail: nil)
}

// MARK: - SimulatorRecovery

/// Probes a simulator's state via `simctl list` and applies tiered recovery if unhealthy.
///
/// Tier 1: shutdown + boot (non-destructive).
/// Tier 2: erase + boot (destructive) — only if Tier 1 re-probe fails.
///
/// All operations are best-effort: failures surface in `RecoveryOutcome.failureReason`
/// rather than being thrown.
enum SimulatorRecovery {

  /// Probe the simulator's state and, if not Booted, attempt tiered recovery.
  ///
  /// - Parameters:
  ///   - udid: The simulator UDID to probe.
  ///   - env: Execution environment.
  /// - Returns: A `RecoveryOutcome` describing what happened. Never throws.
  static func probeAndRecover(udid: String, env: Environment) async -> RecoveryOutcome {
    let probeResult = await probeSimState(udid: udid, env: env)

    switch probeResult {
    case .booted:
      return .healthy

    case .unknown(let detail):
      // Cannot determine state — skip recovery rather than risk destructive action.
      Log.warn("Sim health check inconclusive for \(udid): \(detail) — skipping recovery")
      return RecoveryOutcome(
        fired: false, reason: nil, failureReason: nil, healthCheckDetail: detail)

    case .notBooted(let stateDetail):
      // Simulator is unhealthy — attempt tiered recovery.
      let failureReason = await performTieredRecovery(udid: udid, env: env)
      return RecoveryOutcome(
        fired: true,
        reason: "sim_unhealthy",
        failureReason: failureReason,
        healthCheckDetail: stateDetail
      )
    }
  }

  // MARK: - Private

  private enum ProbeResult {
    case booted
    case notBooted(stateDetail: String)
    case unknown(detail: String)
  }

  /// Reads the simulator state via `simctl list --json`. Fast, non-blocking.
  /// Returns `.unknown` when the query times out or the UDID is not found.
  private static func probeSimState(udid: String, env: Environment) async -> ProbeResult {
    let result = try? await env.shell.run(
      "/usr/bin/xcrun",
      arguments: ["simctl", "list", "devices", "--json"],
      timeout: 10
    )
    guard let output = result?.stdout, !output.isEmpty else {
      return .unknown(detail: "list query timed out - recovery skipped")
    }

    guard let data = output.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let devices = json["devices"] as? [String: Any]
    else {
      return .unknown(detail: "list JSON parse failed - recovery skipped")
    }

    // Walk all runtime buckets to find the device entry.
    for (_, bucket) in devices {
      guard let deviceList = bucket as? [[String: Any]] else { continue }
      for device in deviceList {
        guard let deviceUDID = device["udid"] as? String, deviceUDID == udid else { continue }
        let state = (device["state"] as? String) ?? "Unknown"
        if state == "Booted" {
          return .booted
        }
        return .notBooted(stateDetail: "state=\(state)")
      }
    }
    return .unknown(detail: "UDID not found in list - recovery skipped")
  }

  /// Returns a failure description string on error, or nil on success.
  private static func performTieredRecovery(udid: String, env: Environment) async -> String? {
    // Tier 1: non-destructive shutdown + boot
    _ = try? await env.shell.run(
      "/usr/bin/xcrun", arguments: ["simctl", "shutdown", udid], timeout: 15)
    _ = try? await env.shell.run(
      "/usr/bin/xcrun", arguments: ["simctl", "boot", udid], timeout: 60)

    let tier1Probe = await probeSimState(udid: udid, env: env)
    if case .booted = tier1Probe {
      return nil
    }

    // Tier 2: destructive erase + boot
    let eraseResult = try? await env.shell.run(
      "/usr/bin/xcrun", arguments: ["simctl", "erase", udid], timeout: 60)
    if eraseResult?.succeeded != true {
      let detail = eraseResult?.stderr ?? "erase command unavailable"
      return "simctl erase failed: \(detail)"
    }

    let bootResult = try? await env.shell.run(
      "/usr/bin/xcrun", arguments: ["simctl", "boot", udid], timeout: 60)
    let alreadyBooted = bootResult?.stderr.contains("current state: Booted") == true
    if bootResult?.succeeded != true && !alreadyBooted {
      let detail = bootResult?.stderr ?? "boot command unavailable"
      return "simctl boot failed after erase: \(detail)"
    }

    let tier2Probe = await probeSimState(udid: udid, env: env)
    if case .booted = tier2Probe {
      return nil
    }
    return "simulator did not reach Booted state after erase+boot"
  }
}

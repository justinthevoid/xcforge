import Foundation

// MARK: - Public types

/// Controls whether SimulatorRecovery probes bootstatus before a build.
public enum SimRecoveryMode: String, Sendable, CaseIterable {
  case auto
  case off
}

/// Result of a probeAndRecover call.
public struct RecoveryOutcome: Sendable {
  /// Whether recovery actions were taken (erase + reboot).
  public let fired: Bool
  /// Human-readable reason the recovery fired, or nil when it did not fire.
  public let reason: String?
  /// Non-nil when recovery was attempted but failed.
  public let failureReason: String?

  static let healthy = RecoveryOutcome(fired: false, reason: nil, failureReason: nil)
}

// MARK: - SimulatorRecovery

/// Probes a simulator's boot state and erases/reboots if unhealthy.
///
/// All operations are best-effort: failures surface in `RecoveryOutcome.failureReason`
/// rather than being thrown.
enum SimulatorRecovery {

  /// Probe the simulator's boot status and, if unhealthy, erase + reboot.
  ///
  /// - Parameters:
  ///   - udid: The simulator UDID to probe.
  ///   - env: Execution environment.
  /// - Returns: A `RecoveryOutcome` describing what happened. Never throws.
  static func probeAndRecover(udid: String, env: Environment) async -> RecoveryOutcome {
    let isHealthy = await probeBootstatus(udid: udid, env: env)
    if isHealthy {
      return .healthy
    }

    // Simulator is unhealthy — attempt erase + reboot
    let failureReason = await performRecovery(udid: udid, env: env)
    return RecoveryOutcome(
      fired: true,
      reason: "sim_unhealthy",
      failureReason: failureReason
    )
  }

  // MARK: - Private

  /// Returns true when `bootstatus` reports Status=4 (fully booted) within 30 s.
  private static func probeBootstatus(udid: String, env: Environment) async -> Bool {
    let result = try? await env.shell.run(
      "/usr/bin/xcrun",
      arguments: ["simctl", "bootstatus", udid, "-b"],
      timeout: 30
    )
    guard let output = result?.stdout else { return false }
    return containsStatus4(output)
  }

  /// Returns a failure description string on error, or nil on success.
  private static func performRecovery(udid: String, env: Environment) async -> String? {
    // Step 1: best-effort shutdown
    _ = try? await env.shell.run(
      "/usr/bin/xcrun",
      arguments: ["simctl", "shutdown", udid],
      timeout: 15
    )

    // Step 2: erase (required to unstick the simulator)
    let eraseResult = try? await env.shell.run(
      "/usr/bin/xcrun",
      arguments: ["simctl", "erase", udid],
      timeout: 60
    )
    if eraseResult?.succeeded != true {
      let detail = eraseResult?.stderr ?? "erase command unavailable"
      return "simctl erase failed: \(detail)"
    }

    // Step 3: boot
    let bootResult = try? await env.shell.run(
      "/usr/bin/xcrun",
      arguments: ["simctl", "boot", udid],
      timeout: 60
    )
    let alreadyBooted = bootResult?.stderr.contains("current state: Booted") == true
    if bootResult?.succeeded != true && !alreadyBooted {
      let detail = bootResult?.stderr ?? "boot command unavailable"
      return "simctl boot failed: \(detail)"
    }

    // Step 4: probe again to confirm health
    let confirmedHealthy = await probeBootstatus(udid: udid, env: env)
    if !confirmedHealthy {
      return "simulator did not reach Status=4 after erase+boot"
    }
    return nil
  }

  /// Checks the output of `simctl bootstatus` for an exact `Status=4` token.
  ///
  /// Uses multiple boundary checks to avoid false-positives from tokens
  /// like "Status=40" or "Status=42".
  static func containsStatus4(_ output: String) -> Bool {
    // Check common forms: "Status=4\n", "Status=4 ", "Status = 4", or end-of-string.
    if output.contains("Status=4\n") { return true }
    if output.contains("Status=4 ") { return true }
    if output.hasSuffix("Status=4") { return true }
    // "Status = 4" variant (space around equals) — use boundary checks too
    if output.contains("Status = 4\n") { return true }
    if output.contains("Status = 4 ") { return true }
    if output.hasSuffix("Status = 4") { return true }

    // Whitespace-split fallback: exact "Status=4" or "4" following "Status =" token pair.
    let tokens = output.components(separatedBy: .whitespacesAndNewlines)
    return tokens.contains("Status=4")
  }
}

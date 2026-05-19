import Foundation

/// Shared session-create classification + bounded auto-heal used by both the
/// `ui session` CLI command and the `wda_create_session` MCP tool.
///
/// Design constraints (encode prior-spec review findings):
/// - Reuses `WDAClient.ensureWDARunning()`/`deployXCForgeWDA` *as-is* — never
///   widens their policy. This is only a bounded one-shot wrapper at the
///   `ui session` level, never inside the element-path `ensureSession()`.
/// - Classification is cheap state inspection (DerivedData present? booted
///   sim? :8100 reachable?), all subprocess I/O via `env.shell` (never
///   `Process`).
/// - Bounded: exactly one auto-heal attempt, hard timeout.
public enum WDASessionRepair {

  /// Deterministic DerivedData path the WDA runner deploy uses (mirrors
  /// `WDAClient.deployXCForgeWDA`). A missing tree after a DerivedData nuke is
  /// the canonical recoverable cause.
  public static let deployDerivedData =
    NSHomeDirectory() + "/Library/Developer/Xcode/DerivedData/xcforgeWDA-deploy"

  /// Hard ceiling for the single auto-heal attempt, in seconds.
  static let autoHealTimeout: TimeInterval = 240

  // MARK: - Classification

  /// Classify a raw session-create failure into an actionable cause using
  /// cheap state probes. Pure w.r.t. injected `env`.
  public static func classify(_ error: Error, bundleId: String?, env: Environment) async
    -> WDASessionCreateError
  {
    let raw = "\(error)"

    // 1. A non-empty bound bundle that simply mismatched the request is a
    //    bind rejection, not a runner failure (caller passes this through a
    //    sentinel error — see classifyBindMismatch).
    if let bindErr = error as? BindMismatch {
      return WDASessionCreateError(
        cause: .sessionBindRejected,
        detail:
          "WDA accepted the session but bound bundleId=\(bindErr.reported ?? "<none>") "
          + "≠ requested=\(bindErr.requested). WDA activated a different app."
      )
    }

    // 2. No booted simulator → nothing WDA can attach to. Only assert this
    //    non-recoverable cause when the probe DEFINITIVELY saw no booted
    //    device. On JSON shape drift / parse failure the state is `.unknown`
    //    and we must NOT flip a possibly-booted machine to no_booted_simulator
    //    — fall through to the runner-reachability checks instead.
    if await bootState(env: env) == .none {
      return WDASessionCreateError(
        cause: .noBootedSimulator,
        detail: "No booted simulator found. WDA cannot create a session without a booted device."
      )
    }

    // 3. WDA runner reachable? If :8100 answers /status the runner is up, so
    //    a session-create failure is a bind rejection against a live runner.
    let healthy = await env.wdaClient.isHealthy()
    if healthy {
      return WDASessionCreateError(
        cause: .sessionBindRejected,
        detail:
          "WDA runner is reachable but rejected the session"
          + (bundleId.map { " for bundleId=\($0)" } ?? "") + ". Raw: \(raw)"
      )
    }

    // 4. Runner not reachable → distinguish "never built" from "built but
    //    not running". A missing deploy DerivedData tree after a clean is the
    //    classic recoverable case.
    if !env.directoryExists(deployDerivedData) {
      return WDASessionCreateError(
        cause: .wdaRunnerNotRunning,
        detail:
          "WDA runner not reachable on :8100 and xcforgeWDA-deploy DerivedData is missing "
          + "(likely cleaned). Raw: \(raw)"
      )
    }

    return WDASessionCreateError(
      cause: .wdaRunnerNotRunning,
      detail:
        "WDA runner not reachable on :8100 though deploy DerivedData exists. Raw: \(raw)"
    )
  }

  /// Sentinel passed by callers when WDA accepted the session but bound a
  /// different bundle than requested — classified as `session_bind_rejected`.
  public struct BindMismatch: Error, Sendable {
    public let requested: String
    public let reported: String?
    public init(requested: String, reported: String?) {
      self.requested = requested
      self.reported = reported
    }
  }

  /// Whether a recoverable cause should trigger the bounded auto-heal.
  /// Bind rejection is *not* auto-recoverable (the app/bundle is the problem,
  /// not the runner) — fail fast with structured detail instead.
  public static func isRecoverable(_ cause: WDASessionCause) -> Bool {
    switch cause {
    case .wdaRunnerNotRunning, .wdaRunnerBuildFailed:
      return true
    case .noBootedSimulator, .bundleNotInstalled, .sessionBindRejected, .unknown:
      return false
    }
  }

  // MARK: - Bounded Auto-Heal

  public struct RepairOutcome: Sendable {
    public let recovered: Bool
    public let sessionId: String?
    public let actions: [String]
    public let failure: WDASessionCreateError?
  }

  /// Attempt **exactly one** bounded rebuild+relaunch+rebind via the existing
  /// `ensureWDARunning()` orchestrator. Hard-timeout-bounded; never loops.
  ///
  /// On success: re-create the session, re-bind to `bundleId`, verify via
  /// `verifyActiveBundleId`. Returns `recovered: true` + the actions taken, or
  /// a structured `wda_runner_build_failed` failure with the exact repair cmd.
  public static func attemptAutoHeal(bundleId: String?, env: Environment) async -> RepairOutcome {
    var actions: [String] = []

    // Real wall-clock bound: race the single heal attempt against a sleep.
    // Whichever child finishes first wins; if the timeout wins we return the
    // failure deterministically WITHOUT awaiting the heal child (which may be
    // blocked in a subprocess that ignores cancellation), so the caller is
    // unblocked at the deadline. Still EXACTLY ONE `ensureWDARunning` attempt.
    enum HealRace: Sendable {
      case healed(Bool)
      case timedOut
    }

    let raced: HealRace = await withTaskGroup(of: HealRace.self) { group in
      group.addTask {
        do {
          // Reuse the existing orchestrator AS-IS (do not widen its policy).
          try await env.wdaClient.ensureWDARunning()
          return .healed(true)
        } catch {
          return .healed(false)
        }
      }
      group.addTask {
        try? await Task.sleep(nanoseconds: UInt64(autoHealTimeout * 1_000_000_000))
        return .timedOut
      }
      // First child to finish decides the outcome; cancel the rest. We do NOT
      // await the loser — a hung subprocess must not re-block the caller.
      let first = await group.next() ?? .timedOut
      group.cancelAll()
      return first
    }

    actions.append("ensureWDARunning (rebuild+relaunch WDA runner)")

    let healed: Bool
    switch raced {
    case .healed(let ok):
      healed = ok
    case .timedOut:
      healed = false
    }

    guard healed else {
      return RepairOutcome(
        recovered: false,
        sessionId: nil,
        actions: actions,
        failure: WDASessionCreateError(
          cause: .wdaRunnerBuildFailed,
          detail:
            "Bounded auto-heal could not rebuild/relaunch the WDA runner within "
            + "\(Int(autoHealTimeout))s."
        )
      )
    }

    do {
      let sid = try await env.wdaClient.createSession(bundleId: bundleId)
      actions.append("createSession")

      if let requested = bundleId {
        // Distinguish a *thrown* verify (transient WDA hiccup — NOT a bind
        // rejection, do not discard the valid session) from an actually
        // resolved-but-DIFFERENT bundle (the real bind rejection).
        do {
          let bound = try await env.wdaClient.verifyActiveBundleId()
          actions.append("verifyActiveBundleId")
          if let bound, bound != requested {
            return RepairOutcome(
              recovered: false,
              sessionId: sid,
              actions: actions,
              failure: WDASessionCreateError(
                cause: .sessionBindRejected,
                detail:
                  "Runner recovered but bundleId binding still failed "
                  + "(requested=\(requested), reported=\(bound))."
              )
            )
          }
          // bound == requested, or bound == nil (verify could not resolve a
          // foreground bundle but did not throw) → treat the session as
          // created. A nil here is not a bind rejection.
        } catch {
          // Transient verify error — the session was created; do NOT escalate
          // to a create-failure or session_bind_rejected, and do NOT discard
          // the session id.
          actions.append("verifyActiveBundleId (threw — treated as created)")
        }
      }
      return RepairOutcome(
        recovered: true, sessionId: sid, actions: actions, failure: nil)
    } catch {
      return RepairOutcome(
        recovered: false,
        sessionId: nil,
        actions: actions,
        failure: WDASessionCreateError(
          cause: .wdaRunnerBuildFailed,
          detail:
            "WDA runner recovered but session re-create failed: \(error)"
        )
      )
    }
  }

  // MARK: - Cheap State Probes

  // MARK: - Shared `ui session` Orchestration

  /// Structured outcome of a session-create attempt. Drives the
  /// `error/cause/detail/remediation/recovered/appForeground` JSON envelope
  /// shared by the CLI command and the `wda_create_session` MCP tool.
  public struct SessionAttempt: Sendable {
    public let succeeded: Bool
    public let sessionId: String?
    public let message: String
    public let error: String?
    public let cause: WDASessionCause?
    public let detail: String?
    public let remediation: String?
    public let recovered: Bool?
    public let actions: [String]?
    public let appForeground: Bool?
  }

  /// Create a WDA session, classify failures into the structured envelope, and
  /// (unless opted out) attempt exactly one bounded auto-heal on a recoverable
  /// cause. Used by both `ui session` and `wda_create_session`.
  ///
  /// - Parameters:
  ///   - bundleId: app to bind the session to (nil = unbound).
  ///   - autoHeal: when false, preserve today's fail-fast (no repair attempt).
  ///   - relaunchApp: reserved opt-in; auto-heal never relaunches the user app
  ///     unless this is set (runner repair is safe, app relaunch is not).
  ///   - ensureRunning: when true (default), call `ensureWDARunning()` before
  ///     the first create — matches the existing default `ui session` path. A
  ///     custom-URL caller passes false (never deploy to a custom URL).
  public static func createSession(
    bundleId: String?,
    autoHeal: Bool = true,
    relaunchApp: Bool = false,
    ensureRunning: Bool = true,
    env: Environment
  ) async -> SessionAttempt {
    do {
      if ensureRunning {
        try await env.wdaClient.ensureWDARunning()
      }
      let sid = try await env.wdaClient.createSession(bundleId: bundleId)
      if let requested = bundleId {
        // Mirror the heal-path distinction so both paths agree: a *thrown*
        // verify is a transient hiccup (not a bind rejection — keep the
        // session), only an actually-resolved-but-DIFFERENT bundle is a real
        // `session_bind_rejected`. A resolved nil is not a rejection either.
        let bound: String?
        do {
          bound = try await env.wdaClient.verifyActiveBundleId()
        } catch {
          // Transient verify error — session created; do not classify as a
          // bind rejection or discard the session id.
          let foreground = await appForeground(requested: bundleId, env: env)
          return SessionAttempt(
            succeeded: true,
            sessionId: sid,
            message:
              "Session created: \(sid) (bind verify was inconclusive: \(error) — "
              + "session retained).",
            error: nil,
            cause: nil,
            detail: nil,
            remediation: nil,
            recovered: nil,
            actions: nil,
            appForeground: foreground
          )
        }
        if let bound, bound != requested {
          // Bind mismatch — classify (always session_bind_rejected) and
          // surface the real message instead of swallowing it.
          let structured = await classify(
            BindMismatch(requested: requested, reported: bound), bundleId: bundleId, env: env)
          let foreground = await appForeground(requested: requested, env: env)
          return SessionAttempt(
            succeeded: false,
            sessionId: sid,
            message:
              "Session created: \(sid) but bundleId binding failed "
              + "(requested=\(requested), reported=\(bound)). "
              + "WDA may not have activated the app — ensure it is installed and runnable.",
            error: "wda_session_create_failed",
            cause: structured.cause,
            detail: structured.detail,
            remediation: structured.remediation,
            recovered: nil,
            actions: nil,
            appForeground: foreground
          )
        }
      }
      let foreground = await appForeground(requested: bundleId, env: env)
      return SessionAttempt(
        succeeded: true,
        sessionId: sid,
        message: "Session created: \(sid)",
        error: nil,
        cause: nil,
        detail: nil,
        remediation: nil,
        recovered: nil,
        actions: nil,
        appForeground: foreground
      )
    } catch {
      let structured = await classify(error, bundleId: bundleId, env: env)

      // Opt-out OR non-recoverable cause → today's fail-fast, structured. No
      // heal attempt is made in this branch (either opted out or the cause is
      // not recoverable), so `recovered` is `nil` (omitted) — `false` would
      // imply an attempt was made and failed, which is dishonest here.
      guard autoHeal, isRecoverable(structured.cause) else {
        let foreground = await appForeground(requested: bundleId, env: env)
        return SessionAttempt(
          succeeded: false,
          sessionId: nil,
          message: structured.description,
          error: "wda_session_create_failed",
          cause: structured.cause,
          detail: structured.detail,
          remediation: structured.remediation,
          recovered: nil,
          actions: nil,
          appForeground: foreground
        )
      }

      // Exactly one bounded auto-heal.
      let outcome = await attemptAutoHeal(bundleId: bundleId, env: env)
      let foreground = await appForeground(requested: bundleId, env: env)
      if outcome.recovered {
        return SessionAttempt(
          succeeded: true,
          sessionId: outcome.sessionId,
          message:
            "Session recovered after auto-heal: \(outcome.sessionId ?? "?") "
            + "(actions: \(outcome.actions.joined(separator: ", ")))",
          error: nil,
          cause: nil,
          detail: nil,
          remediation: nil,
          recovered: true,
          actions: outcome.actions,
          appForeground: foreground
        )
      }
      let fail = outcome.failure ?? structured
      return SessionAttempt(
        succeeded: false,
        sessionId: nil,
        message: fail.description,
        error: "wda_session_create_failed",
        cause: fail.cause,
        detail: fail.detail,
        remediation: fail.remediation,
        recovered: false,
        actions: outcome.actions,
        appForeground: foreground
      )
    }
  }

  /// Whether the requested bundle is foreground per `verifyActiveBundleId`.
  /// `nil` (never `false`) when WDA is unreachable — never a false negative.
  public static func appForeground(requested: String?, env: Environment) async -> Bool? {
    guard let want = requested, !want.isEmpty else {
      // No explicit target — derive from the recorded active bundle if any.
      guard let recorded = await env.wdaClient.getActiveBundleId(), !recorded.isEmpty else {
        return nil
      }
      guard let active = try? await env.wdaClient.verifyActiveBundleId() else { return nil }
      return active == recorded
    }
    guard let active = try? await env.wdaClient.verifyActiveBundleId() else { return nil }
    return active == want
  }

  /// Tri-state booted-simulator probe. Distinguishes a definitive "no booted
  /// device" from "could not determine" (JSON shape drift / parse failure /
  /// shell error) so a non-recoverable `no_booted_simulator` is never asserted
  /// on a possibly-booted machine.
  enum BootState: Sendable {
    /// At least one device is in the "Booted" state.
    case some
    /// `simctl list devices booted -j` parsed cleanly and listed no Booted
    /// device — definitively no booted simulator.
    case none
    /// Shell error or JSON shape drift — state indeterminate. Callers must NOT
    /// treat this as `no_booted_simulator`.
    case unknown
  }

  /// Query the booted-device state via `simctl list devices booted -j`.
  /// `env.shell` only. Parse/shape failures yield `.unknown`, never `.none`.
  static func bootState(env: Environment) async -> BootState {
    guard
      let result = try? await env.shell.xcrun(
        timeout: 10, "simctl", "list", "devices", "booted", "-j")
    else {
      return .unknown
    }
    guard
      let data = result.stdout.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return .unknown
    }
    // The `devices` map's value shape can drift across Xcode versions; treat a
    // shape we cannot read as `.unknown` rather than `.none`. Walk it
    // defensively as `[String: Any]` arrays. If `devices` is empty we trust
    // the clean parse (definitively no booted device → `.none`); but if it has
    // entries and NONE of them are a readable device-array shape, the shape
    // has drifted — `.unknown`, never `.none`.
    guard let devices = json["devices"] as? [String: Any] else {
      return .unknown
    }
    if devices.isEmpty {
      return .none
    }
    var sawReadableArray = false
    var sawBooted = false
    for value in devices.values {
      guard let sims = value as? [[String: Any]] else { continue }
      sawReadableArray = true
      if sims.contains(where: { ($0["state"] as? String) == "Booted" }) {
        sawBooted = true
        break
      }
    }
    if sawBooted { return .some }
    // Read at least one well-formed (possibly empty) device array and saw no
    // Booted device → definitively none. Saw entries but could not read ANY as
    // a device array → shape drift → unknown.
    return sawReadableArray ? .none : .unknown
  }

  /// Whether any simulator device is in the "Booted" state. `env.shell` only.
  /// Backward-compatible boolean wrapper over `bootState`. NOTE: `.unknown`
  /// maps to `false` here for callers that only need a boolean; `classify`
  /// uses `bootState` directly so JSON drift never asserts a non-recoverable
  /// `no_booted_simulator`.
  static func hasBootedSimulator(env: Environment) async -> Bool {
    await bootState(env: env) == .some
  }
}

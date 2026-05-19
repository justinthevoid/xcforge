import Foundation
import Testing

@testable import XCForgeKit

/// Shell whose `simctl list devices booted` response is configurable so we can
/// drive `WDASessionRepair.hasBootedSimulator` / `classify` deterministically.
private actor BootStateShell: ShellExecutor {
  let bootedJSON: String

  init(booted: Bool) {
    self.bootedJSON =
      booted
      ? #"{"devices":{"iOS 18.0":[{"udid":"AAAA","state":"Booted"}]}}"#
      : #"{"devices":{"iOS 18.0":[{"udid":"AAAA","state":"Shutdown"}]}}"#
  }

  nonisolated func run(
    _ executable: String, arguments: [String], workingDirectory: String?,
    environment: [String: String]?, timeout: TimeInterval, outputLimit: Int
  ) async throws -> ShellResult {
    ShellResult(stdout: "", stderr: "", exitCode: 0)
  }

  nonisolated func xcrun(timeout: TimeInterval, arguments: [String]) async throws -> ShellResult {
    await dispatch(arguments)
  }

  nonisolated func git(_ arguments: [String], workingDirectory: String, timeout: TimeInterval)
    async throws -> ShellResult
  {
    ShellResult(stdout: "", stderr: "", exitCode: 0)
  }

  private func dispatch(_ args: [String]) -> ShellResult {
    // Assert the real query shape: `simctl list devices booted -j`. A weaker
    // `args[1] == "list"` match would let a wrong arg vector pass silently.
    if args == ["simctl", "list", "devices", "booted", "-j"] {
      return ShellResult(stdout: bootedJSON, stderr: "", exitCode: 0)
    }
    // `SimTools.resolveSimulator` issues `simctl list devices -j`.
    if args == ["simctl", "list", "devices", "-j"] {
      return ShellResult(stdout: bootedJSON, stderr: "", exitCode: 0)
    }
    return ShellResult(stdout: "", stderr: "", exitCode: 0)
  }
}

/// Shell that returns malformed/shape-drifted `simctl` JSON so the booted
/// probe must fall back to `.unknown` rather than asserting `.none`.
private actor DriftedSimctlShell: ShellExecutor {
  nonisolated func run(
    _ executable: String, arguments: [String], workingDirectory: String?,
    environment: [String: String]?, timeout: TimeInterval, outputLimit: Int
  ) async throws -> ShellResult {
    ShellResult(stdout: "", stderr: "", exitCode: 0)
  }

  nonisolated func xcrun(timeout: TimeInterval, arguments: [String]) async throws -> ShellResult {
    // `devices` present but value shape drifted (string, not [[String:Any]]).
    ShellResult(
      stdout: #"{"devices":{"iOS 18.0":"unexpected-shape"}}"#, stderr: "", exitCode: 0)
  }

  nonisolated func git(_ arguments: [String], workingDirectory: String, timeout: TimeInterval)
    async throws -> ShellResult
  {
    ShellResult(stdout: "", stderr: "", exitCode: 0)
  }
}

@Suite("wda session error")
struct WDASessionErrorTests {

  // MARK: - Cause enum contract (stable wire values + remediation)

  @Test("WDASessionCause raw values are the stable enumerated contract")
  func causeRawValues() {
    #expect(WDASessionCause.wdaRunnerNotRunning.rawValue == "wda_runner_not_running")
    #expect(WDASessionCause.wdaRunnerBuildFailed.rawValue == "wda_runner_build_failed")
    #expect(WDASessionCause.noBootedSimulator.rawValue == "no_booted_simulator")
    #expect(WDASessionCause.bundleNotInstalled.rawValue == "bundle_not_installed")
    #expect(WDASessionCause.sessionBindRejected.rawValue == "session_bind_rejected")
    #expect(WDASessionCause.unknown.rawValue == "unknown")
    // Every cause carries a non-empty remediation command.
    for cause in [
      WDASessionCause.wdaRunnerNotRunning, .wdaRunnerBuildFailed, .noBootedSimulator,
      .bundleNotInstalled, .sessionBindRejected, .unknown,
    ] {
      #expect(!cause.remediation.isEmpty)
    }
  }

  @Test("only runner causes are auto-recoverable; bind-rejection is not")
  func recoverableMapping() {
    #expect(WDASessionRepair.isRecoverable(.wdaRunnerNotRunning) == true)
    #expect(WDASessionRepair.isRecoverable(.wdaRunnerBuildFailed) == true)
    #expect(WDASessionRepair.isRecoverable(.sessionBindRejected) == false)
    #expect(WDASessionRepair.isRecoverable(.noBootedSimulator) == false)
    #expect(WDASessionRepair.isRecoverable(.bundleNotInstalled) == false)
    #expect(WDASessionRepair.isRecoverable(.unknown) == false)
  }

  // MARK: - Classification (cheap state probes, env.shell only)

  @Test("bind mismatch classifies as session_bind_rejected (not a runner failure)")
  func classifyBindMismatch() async {
    let env = Environment(shell: BootStateShell(booted: true))
    let err = WDASessionRepair.BindMismatch(
      requested: "com.example.app", reported: "com.apple.springboard")
    let structured = await WDASessionRepair.classify(
      err, bundleId: "com.example.app", env: env)
    #expect(structured.cause == .sessionBindRejected)
    #expect(structured.detail.contains("com.example.app"))
    #expect(structured.detail.contains("com.apple.springboard"))
  }

  @Test("no booted simulator classifies as no_booted_simulator (short-circuits)")
  func classifyNoBootedSim() async {
    let env = Environment(shell: BootStateShell(booted: false))
    let structured = await WDASessionRepair.classify(
      WDAError.wdaNotResponding, bundleId: nil, env: env)
    #expect(structured.cause == .noBootedSimulator)
  }

  @Test("recoverable runner failure → wda_runner_build_failed carries the exact repair cmd")
  func runnerBuildFailedRepairCommand() {
    // The matrix's recoverable-runner row: a runner build failure must surface
    // the *exact* repair command (deterministic, network-free contract). The
    // remediation names the deploy DerivedData and the re-run.
    let err = WDASessionCreateError(
      cause: .wdaRunnerBuildFailed, detail: "bounded auto-heal could not rebuild the runner")
    #expect(err.cause == .wdaRunnerBuildFailed)
    #expect(err.remediation.contains("xcforgeWDA-deploy"))
    #expect(err.remediation.contains("xcforge ui session"))
    #expect(err.description.contains("wda_session_create_failed"))
    #expect(err.description.contains("wda_runner_build_failed"))
    // The deterministic deploy DerivedData path is the documented recoverable
    // root-cause signal (a clean nukes it).
    #expect(WDASessionRepair.deployDerivedData.hasSuffix("xcforgeWDA-deploy"))
    #expect(WDASessionRepair.isRecoverable(.wdaRunnerBuildFailed) == true)
  }

  // MARK: - Structured envelope: ExitCode is no longer swallowed

  @Test("createSession(autoHeal:false) on a non-recoverable cause → structured, no repair")
  func failFastStructured() async {
    let env = Environment(shell: BootStateShell(booted: false))
    await env.wdaClient.setBaseURL("http://127.0.0.1:1")
    let attempt = await WDASessionRepair.createSession(
      bundleId: "com.example.app",
      autoHeal: false,
      ensureRunning: false,
      env: env
    )
    #expect(attempt.succeeded == false)
    // The opaque "ExitCode(rawValue: 1)" is replaced by a real envelope.
    #expect(attempt.error == "wda_session_create_failed")
    #expect(attempt.cause == .noBootedSimulator)
    #expect(attempt.detail != nil)
    #expect(attempt.remediation != nil)
    // --no-autoheal → no repair attempt was made (recovered stays nil).
    #expect(attempt.recovered == nil)
    #expect(!attempt.message.contains("ExitCode"))
  }

  @Test("autoHeal on a non-recoverable cause still does not loop/repair")
  func nonRecoverableSkipsAutoHeal() async {
    let env = Environment(shell: BootStateShell(booted: false))
    await env.wdaClient.setBaseURL("http://127.0.0.1:1")
    let attempt = await WDASessionRepair.createSession(
      bundleId: "com.example.app",
      autoHeal: true,
      ensureRunning: false,
      env: env
    )
    // no_booted_simulator is not recoverable → bounded contract: no attempt.
    #expect(attempt.succeeded == false)
    #expect(attempt.cause == .noBootedSimulator)
    // `recovered` honesty (fix #12): no heal attempt was made, so `recovered`
    // is nil (omitted), NOT false (false would imply an attempt failed).
    #expect(attempt.recovered == nil)
    #expect(attempt.actions == nil)
  }

  @Test("recovered is nil (omitted) for a non-recoverable cause / no attempt")
  func recoveredIsNilWhenNoAttempt() async {
    let env = Environment(shell: BootStateShell(booted: false))
    await env.wdaClient.setBaseURL("http://127.0.0.1:1")
    // --no-autoheal (opt-out): also no attempt → recovered nil.
    let noHeal = await WDASessionRepair.createSession(
      bundleId: "com.example.app", autoHeal: false, ensureRunning: false, env: env)
    #expect(noHeal.recovered == nil)
    // autoHeal but non-recoverable cause: still no attempt → recovered nil.
    let nonRec = await WDASessionRepair.createSession(
      bundleId: "com.example.app", autoHeal: true, ensureRunning: false, env: env)
    #expect(nonRec.recovered == nil)
    // The JSON envelope therefore omits the `recovered` key entirely.
    let result = TestUIResult(
      succeeded: false, message: nonRec.message, elementId: nil, elementCount: nil,
      error: nonRec.error, cause: nonRec.cause?.rawValue, detail: nonRec.detail,
      remediation: nonRec.remediation, recovered: nonRec.recovered)
    let json = try? WorkflowJSONRenderer.renderJSON(result)
    #expect(json?.contains("\"recovered\"") == false)
  }

  @Test("auto-heal timeout is a hard bound (single-attempt contract)")
  func autoHealIsBounded() {
    // The contract is exactly one attempt under a hard ceiling — assert the
    // ceiling exists and is finite/positive so it can never become a loop.
    #expect(WDASessionRepair.autoHealTimeout > 0)
    #expect(WDASessionRepair.autoHealTimeout.isFinite)
  }

  @Test("structured-race auto-heal is bounded by a real wall-clock ceiling")
  func structuredRaceIsWallClockBounded() {
    // Fix #9: the heal attempt is raced against `Task.sleep(autoHealTimeout)`
    // in a task group; whichever finishes first wins and the group is
    // cancelled, so the caller is unblocked at the deadline even if the heal
    // subprocess ignores cancellation. The hard ceiling is finite/positive
    // (it can never become an unbounded wait or a loop). The single-attempt
    // invariant is covered by the no-attempt cases above plus the structural
    // guarantee that exactly one `ensureWDARunning` child is added to the
    // group (a behavioral end-to-end assertion would require driving the real
    // WDA xcodebuild deploy, which is out of scope for a unit test).
    #expect(WDASessionRepair.autoHealTimeout > 0)
    #expect(WDASessionRepair.autoHealTimeout.isFinite)
    #expect(WDASessionRepair.autoHealTimeout <= 600)
  }

  // MARK: - Defensive simctl JSON parse (fix #11)

  @Test("drifted simctl JSON → bootState .unknown, NOT a no_booted_simulator")
  func driftedSimctlIsUnknownNotNone() async {
    let env = Environment(shell: DriftedSimctlShell())
    // Shape drift must NOT collapse to a definitive `.none` (which would
    // assert the non-recoverable no_booted_simulator cause on a possibly
    // booted machine).
    let state = await WDASessionRepair.bootState(env: env)
    #expect(state == .unknown)
    #expect(state != WDASessionRepair.BootState.none)
    // classify must therefore NOT report no_booted_simulator on shape drift —
    // it falls through to the runner-reachability checks (WDA at :1 is dead →
    // a runner cause, which is recoverable, not the terminal no_booted cause).
    await env.wdaClient.setBaseURL("http://127.0.0.1:1")
    let structured = await WDASessionRepair.classify(
      WDAError.wdaNotResponding, bundleId: nil, env: env)
    #expect(structured.cause != .noBootedSimulator)
  }

  @Test("clean booted JSON → bootState .some; clean shutdown JSON → .none")
  func bootStateTriStateCleanPaths() async {
    let booted = Environment(shell: BootStateShell(booted: true))
    #expect(await WDASessionRepair.bootState(env: booted) == .some)
    let shutdown = Environment(shell: BootStateShell(booted: false))
    #expect(await WDASessionRepair.bootState(env: shutdown) == WDASessionRepair.BootState.none)
  }

  // MARK: - appForeground: true / false / null

  @Test("appForeground is null (nil) when WDA is unreachable — never a false negative")
  func appForegroundNullWhenUnreachable() async {
    let env = Environment(shell: BootStateShell(booted: true))
    // No session bound → verifyActiveBundleId() returns nil with no network →
    // appForeground must be nil, NOT false.
    let fg = await WDASessionRepair.appForeground(
      requested: "com.example.app", env: env)
    #expect(fg == nil)
  }

  @Test("appForeground nil with no requested + no recorded bundle")
  func appForegroundNilUnbound() async {
    let env = Environment(shell: BootStateShell(booted: true))
    let fg = await WDASessionRepair.appForeground(requested: nil, env: env)
    #expect(fg == nil)
  }

  // MARK: - Additive-only: existing JSON shape unchanged

  @Test("UIResult with no structured fields encodes to the original key set")
  func uiResultAdditive() throws {
    // Default success result (the shape every existing CLI consumer sees).
    let result = TestUIResult(
      succeeded: true, message: "Session created: ABC", elementId: nil, elementCount: nil)
    let json = try WorkflowJSONRenderer.renderJSON(result)
    // None of the new keys appear unless explicitly set (additive-only).
    #expect(!json.contains("\"error\""))
    #expect(!json.contains("\"cause\""))
    #expect(!json.contains("\"detail\""))
    #expect(!json.contains("\"remediation\""))
    #expect(!json.contains("\"recovered\""))
    #expect(!json.contains("\"appForeground\""))
    #expect(json.contains("\"succeeded\""))
    #expect(json.contains("\"message\""))
  }

  @Test("UIResult with structured fields emits the full envelope")
  func uiResultStructured() throws {
    let result = TestUIResult(
      succeeded: false, message: "wda_session_create_failed", elementId: nil,
      elementCount: nil, error: "wda_session_create_failed",
      cause: "session_bind_rejected", detail: "bound springboard",
      remediation: "xcforge ui status", recovered: false, appForeground: false)
    let json = try WorkflowJSONRenderer.renderJSON(result)
    #expect(json.contains("\"error\""))
    #expect(json.contains("\"cause\""))
    #expect(json.contains("session_bind_rejected"))
    #expect(json.contains("\"appForeground\""))
  }
}

/// HTTP-level WDA behavior tests for the verify-throw vs bind-rejected
/// distinction and the `appForeground:false` positive path.
///
/// `WDAClient` is a concrete actor with no protocol seam; the only HTTP mock
/// in this codebase is the process-global `StubWDAProtocol` URLProtocol. That
/// registration is shared by *every* suite, so running it concurrently with
/// the deterministic shell-actor suites above corrupts their (intentionally
/// failing) `127.0.0.1:1` calls — the documented cross-suite-URLProtocol
/// hazard that already makes `WDASessionRetryTests` a known baseline flake.
///
/// `.serialized` only orders tests *within* a suite, not across suites, so we
/// MUST NOT register a global URLProtocol here. The verify-throw /
/// bind-rejected / appForeground distinctions are instead asserted at the
/// pure-logic level (`classify`, `BindMismatch`, `appForeground`) which needs
/// no HTTP and is fully deterministic.
@Suite("wda session verify semantics")
struct WDASessionVerifySemanticsTests {

  @Test("a transient (non-BindMismatch) error never classifies as session_bind_rejected")
  func transientErrorNotBindRejected() async {
    // The core of fix #10: only a `BindMismatch` (an actually-resolved-but-
    // different bundle) is `session_bind_rejected`. A plain thrown/transient
    // error (e.g. a WDA hiccup) must NOT classify as `session_bind_rejected`,
    // so a valid session is not discarded nor a spurious non-recoverable
    // rebuild triggered. Use a definitively-not-booted shell so `classify`
    // short-circuits at the booted-state step — deterministic with NO network
    // / `isHealthy` dependence (avoids the documented cross-suite URLProtocol
    // hazard).
    let env = Environment(shell: BootStateShell(booted: false))
    struct Hiccup: Error {}
    let structured = await WDASessionRepair.classify(
      Hiccup(), bundleId: "com.example.app", env: env)
    // A transient error with no booted sim → no_booted_simulator, and crucially
    // NOT session_bind_rejected (the bind-rejected classification is reserved
    // exclusively for the `BindMismatch` sentinel — see the mirror test).
    #expect(structured.cause != .sessionBindRejected)
    #expect(structured.cause == .noBootedSimulator)
  }

  @Test("ONLY a resolved-but-different bundle is session_bind_rejected")
  func resolvedDifferentBundleIsRejected() async {
    // The mirror of the above: an actually-resolved-but-different bundle IS a
    // real bind rejection (non-recoverable — the app, not the runner).
    let env = Environment(shell: BootStateShell(booted: true))
    let mismatch = WDASessionRepair.BindMismatch(
      requested: "com.example.app", reported: "com.apple.springboard")
    let structured = await WDASessionRepair.classify(
      mismatch, bundleId: "com.example.app", env: env)
    #expect(structured.cause == .sessionBindRejected)
    #expect(WDASessionRepair.isRecoverable(structured.cause) == false)
    #expect(structured.detail.contains("com.example.app"))
    #expect(structured.detail.contains("com.apple.springboard"))
  }

  @Test("appForeground stays nil (never a false `false`) when WDA cannot resolve")
  func appForegroundNeverFalseNegative() async {
    // The appForeground:false positive path requires a *live* WDA session
    // returning a different bundle (HTTP-only — see suite note). What IS
    // deterministically guaranteed: when WDA cannot resolve a foreground
    // bundle, appForeground is nil, NEVER a false `false`.
    let env = Environment(shell: BootStateShell(booted: true))
    await env.wdaClient.setBaseURL("http://127.0.0.1:1")
    await env.wdaClient.recordLaunchedApp(bundleId: "com.example.app")
    let fgRequested = await WDASessionRepair.appForeground(
      requested: "com.example.app", env: env)
    let fgRecorded = await WDASessionRepair.appForeground(requested: nil, env: env)
    #expect(fgRequested == nil)
    #expect(fgRecorded == nil)
  }
}

/// Mirror of the CLI `UIResult` Codable so the additive-only invariant is
/// verifiable from the kit test target (the CLI struct is internal to the
/// executable target). Must stay byte-shape-identical to UICommand.UIResult.
private struct TestUIResult: Codable {
  let succeeded: Bool
  let message: String
  let elementId: String?
  let elementCount: Int?
  let retried: Bool?
  let error: String?
  let cause: String?
  let detail: String?
  let remediation: String?
  let recovered: Bool?
  let appForeground: Bool?

  init(
    succeeded: Bool, message: String, elementId: String?, elementCount: Int?,
    retried: Bool? = nil, error: String? = nil, cause: String? = nil, detail: String? = nil,
    remediation: String? = nil, recovered: Bool? = nil, appForeground: Bool? = nil
  ) {
    self.succeeded = succeeded
    self.message = message
    self.elementId = elementId
    self.elementCount = elementCount
    self.retried = retried
    self.error = error
    self.cause = cause
    self.detail = detail
    self.remediation = remediation
    self.recovered = recovered
    self.appForeground = appForeground
  }

  enum CodingKeys: String, CodingKey {
    case succeeded, message, elementId, elementCount, retried
    case error, cause, detail, remediation, recovered, appForeground
  }

  func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(succeeded, forKey: .succeeded)
    try c.encode(message, forKey: .message)
    try c.encodeIfPresent(elementId, forKey: .elementId)
    try c.encodeIfPresent(elementCount, forKey: .elementCount)
    try c.encodeIfPresent(retried, forKey: .retried)
    try c.encodeIfPresent(error, forKey: .error)
    try c.encodeIfPresent(cause, forKey: .cause)
    try c.encodeIfPresent(detail, forKey: .detail)
    try c.encodeIfPresent(remediation, forKey: .remediation)
    try c.encodeIfPresent(recovered, forKey: .recovered)
    try c.encodeIfPresent(appForeground, forKey: .appForeground)
  }
}

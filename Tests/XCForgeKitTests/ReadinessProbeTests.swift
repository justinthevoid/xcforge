import Foundation
import Testing

@testable import XCForgeKit

/// Shell that never reaches a real simulator — all subprocess calls return
/// empty success. Used to exercise probe timing/grammar without network/sim.
private actor InertShell: ShellExecutor {
  nonisolated func run(
    _ executable: String, arguments: [String], workingDirectory: String?,
    environment: [String: String]?, timeout: TimeInterval, outputLimit: Int
  ) async throws -> ShellResult {
    ShellResult(stdout: "", stderr: "", exitCode: 0)
  }

  nonisolated func xcrun(timeout: TimeInterval, arguments: [String]) async throws -> ShellResult {
    ShellResult(stdout: "{\"devices\":{}}", stderr: "", exitCode: 0)
  }

  nonisolated func git(_ arguments: [String], workingDirectory: String, timeout: TimeInterval)
    async throws -> ShellResult
  {
    ShellResult(stdout: "", stderr: "", exitCode: 0)
  }
}

@Suite("readiness probe")
struct ReadinessProbeTests {

  // MARK: - Signal grammar

  @Test("parses launch-complete / a11y / text and composes with comma")
  func signalGrammar() {
    #expect(ReadinessProbe.Signal.parse("launch-complete") == .launchComplete)
    #expect(ReadinessProbe.Signal.parse("a11y:home.title") == .a11y("home.title"))
    #expect(ReadinessProbe.Signal.parse("text:Welcome back") == .text("Welcome back"))

    let list = ReadinessProbe.Signal.parseList("launch-complete, a11y:x , text:y")
    #expect(list == [.launchComplete, .a11y("x"), .text("y")])
  }

  @Test("rejects empty / malformed / value-less tokens and de-dupes")
  func signalGrammarRejects() {
    #expect(ReadinessProbe.Signal.parse("") == nil)
    // Bare prefix with an empty remainder is invalid (fix #7).
    #expect(ReadinessProbe.Signal.parse("a11y:") == nil)
    #expect(ReadinessProbe.Signal.parse("text:") == nil)
    #expect(ReadinessProbe.Signal.parse("bogus") == nil)
    // Unknown tokens dropped; duplicates collapsed.
    #expect(ReadinessProbe.Signal.parseList("a11y:x,bogus,a11y:x") == [.a11y("x")])
    #expect(ReadinessProbe.Signal.parseList("") == [])
  }

  @Test("parseSpec distinguishes empty spec from all-unparseable spec")
  func parseSpecUnparseableTracking() {
    // Genuinely empty / whitespace → no signals requested (NOT unparseable).
    let empty = ReadinessProbe.Signal.parseSpec("")
    #expect(empty.signals.isEmpty)
    #expect(empty.allUnparseable == false)
    let blank = ReadinessProbe.Signal.parseSpec("   ")
    #expect(blank.signals.isEmpty)
    #expect(blank.allUnparseable == false)
    // Non-empty but every token unparseable → flagged.
    let bad = ReadinessProbe.Signal.parseSpec("bogus,a11y:,text:")
    #expect(bad.signals.isEmpty)
    #expect(bad.allUnparseable == true)
    // At least one valid token → not unparseable.
    let mixed = ReadinessProbe.Signal.parseSpec("bogus,a11y:x")
    #expect(mixed.signals == [.a11y("x")])
    #expect(mixed.allUnparseable == false)
  }

  @Test("text: comma-split grammar is consistent (no silent wrong partial)")
  func textCommaSplitGrammar() {
    // `,` is the only separator (documented). A text value with a comma is
    // split into separate signals — it must NOT silently truncate to one
    // wrong partial match. "text:a, b" → signals text:a and (trimmed) "b"
    // which is unparseable and dropped; text:a still parsed (consistent).
    let parsed = ReadinessProbe.Signal.parseSpec("text:hello, world")
    #expect(parsed.signals == [.text("hello")])
    #expect(parsed.allUnparseable == false)
  }

  @Test("raw round-trips the wire form")
  func signalRaw() {
    #expect(ReadinessProbe.Signal.launchComplete.raw == "launch-complete")
    #expect(ReadinessProbe.Signal.a11y("id").raw == "a11y:id")
    #expect(ReadinessProbe.Signal.text("sub").raw == "text:sub")
  }

  // MARK: - Empty signals → trivially ready (fast path, ≤ one interval)

  @Test("no signals → ready immediately, mode axp, elapsed 0")
  func emptySignalsReady() async {
    let env = Environment(shell: InertShell())
    let r = await ReadinessProbe.waitReady(signals: [], timeout: 20, env: env)
    #expect(r.ready == true)
    #expect(r.mode == .axp)
    #expect(r.elapsedMs == 0)
    #expect(r.satisfied.isEmpty)
  }

  // MARK: - timeout 0 = pass-through SKIP (legacy delay-0 parity, fix #4)

  @Test("timeout 0 skips the gate as a PASS-THROUGH: ready:true, reason set")
  func timeoutZeroPassThrough() async {
    let env = Environment(shell: InertShell())
    let r = await ReadinessProbe.waitReady(
      signals: [.a11y("x")], timeout: 0, env: env)
    // Mirrors pose `screenshotDelay == 0` which proceeds (does NOT fail) — so
    // `wait-ready --timeout 0 && …` composes (exit 0).
    #expect(r.ready == true)
    #expect(r.reason != nil)
    #expect(r.reason?.contains("pass-through") == true)
  }

  @Test("non-finite timeout is treated as 0 → pass-through ready (no UInt64 trap)")
  func nonFiniteTimeout() async {
    let env = Environment(shell: InertShell())
    let r = await ReadinessProbe.waitReady(
      signals: [.a11y("x")], timeout: .infinity, env: env)
    #expect(r.ready == true)
  }

  // MARK: - Non-empty but unparseable spec → NOT ready (fix #3)

  @Test("non-empty unparseable spec → not ready + 'no valid signals' reason")
  func unparseableSpecNotReady() async {
    let env = Environment(shell: InertShell())
    // A real (non-zero) timeout so this is not the pass-through path.
    let r = await ReadinessProbe.waitReady(
      signals: [], timeout: 20, specWasUnparseable: true, env: env)
    #expect(r.ready == false)
    #expect(r.mode == .degraded)
    #expect(r.reason?.contains("no valid signals parsed") == true)
  }

  @Test("WaitReadyTools: unparseable spec exits not-ready (standalone non-zero)")
  func waitReadyToolsUnparseable() async {
    let env = Environment(shell: InertShell())
    let exec = await WaitReadyTools.executeWaitReady(
      signalSpec: "bogus,a11y:,text:", timeout: 20, env: env)
    #expect(exec.ready == false)
    #expect(exec.signals.isEmpty)
    #expect(exec.mode == "degraded")
    #expect(exec.reason?.contains("no valid signals") == true)
  }

  // MARK: - pollMs clamp: huge value must not overflow-trap (fix #2)

  @Test("huge pollMs does not overflow-trap; clamped, deadline still honored")
  func hugePollMsDoesNotTrap() async {
    let env = Environment(shell: InertShell())
    // `launch-complete` + a recorded bundle resolves only via
    // verifyActiveBundleId() — no per-iteration HTTP findElement/AXP — so the
    // poll-clamp arithmetic is exercised with fast evals (no live-WDA hang).
    // UInt64(Int.max) * 1_000_000 would trap; the [1, 60000] clamp prevents
    // the trap and the remaining-time clamp prevents overshooting the 0.3s
    // ceiling despite the absurd poll interval.
    await env.wdaClient.recordLaunchedApp(bundleId: "com.example.app")
    let r = await ReadinessProbe.waitReady(
      signals: [.launchComplete], timeout: 0.3, pollMs: .max, env: env)
    #expect(r.ready == false)
    // The deadline (0.3s) is still respected — the giant interval is clamped
    // to the remaining time, so we never sleep past the ceiling.
    #expect(r.elapsedMs < 5000)
  }

  // MARK: - launch-complete with no known target bundle (fix #5)

  @Test("launch-complete + no recorded bundle → degraded, explicit reason, no blind wait")
  func launchCompleteNoBundleShortCircuits() async {
    let env = Environment(shell: InertShell())
    // No recorded/active bundle (fresh standalone process). `launch-complete`
    // can never hold — the probe must surface that explicitly and NOT
    // blind-wait the whole timeout.
    let r = await ReadinessProbe.waitReady(
      signals: [.launchComplete], timeout: 30, pollMs: 50, env: env)
    #expect(r.ready == false)
    #expect(r.mode == .degraded)
    #expect(r.reason?.contains("launch-complete needs a known target app") == true)
    // Short-circuits — does NOT blind-wait toward the 30s deadline.
    #expect(r.elapsedMs < 1000)
  }

  // MARK: - Degraded: nothing detectable → blind wait, announced

  @Test("launch-complete + recorded bundle but WDA unreachable → degraded blind wait")
  func degradedWhenNothingDetectable() async {
    let env = Environment(shell: InertShell())
    // Record a bundle so the no-target short-circuit (fix #5) does NOT apply;
    // launch-complete then resolves only via verifyActiveBundleId() which
    // returns nil with no session/network (never throws, never functions).
    // Deterministic regardless of AX-trust (launch-complete never uses AXP).
    await env.wdaClient.recordLaunchedApp(bundleId: "com.example.app")
    let r = await ReadinessProbe.waitReady(
      signals: [.launchComplete], timeout: 0.3, pollMs: 50, env: env)
    #expect(r.ready == false)
    #expect(r.mode == .degraded)
    #expect(r.reason != nil)
    // The blind wait runs to (roughly) the deadline — never instant.
    #expect(r.elapsedMs >= 200)
  }

  // MARK: - Cancellation aware

  @Test("cancelled probe returns not-ready without ever reporting ready")
  func cancellationAware() async {
    let env = Environment(shell: InertShell())
    // Record a bundle so launch-complete enters the deadline-bounded loop
    // (rather than the fix #5 no-target short-circuit) and we genuinely
    // exercise the cancellation path.
    await env.wdaClient.recordLaunchedApp(bundleId: "com.example.app")
    let task = Task {
      await ReadinessProbe.waitReady(
        signals: [.launchComplete], timeout: 30, pollMs: 50, env: env)
    }
    // Cancel almost immediately; the loop checks Task.isCancelled / honors
    // Task.sleep cancellation.
    task.cancel()
    let r = await task.value
    #expect(r.ready == false)
    // Cancelled well before the 30s deadline.
    #expect(r.elapsedMs < 5000)
  }

  // MARK: - WaitReadyTools wrapper parity

  @Test("WaitReadyTools.executeWaitReady mirrors probe + echoes parsed signals")
  func waitReadyToolsParity() async {
    let env = Environment(shell: InertShell())
    // timeout 0 is now a pass-through (fix #4): a valid signal parsed
    // (`a11y:x`, `bogus` dropped) + timeout 0 → ready:true, signals echoed.
    let exec = await WaitReadyTools.executeWaitReady(
      signalSpec: "a11y:x,bogus", timeout: 0, env: env)
    #expect(exec.ready == true)
    #expect(exec.signals == ["a11y:x"])  // bogus dropped
  }

  @Test("empty spec → no signals → ready (additive, no behavior change)")
  func waitReadyToolsEmptySpec() async {
    let env = Environment(shell: InertShell())
    let exec = await WaitReadyTools.executeWaitReady(
      signalSpec: "", timeout: 5, env: env)
    #expect(exec.ready == true)
    #expect(exec.mode == "axp")
    #expect(exec.signals.isEmpty)
  }

  // MARK: - text: matches element label/value ONLY, never structural keys

  /// AXP `getSourceJSON` shape: a flat array of element dicts.
  private static let axpTree = """
    [{"identifier":"home.title","label":"Welcome back","type":"StaticText",\
    "value":"100","frame":{"x":0,"y":0,"width":320,"height":44}}]
    """

  /// WDA `getSource(format:"json")` shape: nested `value`/`children` tree.
  private static let wdaTree = """
    {"value":{"type":"Application","name":"App","children":[\
    {"type":"Button","label":"Sign In","rect":{"x":1,"y":2,"width":80,"height":30}}]}}
    """

  @Test("text: matches a real label/value substring (AXP + WDA shapes)")
  func textMatchesRealText() {
    #expect(ReadinessProbe.textMatches("Welcome", inSerializedTree: Self.axpTree))
    #expect(ReadinessProbe.textMatches("come ba", inSerializedTree: Self.axpTree))
    // value "100" is a matchable element value, so text:100 here is legit.
    #expect(ReadinessProbe.textMatches("100", inSerializedTree: Self.axpTree))
    #expect(ReadinessProbe.textMatches("Sign In", inSerializedTree: Self.wdaTree))
  }

  @Test("text: does NOT false-positive on structural keys / attribute names")
  func textRejectsStructuralKeyCollisions() {
    // `type`, `width`, `frame`, `identifier`, `rect` are STRUCTURAL — a
    // substring that only appears as a key or in geometry must NOT satisfy.
    #expect(!ReadinessProbe.textMatches("type", inSerializedTree: Self.axpTree))
    #expect(!ReadinessProbe.textMatches("width", inSerializedTree: Self.axpTree))
    #expect(!ReadinessProbe.textMatches("frame", inSerializedTree: Self.axpTree))
    #expect(!ReadinessProbe.textMatches("StaticText", inSerializedTree: Self.axpTree))
    // 320 only appears as a frame width (geometry) — not element text.
    #expect(!ReadinessProbe.textMatches("320", inSerializedTree: Self.axpTree))
    // WDA: "Application"/"Button" are `type` values (structural), `rect` is
    // geometry — none are matchable element text.
    #expect(!ReadinessProbe.textMatches("Application", inSerializedTree: Self.wdaTree))
    #expect(!ReadinessProbe.textMatches("Button", inSerializedTree: Self.wdaTree))
    #expect(!ReadinessProbe.textMatches("rect", inSerializedTree: Self.wdaTree))
    #expect(!ReadinessProbe.textMatches("80", inSerializedTree: Self.wdaTree))
  }

  @Test("text: returns false on unparseable / empty needle (no raw-blob match)")
  func textMatchesGuards() {
    #expect(!ReadinessProbe.textMatches("Welcome", inSerializedTree: "not json"))
    #expect(!ReadinessProbe.textMatches("", inSerializedTree: Self.axpTree))
  }
}

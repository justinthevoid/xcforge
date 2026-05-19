import Foundation

/// Shared, WDA-session-independent launch-readiness primitive.
///
/// `pose`/`screenshot` historically raced cold launch: the only gate was a
/// WDA-coupled bundle-id-foreground poll with a blind-sleep fallback, so an
/// agent could screenshot the splash/Home and mis-diagnose. `ReadinessProbe`
/// gates on real signals instead:
///
/// 1. **AXP first** (`a11y:`/`text:`) — reads Simulator.app's accessibility
///    tree directly, no WDA *session* required (the session was the thing that
///    failed in the motivating incident). Deterministic when AX-trusted.
/// 2. **WDA fallback** — `findElement` for `a11y:`/`text:`,
///    `verifyActiveBundleId` for `launch-complete`. Used only when AXP is not
///    AX-trusted.
/// 3. **Degraded** — last resort: `launch-complete` best-effort + a residual
///    sleep of the remaining budget, reported as `mode: "degraded"` with a
///    one-line reason (never silently degrade).
///
/// The poll loop mirrors `WDAClient.pollForActiveBundleId`: ~150ms cadence,
/// deadline-bounded, `Task.isCancelled`-aware, timeout `isFinite`-guarded and
/// clamped to `[0, 60]`. `timeout 0` is a pass-through that **skips** the gate
/// (returns `ready: true`), mirroring the legacy pose `screenshotDelay == 0`
/// fast path so `wait-ready --timeout 0 && …` composes.
public enum ReadinessProbe {

  /// Cadence between probe iterations (matches `pollForActiveBundleId`).
  static let pollIntervalNs: UInt64 = 150_000_000

  /// Upper clamp for the timeout, in seconds (matches `pollForActiveBundleId`).
  static let maxTimeout: Double = 60

  /// Lower/upper clamp for an explicit `pollMs`, in ms. A huge value would
  /// overflow-trap `UInt64(pollMs) * 1_000_000`; a zero/negative one would
  /// busy-spin. Clamp to a sane band before any arithmetic.
  static let minPollMs = 1
  static let maxPollMs = 60_000

  // MARK: - Signal

  /// A single readiness predicate. Compose multiple with `,` (all must hold).
  ///
  /// Grammar note: `,` is the **only** separator. A `text:` value containing a
  /// comma is split into separate signals per this documented grammar (there
  /// is no escaping); the split tokens are still parsed/validated so the gate
  /// is consistent and reason-reported rather than a silent wrong match.
  public enum Signal: Equatable, Sendable {
    /// App process is foreground (the requested/launched bundle is active).
    case launchComplete
    /// An element with this accessibility id is present in the tree.
    case a11y(String)
    /// Any element label/value/name contains this substring.
    case text(String)

    /// The canonical wire form (`launch-complete`, `a11y:<id>`, `text:<sub>`).
    public var raw: String {
      switch self {
      case .launchComplete: return "launch-complete"
      case .a11y(let id): return "a11y:\(id)"
      case .text(let sub): return "text:\(sub)"
      }
    }

    /// Parse one token. Returns nil for an empty/malformed token (including a
    /// bare `a11y:`/`text:` prefix with an empty remainder).
    static func parse(_ token: String) -> Signal? {
      let trimmed = token.trimmingCharacters(in: .whitespaces)
      guard !trimmed.isEmpty else { return nil }
      if trimmed == "launch-complete" { return .launchComplete }
      if let range = trimmed.range(of: "a11y:"), range.lowerBound == trimmed.startIndex {
        let value = String(trimmed[range.upperBound...])
        return value.isEmpty ? nil : .a11y(value)
      }
      if let range = trimmed.range(of: "text:"), range.lowerBound == trimmed.startIndex {
        let value = String(trimmed[range.upperBound...])
        return value.isEmpty ? nil : .text(value)
      }
      return nil
    }

    /// Parse a comma-separated signal string into an ordered, de-duplicated
    /// list. Unknown/malformed tokens are dropped here; callers distinguish
    /// "no signals requested" (empty spec) from "signals requested but all
    /// unparseable" via `parseSpec`.
    public static func parseList(_ spec: String) -> [Signal] {
      parseSpec(spec).signals
    }

    /// Whether a non-empty spec yielded zero valid signals (i.e. every token
    /// was unparseable). Distinguishes a genuinely empty spec from one that
    /// requested signals but parsed none.
    public struct ParsedSpec: Sendable {
      public let signals: [Signal]
      /// True only when the trimmed spec was non-empty yet no token parsed.
      public let allUnparseable: Bool
    }

    /// Parse a spec, tracking whether a non-empty spec produced no valid
    /// signals (so the gate can report "no valid signals parsed" instead of
    /// silently treating it as "nothing to wait on").
    public static func parseSpec(_ spec: String) -> ParsedSpec {
      let trimmedSpec = spec.trimmingCharacters(in: .whitespaces)
      guard !trimmedSpec.isEmpty else {
        return ParsedSpec(signals: [], allUnparseable: false)
      }
      var seen: [Signal] = []
      for token in spec.split(separator: ",", omittingEmptySubsequences: true) {
        if let signal = parse(String(token)), !seen.contains(signal) {
          seen.append(signal)
        }
      }
      return ParsedSpec(signals: seen, allUnparseable: seen.isEmpty)
    }
  }

  // MARK: - Result

  public enum Mode: String, Codable, Sendable {
    case axp
    case wda
    case degraded
  }

  public struct ReadinessResult: Codable, Sendable {
    /// True when every requested signal held before the deadline.
    public let ready: Bool
    /// The signals (raw form) that were observed to hold.
    public let satisfied: [String]
    /// Wall-clock spent probing, in milliseconds.
    public let elapsedMs: Int
    /// Which detection path produced the verdict.
    public let mode: Mode
    /// One-line human reason — always set for `degraded`, else nil.
    public let reason: String?

    public init(
      ready: Bool, satisfied: [String], elapsedMs: Int, mode: Mode, reason: String? = nil
    ) {
      self.ready = ready
      self.satisfied = satisfied
      self.elapsedMs = elapsedMs
      self.mode = mode
      self.reason = reason
    }
  }

  // MARK: - Probe

  /// Wait until every signal holds, or the (clamped) timeout elapses.
  ///
  /// - Parameters:
  ///   - signals: predicates that must all hold; empty → immediately ready
  ///     (`mode: .axp`, nothing to wait on). NOTE: callers that need to
  ///     distinguish "empty spec" from "all-unparseable spec" should resolve
  ///     signals via `Signal.parseSpec` and pass `specWasUnparseable`.
  ///   - timeout: ceiling in seconds. Non-finite → treated as 0. Clamped to
  ///     `[0, 60]`. `0` is a pass-through that **skips** the gate
  ///     (`ready: true`), so `wait-ready --timeout 0 && …` composes.
  ///   - pollMs: cadence override in ms; clamped to `[1, 60000]` so an
  ///     adversarial value cannot overflow-trap or busy-spin.
  ///   - specWasUnparseable: true when a non-empty spec produced zero valid
  ///     signals — reported as not-ready/`.degraded` instead of trivially
  ///     ready.
  ///   - simulator: optional UDID/name to scope AXP/WDA queries (a name is
  ///     resolved to a UDID so the AXP tree cache keys consistently).
  ///   - env: injected dependencies (shell/AXP/WDA).
  public static func waitReady(
    signals: [Signal],
    timeout: Double,
    pollMs: Int = 150,
    specWasUnparseable: Bool = false,
    simulator: String? = nil,
    env: Environment
  ) async -> ReadinessResult {
    let start = DispatchTime.now()

    func elapsedMs() -> Int {
      Int((DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000)
    }

    // A non-empty spec that parsed to zero valid signals is NOT "nothing to
    // wait on" — it is a malformed request. Report not-ready/degraded so the
    // standalone command exits non-zero rather than silently passing.
    if specWasUnparseable {
      return ReadinessResult(
        ready: false,
        satisfied: [],
        elapsedMs: elapsedMs(),
        mode: .degraded,
        reason:
          "no valid signals parsed (`,` separates signals; `a11y:`/`text:` "
          + "need a non-empty value). Nothing to gate on."
      )
    }

    // No signals requested at all → trivially ready; no probing, no degraded
    // sleep. (Genuinely empty/whitespace spec keeps the fast path.)
    guard !signals.isEmpty else {
      return ReadinessResult(ready: true, satisfied: [], elapsedMs: 0, mode: .axp)
    }

    // Sanitize timeout exactly like pollForActiveBundleId: NaN/inf → 0, clamp.
    let clamped: Double = {
      guard timeout.isFinite, timeout > 0 else { return 0 }
      return min(timeout, maxTimeout)
    }()

    // timeout 0 → pass-through that SKIPS the gate (mirrors pose
    // `screenshotDelay == 0`, which proceeds rather than failing). Report
    // ready:true so `wait-ready --timeout 0` exits 0 and composes with `&&`.
    guard clamped > 0 else {
      return ReadinessResult(
        ready: true,
        satisfied: [],
        elapsedMs: elapsedMs(),
        mode: .degraded,
        reason: "Readiness gate skipped (timeout 0 = pass-through); not gated."
      )
    }

    // `launch-complete` with no known target bundle can NEVER hold (it is
    // "the recorded/active app is foreground" — there is no app to compare
    // against). Surface that explicitly instead of silently blind-waiting the
    // entire timeout. Only short-circuits when launch-complete is the *only*
    // signal — otherwise the a11y:/text: signals can still be satisfied.
    if signals == [.launchComplete] {
      let recorded = await env.wdaClient.getActiveBundleId()
      if recorded?.isEmpty != false {
        return ReadinessResult(
          ready: false,
          satisfied: [],
          elapsedMs: elapsedMs(),
          mode: .degraded,
          reason:
            "launch-complete needs a known target app (none recorded); "
            + "use a11y:/text: or run via pose."
        )
      }
    }

    // Resolve a simulator NAME to its UDID so the AXP tree cache keys the same
    // way regardless of whether the caller passed a name or a UDID. A failure
    // to resolve falls back to the raw value (best-effort, never hard-fails).
    let scopedUDID: String? = await {
      guard let simulator, !simulator.isEmpty else { return nil }
      return (try? await SimTools.resolveSimulator(simulator, env: env)) ?? simulator
    }()

    // Clamp the poll cadence BEFORE any arithmetic so a huge `--poll-ms`
    // cannot overflow-trap `UInt64 * 1_000_000`.
    let effectivePollMs = min(max(pollMs, minPollMs), maxPollMs)
    let cadenceNs: UInt64 = UInt64(effectivePollMs) * 1_000_000
    let startNs = DispatchTime.now().uptimeNanoseconds
    let deadline = startNs + UInt64(clamped * 1_000_000_000)

    let axpUsable = AXPBridge.isAvailable
    // Track whether AXP/WDA detectors were ever *exercised functionally*
    // across ALL evaluated signals — not just the ones that held. A signal
    // that fails must not hide the fact that a detector was actually working,
    // otherwise `mode` reports `.degraded` even though AXP/WDA answered.
    var sawAXP = false
    var sawWDA = false
    var axpFunctioned = false
    var wdaFunctioned = false

    while DispatchTime.now().uptimeNanoseconds < deadline {
      if Task.isCancelled {
        return ReadinessResult(
          ready: false, satisfied: [], elapsedMs: elapsedMs(), mode: .degraded,
          reason: "Readiness probe cancelled before all signals held.")
      }

      var allHold = true
      var satisfied: [String] = []

      for signal in signals {
        let outcome = await evaluate(
          signal, axpUsable: axpUsable, udid: scopedUDID, env: env)
        // Mode bookkeeping is updated regardless of whether THIS signal held
        // or which earlier signal failed.
        if outcome.axpFunctioned { axpFunctioned = true }
        if outcome.wdaFunctioned { wdaFunctioned = true }
        if outcome.held {
          satisfied.append(signal.raw)
          if outcome.via == .axp { sawAXP = true }
          if outcome.via == .wda { sawWDA = true }
        } else {
          allHold = false
          // Do NOT break: keep evaluating so detector bookkeeping reflects
          // every signal, not just up to the first failure.
        }
      }

      if allHold {
        // Prefer the strongest path actually exercised this round.
        let mode: Mode = sawAXP ? .axp : (sawWDA ? .wda : .axp)
        return ReadinessResult(
          ready: true, satisfied: satisfied, elapsedMs: elapsedMs(), mode: mode)
      }

      // Clamp the sleep to the remaining time-to-deadline so a large poll
      // interval cannot overshoot the timeout ceiling.
      let nowNs = DispatchTime.now().uptimeNanoseconds
      guard nowNs < deadline else { break }
      let remainingNs = deadline - nowNs
      let sleepNs = min(cadenceNs, remainingNs)
      do {
        try await Task.sleep(nanoseconds: sleepNs)
      } catch {
        return ReadinessResult(
          ready: false, satisfied: satisfied, elapsedMs: elapsedMs(), mode: .degraded,
          reason: "Readiness probe cancelled before all signals held.")
      }
    }

    // Deadline reached. `mode` must reflect whether a detector was actually
    // functioning, not whether a signal happened to hold — a working AXP/WDA
    // that simply never confirmed is a genuine timeout in that path, NOT a
    // blind degraded wait.
    if axpFunctioned || wdaFunctioned {
      let workingMode: Mode = axpFunctioned ? .axp : .wda
      return ReadinessResult(
        ready: false, satisfied: [], elapsedMs: elapsedMs(), mode: workingMode,
        reason: nil)
    }

    let why =
      axpUsable
      ? "Neither AXP nor WDA could confirm the signal(s) within the budget — proceeding degraded."
      : "AXP not AX-trusted and WDA unreachable — proceeding degraded after a blind wait."
    return ReadinessResult(
      ready: false, satisfied: [], elapsedMs: elapsedMs(), mode: .degraded, reason: why)
  }

  // MARK: - Signal Evaluation

  /// The outcome of evaluating one signal once: whether it held, which path
  /// proved it (for `mode` attribution), and — independently — whether the
  /// AXP/WDA detectors actually *functioned* (answered without throwing) so
  /// the final mode is not hidden by an unrelated failing signal.
  private struct SignalOutcome {
    let held: Bool
    let via: Mode
    let axpFunctioned: Bool
    let wdaFunctioned: Bool
  }

  /// Evaluate one signal once. All errors are warn-only — a probe iteration
  /// never throws.
  private static func evaluate(
    _ signal: Signal, axpUsable: Bool, udid: String?, env: Environment
  ) async -> SignalOutcome {
    switch signal {
    case .launchComplete:
      // launch-complete reflects "the target app is foreground", which is a
      // WDA-derived fact (verifyActiveBundleId) — AXP traverses the whole
      // Simulator.app tree and cannot answer "which app is foreground".
      guard let want = await env.wdaClient.getActiveBundleId(), !want.isEmpty else {
        // No recorded/active target bundle (e.g. a fresh standalone CLI
        // process) — `launch-complete` can never hold. Surface it explicitly
        // instead of never-holding until the timeout.
        return SignalOutcome(
          held: false, via: .degraded, axpFunctioned: false, wdaFunctioned: false)
      }
      if let active = try? await env.wdaClient.verifyActiveBundleId() {
        return SignalOutcome(
          held: active == want, via: .wda, axpFunctioned: false, wdaFunctioned: true)
      }
      return SignalOutcome(
        held: false, via: .degraded, axpFunctioned: false, wdaFunctioned: false)

    case .a11y(let id):
      var axpFunctioned = false
      if axpUsable {
        if (try? await env.axpBridge.findElement(
          strategy: "accessibility id", value: id, udid: udid)) != nil
        {
          return SignalOutcome(
            held: true, via: .axp, axpFunctioned: true, wdaFunctioned: false)
        }
        // findElement throws only on not-found; reaching here means AXP
        // answered (it functioned), the element just is not present yet.
        axpFunctioned = AXPBridge.isAvailable
      }
      if (try? await env.wdaClient.findElement(using: "accessibility id", value: id)) != nil {
        return SignalOutcome(
          held: true, via: .wda, axpFunctioned: axpFunctioned, wdaFunctioned: true)
      }
      return SignalOutcome(
        held: false, via: .degraded, axpFunctioned: axpFunctioned, wdaFunctioned: false)

    case .text(let sub):
      var axpFunctioned = false
      var wdaFunctioned = false
      if axpUsable, let json = try? await env.axpBridge.getSourceJSON(udid: udid) {
        axpFunctioned = true
        if textMatches(sub, inSerializedTree: json) {
          return SignalOutcome(
            held: true, via: .axp, axpFunctioned: true, wdaFunctioned: false)
        }
      }
      if let source = try? await env.wdaClient.getSource(format: "json") {
        wdaFunctioned = true
        if textMatches(sub, inSerializedTree: source) {
          return SignalOutcome(
            held: true, via: .wda, axpFunctioned: axpFunctioned, wdaFunctioned: true)
        }
      }
      return SignalOutcome(
        held: false, via: .degraded, axpFunctioned: axpFunctioned,
        wdaFunctioned: wdaFunctioned)
    }
  }

  // MARK: - Text matching

  /// Whether `needle` appears in an element's textual content somewhere in the
  /// serialized accessibility tree (`getSourceJSON` array of dicts, or WDA's
  /// `{ "value": { children: [...] } }` source). Matches ONLY against text /
  /// label / value / name fields recursively — never structural keys,
  /// attribute names, coordinates, or the raw blob.
  static func textMatches(_ needle: String, inSerializedTree json: String) -> Bool {
    guard !needle.isEmpty, let data = json.data(using: .utf8) else { return false }
    guard let root = try? JSONSerialization.jsonObject(with: data) else { return false }
    return scanForText(root, needle: needle)
  }

  /// The element-textual keys whose *string values* `text:` may match. We do
  /// not match keys themselves nor any structural/geometry attribute.
  private static let matchableKeys: Set<String> = [
    "label", "value", "name", "title", "text", "placeholdervalue",
  ]

  private static func scanForText(_ node: Any, needle: String) -> Bool {
    if let dict = node as? [String: Any] {
      for (key, value) in dict {
        if let str = value as? String,
          matchableKeys.contains(key.lowercased()),
          str.contains(needle)
        {
          return true
        }
        // Recurse into nested containers regardless of key (children/subtree),
        // but only string *values under matchable keys* count as a match.
        if value is [Any] || value is [String: Any] {
          if scanForText(value, needle: needle) { return true }
        }
      }
      return false
    }
    if let array = node as? [Any] {
      for element in array where scanForText(element, needle: needle) {
        return true
      }
      return false
    }
    return false
  }
}

import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Which WDA backend to use for UI automation.
public enum WDABackend: String, Sendable {
  case xcForgeWDA  // Our own lightweight WDA replacement
  case originalWDA  // Facebook's WebDriverAgent

  public var bundleId: String {
    switch self {
    case .xcForgeWDA: return "com.xcforge.wda.runner.xctrunner"
    case .originalWDA: return "com.facebook.WebDriverAgentRunner.xctrunner"
    }
  }

  public var displayName: String {
    switch self {
    case .xcForgeWDA: return "xcforgeWDA"
    case .originalWDA: return "Original WDA (Facebook)"
    }
  }
}

/// Direct HTTP client for WebDriverAgent — no Appium overhead.
/// WDA runs on http://localhost:8100 by default.
/// Supports both xcforgeWDA and Original WDA with automatic fallback.
public actor WDAClient {
  public init() {}

  private var baseURL =
    ProcessInfo.processInfo.environment["WDA_BASE_URL"] ?? "http://localhost:8100"
  private var sessionId: String?
  private var knownSessionIds: [String] = []  // Track all created sessions

  /// Last bundleId requested for an active session. Persisted across recreates so
  /// `ensureSession()` and the mid-call retry path rebind the same app — without this,
  /// auto-bootstrapped sessions are unbound and WDA queries can't reach app-owned
  /// secondary windows (sheets, alerts, fullScreenCover).
  private var activeBundleId: String?

  /// Active WDA backend. Default: xcforgeWDA with fallback to Original WDA.
  public private(set) var backend: WDABackend = .xcForgeWDA

  /// Info message when fallback was triggered (nil = no fallback).
  public private(set) var fallbackInfo: String?

  /// Guard against concurrent deploys.
  private var isDeploying = false

  /// Handle to the background xcodebuild test process (for cleanup).
  private var deployTask: Task<Void, Never>?

  /// Default timeout for WDA requests (fast fail instead of endless hang)
  private let requestTimeout: TimeInterval = 10
  /// Quick timeout for health-check pings
  private let healthCheckTimeout: TimeInterval = 2

  // MARK: - Configuration

  public func setBaseURL(_ url: String) {
    self.baseURL = url
  }

  public func getBaseURL() -> String {
    return baseURL
  }

  func setBackend(_ newBackend: WDABackend) {
    self.backend = newBackend
    self.fallbackInfo = nil
  }

  // MARK: - HTTP Helpers

  private func request(
    method: String,
    path: String,
    body: [String: Any]? = nil,
    timeout: TimeInterval? = nil
  ) async throws -> (Data, Int) {
    let effectiveTimeout = timeout ?? requestTimeout
    let urlString = baseURL + path
    guard let url = URL(string: urlString) else {
      throw WDAError.invalidURL(urlString)
    }

    var req = URLRequest(url: url)
    req.httpMethod = method
    req.timeoutInterval = effectiveTimeout

    if let body = body {
      req.httpBody = try JSONSerialization.data(withJSONObject: body)
      req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }

    // Freeze request as let for safe capture in task group closures
    let finalReq = req
    let finalTimeout = effectiveTimeout

    // Hard timeout wrapper — guarantees we never hang longer than effectiveTimeout.
    // URLRequest.timeoutInterval only measures idle time between packets, not total duration.
    // If WDA accepts the connection but never responds, timeoutInterval may never fire.
    return try await withThrowingTaskGroup(of: (Data, Int).self) { group in
      group.addTask {
        let (data, response) = try await URLSession.shared.data(for: finalReq)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (data, statusCode)
      }
      group.addTask {
        try await Task.sleep(nanoseconds: UInt64(finalTimeout * 1_000_000_000))
        throw WDAError.wdaNotResponding
      }
      defer { group.cancelAll() }
      guard let result = try await group.next() else {
        throw WDAError.wdaNotResponding
      }
      return result
    }
  }

  private func jsonRequest(
    method: String,
    path: String,
    body: [String: Any]? = nil
  ) async throws -> [String: Any] {
    let (data, statusCode) = try await request(method: method, path: path, body: body)

    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      let text = String(data: data, encoding: .utf8) ?? "?"
      throw WDAError.invalidResponse("Status \(statusCode): \(text)")
    }

    if statusCode >= 400 {
      let errorMsg = (json["value"] as? [String: Any])?["message"] as? String ?? "\(json)"
      throw WDAError.wdaError(statusCode, errorMsg)
    }

    return json
  }

  // MARK: - Health Check & Auto-Restart

  /// Ping WDA /status with a fast 2s timeout. Returns true if WDA is responsive.
  public func isHealthy() async -> Bool {
    do {
      let (_, statusCode) = try await request(
        method: "GET", path: "/status", timeout: healthCheckTimeout)
      return statusCode < 400
    } catch {
      return false
    }
  }

  /// Restart current backend by terminating and relaunching the xctrunner on the given simulator.
  func restartWDA(simulator: String = "booted") async throws {
    let bid = backend.bundleId
    // Kill any lingering WDA process
    let _ = try? await Shell.xcrun(timeout: 5, "simctl", "terminate", simulator, bid)

    // Clean up port 8100 — prevents binding conflicts when old WDA left the port occupied.
    // This was previously only done in deployXCForgeWDA, causing restartWDA to fail silently.
    await cleanupPort8100()

    // Pause for clean shutdown and port release (0.5s was too short for TIME_WAIT)
    try await Task.sleep(nanoseconds: 1_000_000_000)  // 1s

    // Relaunch WDA with explicit timeout
    let result = try await Shell.xcrun(timeout: 10, "simctl", "launch", simulator, bid)
    guard result.succeeded else {
      throw WDAError.wdaRestart("Failed to restart \(backend.displayName): \(result.stderr)")
    }
    // Wait for WDA to become ready (poll up to 10s)
    for _ in 0..<20 {
      try await Task.sleep(nanoseconds: 500_000_000)  // 0.5s
      if await isHealthy() {
        sessionId = nil
        knownSessionIds.removeAll()  // All old sessions are invalid after restart
        return
      }
    }
    throw WDAError.wdaRestart(
      "\(backend.displayName) did not become ready within 10s after restart")
  }

  /// Kill any process holding port 8100 to prevent binding conflicts.
  private func cleanupPort8100() async {
    if let result = try? await Shell.run("/usr/bin/lsof", arguments: ["-ti", ":8100"], timeout: 5),
      result.succeeded, !result.stdout.isEmpty
    {
      for pidStr in result.stdout.split(separator: "\n") {
        if let pid = Int32(pidStr.trimmingCharacters(in: .whitespaces)) {
          kill(pid, SIGKILL)
        }
      }
      try? await Task.sleep(nanoseconds: 300_000_000)  // 0.3s for port release
    }
  }

  /// Kill any WDA process on port 8100 and terminate known runners.
  private func cleanupWDAProcesses(simulator: String) async {
    let _ = try? await Shell.xcrun(
      timeout: 5, "simctl", "terminate", simulator, WDABackend.xcForgeWDA.bundleId)
    let _ = try? await Shell.xcrun(
      timeout: 5, "simctl", "terminate", simulator, WDABackend.originalWDA.bundleId)
    await cleanupPort8100()
  }

  /// Deploy xcforgeWDA to the simulator: build-for-testing + start via xcodebuild test.
  /// Returns true if deploy succeeded and server is healthy, false otherwise.
  /// If a deploy is already in progress, waits for it instead of starting a new one.
  func deployXCForgeWDA(simulator: String = "booted") async -> Bool {
    // H3 fix: If another deploy is in progress, wait for it instead of triggering premature fallback.
    // Actor isolation guarantees isDeploying is checked atomically (no await before the set).
    if isDeploying {
      Log.warn("deployXCForgeWDA: concurrent call detected, waiting for existing deploy")
      for i in 1...15 {
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        if await isHealthy() {
          Log.warn("deployXCForgeWDA: existing deploy succeeded after \(i * 2)s wait")
          return true
        }
      }
      Log.warn("deployXCForgeWDA: existing deploy did not succeed within 30s")
      return false
    }

    isDeploying = true
    defer { isDeploying = false }

    // H2 fix: Kill lingering processes before deploy (not just Task.cancel)
    deployTask?.cancel()
    deployTask = nil
    await cleanupWDAProcesses(simulator: simulator)

    // Find xcforgeWDA project — check env var first, then common relative location
    let projectDir: String
    if let envDir = ProcessInfo.processInfo.environment["XCFORGE_WDA_DIR"],
      FileManager.default.fileExists(atPath: envDir + "/xcforgeWDA.xcodeproj")
    {
      projectDir = envDir
    } else {
      // Search order: CWD-relative (developer running from a clone) → Homebrew share dirs.
      let candidates = [
        FileManager.default.currentDirectoryPath + "/xcforgeWDA",
        FileManager.default.currentDirectoryPath + "/../xcforgeWDA",
        "/opt/homebrew/share/xcforge/xcforgeWDA",
        "/usr/local/share/xcforge/xcforgeWDA",
      ]
      guard
        let found = candidates.first(where: {
          FileManager.default.fileExists(atPath: $0 + "/xcforgeWDA.xcodeproj")
        })
      else {
        return false
      }
      projectDir = found
    }

    // Resolve UDID for xcodebuild destination
    let udid = await resolveSimulatorUDID(simulator)

    // Deterministic DerivedData so we know where xctestrun lands
    let derivedData = NSHomeDirectory() + "/Library/Developer/Xcode/DerivedData/xcforgeWDA-deploy"

    // Step 1: build-for-testing with -scheme (resolves SPM) + -sdk (Xcode 26
    // workaround: -scheme can't find iOS Simulator destinations for UI testing
    // bundles, but -sdk iphonesimulator without -destination/-arch works)
    let buildArgs = [
      "xcodebuild", "build-for-testing",
      "-project", "\(projectDir)/xcforgeWDA.xcodeproj",
      "-scheme", "xcforgeWDARunner",
      "-sdk", "iphonesimulator",
      "-configuration", "Debug",
      "-derivedDataPath", derivedData,
    ]
    let buildResult: ShellResult
    do {
      buildResult = try await Shell.run("/usr/bin/xcrun", arguments: buildArgs, timeout: 120)
    } catch {
      Log.warn("deployXCForgeWDA build error: \(error)")
      return false
    }
    guard buildResult.succeeded else {
      Log.warn("deployXCForgeWDA build failed: \(buildResult.stderr.prefix(500))")
      return false
    }

    // Step 2: Find xctestrun file and start test-without-building
    let xctestrun = await findXctestrun(derivedData: derivedData)
    guard let xctestrun else {
      Log.warn("deployXCForgeWDA: no xctestrun file found in \(derivedData)")
      return false
    }

    let testArgs = [
      "xcodebuild", "test-without-building",
      "-xctestrun", xctestrun,
      "-destination", "id=\(udid)",
    ]
    deployTask = Task.detached {
      _ = try? await Shell.run("/usr/bin/xcrun", arguments: testArgs, timeout: 3600)
    }

    // Step 3: Poll for server readiness (up to 30s)
    for _ in 1...15 {
      try? await Task.sleep(nanoseconds: 2_000_000_000)  // 2s
      if await isHealthy() {
        return true
      }
    }
    return false
  }

  /// Find the xctestrun file in DerivedData/Build/Products.
  private func findXctestrun(derivedData: String) async -> String? {
    let productsDir = derivedData + "/Build/Products"
    if let result = try? await Shell.run(
      "/usr/bin/find",
      arguments: [
        productsDir, "-maxdepth", "1", "-name", "*.xctestrun", "-type", "f",
      ], timeout: 5), result.succeeded
    {
      let files = result.stdout.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
      return files.first
    }
    return nil
  }

  /// Resolve simulator identifier to actual UDID.
  private func resolveSimulatorUDID(_ simulator: String) async -> String {
    guard simulator == "booted" else { return simulator }
    let shellResult: ShellResult
    do {
      shellResult = try await Shell.xcrun(timeout: 15, "simctl", "list", "devices", "booted", "-j")
    } catch {
      Log.warn("WDA resolveSimulatorUDID failed: \(error)")
      return simulator
    }
    guard shellResult.succeeded,
      let data = shellResult.stdout.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let devices = json["devices"] as? [String: [[String: Any]]]
    else {
      return simulator
    }
    for (_, sims) in devices {
      for sim in sims {
        if let state = sim["state"] as? String, state == "Booted",
          let udid = sim["udid"] as? String
        {
          return udid
        }
      }
    }
    return simulator
  }

  /// Health-check with auto-restart and fallback chain.
  /// Always tries in fixed order: healthy? → restart current → deploy xcforgeWDA → fallback Original WDA.
  /// H1 fix: Backend state is only updated AFTER confirming which backend is actually running.
  public func ensureWDARunning(simulator: String = "booted") async throws {
    // 1. Already healthy? Done — whatever backend is active, it works.
    if await isHealthy() { return }

    // 2. Try restarting current backend
    do {
      try await restartWDA(simulator: simulator)
      return
    } catch {
      // Restart failed, continue with fallback chain
    }

    // 3. Always try xcforgeWDA deploy (preferred backend)
    backend = .xcForgeWDA
    fallbackInfo = nil
    if await deployXCForgeWDA(simulator: simulator) {
      sessionId = nil
      return
    }

    // 4. xcforgeWDA deploy failed → fallback to Original WDA
    backend = .originalWDA
    fallbackInfo = "xcforgeWDA not available — using Original WDA as fallback"
    sessionId = nil

    if await isHealthy() { return }
    do {
      try await restartWDA(simulator: simulator)
      return
    } catch {
      // Original WDA also failed
    }

    // 5. Nothing works
    throw WDAError.noBackendAvailable
  }

  // MARK: - Session Management

  /// Number of tracked sessions (for leak detection)
  public var sessionCount: Int { knownSessionIds.count }

  /// Warning message if too many sessions are open, nil otherwise.
  public var sessionWarning: String? {
    knownSessionIds.count > 2
      ? "⚠️ \(knownSessionIds.count) WDA sessions tracked. Consider deleting unused sessions to avoid resource leaks."
      : nil
  }

  /// Read the bundleId currently bound to recreated sessions (nil when unbound).
  public func getActiveBundleId() -> String? { activeBundleId }

  /// Clear any persisted bundleId; subsequent recreates will produce unbound sessions.
  public func clearActiveBundleId() { activeBundleId = nil }

  public func createSession(bundleId: String? = nil) async throws -> String {
    // Reject empty/whitespace bundleIds — silently storing one would poison every
    // future recreate with a request WDA cannot satisfy.
    let normalizedRequested: String? =
      bundleId?.trimmingCharacters(in: .whitespaces).isEmpty == false
      ? bundleId : nil
    let effectiveBundleId = normalizedRequested ?? activeBundleId
    var capabilities: [String: Any] = [:]
    if let bid = effectiveBundleId {
      capabilities["bundleId"] = bid
    }

    let body: [String: Any] = [
      "capabilities": [
        "alwaysMatch": capabilities
      ]
    ]

    let json = try await jsonRequest(method: "POST", path: "/session", body: body)

    guard
      let sessionId = json["sessionId"] as? String
        ?? (json["value"] as? [String: Any])?["sessionId"] as? String
    else {
      throw WDAError.noSession
    }

    self.sessionId = sessionId
    if !knownSessionIds.contains(sessionId) {
      knownSessionIds.append(sessionId)
    }
    // Persist only after the POST returns a session id. Doing this before the call
    // would let a failed first attempt leave a poisoned `activeBundleId` for every
    // subsequent recreate — including against an app WDA already rejected.
    if let bid = normalizedRequested {
      activeBundleId = bid
    }
    return sessionId
  }

  /// Returns the CFBundleIdentifier reported by WDA for the active session, or nil if
  /// none. Use after `createSession(bundleId:)` to confirm the binding actually took
  /// effect — WDA accepts the capability silently even when activation fails.
  public func verifyActiveBundleId() async throws -> String? {
    guard let sid = sessionId else { return nil }
    let json = try await jsonRequest(method: "GET", path: "/session/\(sid)")
    let value = json["value"] as? [String: Any] ?? json
    if let caps = value["capabilities"] as? [String: Any] {
      if let bid = caps["CFBundleIdentifier"] as? String, !bid.isEmpty { return bid }
      if let bid = caps["bundleId"] as? String, !bid.isEmpty { return bid }
    }
    if let bid = value["CFBundleIdentifier"] as? String, !bid.isEmpty { return bid }
    return nil
  }

  /// Record the bundle id of the most recently launched app (e.g. via `simctl launch`)
  /// so the next implicit `ensureSession()` carries it as a `bundleId` capability. Without
  /// this hint, WDA defaults to activating Springboard whenever `ensureSession()` has to
  /// auto-create a session — silently backgrounding the user's app on the first `ui ls`.
  /// If the bundle changes from a previously recorded one, invalidate the cached
  /// `sessionId` so the next `ensureSession()` rebinds — otherwise the actor's quick
  /// session-health check would happily reuse a session bound to the *old* bundle and
  /// poll/queries would target the wrong app. WDA reaps the orphaned session via its
  /// session timeout; no DELETE call needed here. No network I/O.
  public func recordLaunchedApp(bundleId: String) {
    let trimmed = bundleId.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return }
    if activeBundleId != trimmed {
      sessionId = nil
    }
    activeBundleId = trimmed
  }

  /// Poll `verifyActiveBundleId()` until it returns `target` or `budget` seconds elapse.
  /// Used by `pose` to wait for the app to actually become foreground after a cold launch
  /// instead of relying on a fixed sleep. Cadence ~150ms. Errors during polling are
  /// warn-only — caller falls back to a residual sleep when this returns false. Budget is
  /// clamped to [0, 60].
  public func pollForActiveBundleId(target: String, budget: TimeInterval) async -> Bool {
    let trimmed = target.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty, budget.isFinite else { return false }
    let clampedBudget = max(0, min(budget, 60))
    if clampedBudget == 0 { return false }
    let deadline = Date().addingTimeInterval(clampedBudget)
    let cadenceNs: UInt64 = 150_000_000
    if sessionId == nil {
      do {
        _ = try await ensureSession()
      } catch {
        Log.warn("pollForActiveBundleId: ensureSession failed: \(error)")
        return false
      }
    }
    while Date() < deadline {
      if Task.isCancelled { return false }
      do {
        if let active = try await verifyActiveBundleId(), active == trimmed {
          return true
        }
      } catch {
        Log.warn("pollForActiveBundleId: verify failed (continuing): \(error)")
      }
      do {
        try await Task.sleep(nanoseconds: cadenceNs)
      } catch {
        return false  // cancellation
      }
    }
    return false
  }

  @discardableResult
  func deleteSession() async -> Bool {
    guard let sid = sessionId else { return true }
    var didDeleteRemotely = true
    do {
      _ = try await request(method: "DELETE", path: "/session/\(sid)")
    } catch {
      didDeleteRemotely = false
      Log.warn("deleteSession(\(sid)) failed: \(error)")
    }
    knownSessionIds.removeAll { $0 == sid }
    sessionId = nil
    return didDeleteRemotely
  }

  public func ensureSession() async throws -> String {
    if let sid = sessionId {
      // Quick health check with fast timeout
      do {
        let (_, status) = try await request(
          method: "GET", path: "/session/\(sid)", timeout: healthCheckTimeout)
        if status < 400 { return sid }
      } catch {
        // Session check failed — WDA might be unresponsive
        // Try auto-restart before creating a new session
        try await ensureWDARunning()
      }
    } else {
      // No session yet — still check if WDA is alive before trying to create one
      // This prevents a 10s hang on createSession if WDA is dead
      try await ensureWDARunning()
    }
    return try await createSession()
  }

  /// True for the WebDriver "no such session" / "invalid session id" signature only.
  /// Conservative on purpose: connectivity errors and unrelated 4xx must not trigger retry.
  func isSessionDead(_ error: Error) -> Bool {
    guard case let WDAError.wdaError(status, msg) = error, status == 404 else { return false }
    let lower = msg.lowercased()
    return lower.contains("no such session") || lower.contains("invalid session id")
  }

  /// Run `op` with a freshly ensured session id. If `op` throws a session-dead error,
  /// invalidate `sessionId`, create a new session, and retry `op` exactly once.
  /// A session-dead error means WDA accepted the request and rejected the session id —
  /// WDA itself is alive, so `createSession()` is sufficient (no full restart cycle needed).
  private func withSessionRetry<T>(
    _ op: (String) async throws -> sending T
  ) async throws -> sending T {
    let sid = try await ensureSession()
    do {
      return try await op(sid)
    } catch let err where isSessionDead(err) {
      Log.warn("WDA session expired mid-call; recreating and retrying once")
      sessionId = nil
      let newSid = try await createSession()
      return try await op(newSid)
    }
  }

  // MARK: - Element Finding

  public func findElement(
    using strategy: String, value: String, scroll: Bool = false, direction: String = "auto",
    maxSwipes: Int = 10
  ) async throws -> (elementId: String, swipes: Int) {
    try await withSessionRetry { sid in
      var body: [String: Any] = ["using": strategy, "value": value]
      if scroll {
        body["scroll"] = true
        body["direction"] = direction
        body["maxSwipes"] = maxSwipes
      }
      let json = try await self.jsonRequest(
        method: "POST",
        path: "/session/\(sid)/element",
        body: body
      )

      guard let element = json["value"] as? [String: Any],
        let elementId = element["ELEMENT"] as? String ?? element.values.first as? String
      else {
        throw WDAError.elementNotFound(strategy, value)
      }
      let swipes = element["swipes"] as? Int ?? 0
      return (elementId, swipes)
    }
  }

  public func findElements(using strategy: String, value: String) async throws -> [String] {
    try await withSessionRetry { sid in
      let json = try await self.jsonRequest(
        method: "POST",
        path: "/session/\(sid)/elements",
        body: ["using": strategy, "value": value]
      )

      guard let elements = json["value"] as? [[String: Any]] else { return [] }
      return elements.compactMap { elem in
        elem["ELEMENT"] as? String ?? elem.values.first as? String
      }
    }
  }

  // MARK: - Element Interaction (not wrapped in withSessionRetry)
  //
  // These methods accept an element id captured under the *current* session. If the session
  // dies between find and use, recreating the session would invalidate the element id and the
  // retry would fail with "no such element" — a less truthful error than "no such session".
  // We surface the original session-dead error so the caller can re-find and retry at a
  // higher level.

  public func click(elementId: String) async throws {
    let sid = try await ensureSession()
    _ = try await jsonRequest(method: "POST", path: "/session/\(sid)/element/\(elementId)/click")
  }

  public func getText(elementId: String) async throws -> String {
    let sid = try await ensureSession()
    let json = try await jsonRequest(
      method: "GET", path: "/session/\(sid)/element/\(elementId)/text")
    return json["value"] as? String ?? ""
  }

  public func setValue(elementId: String, text: String) async throws {
    let sid = try await ensureSession()
    _ = try await jsonRequest(
      method: "POST",
      path: "/session/\(sid)/element/\(elementId)/value",
      body: ["value": Array(text).map(String.init)]
    )
  }

  public func clearElement(elementId: String) async throws {
    let sid = try await ensureSession()
    _ = try await jsonRequest(method: "POST", path: "/session/\(sid)/element/\(elementId)/clear")
  }

  func getElementAttribute(_ attribute: String, elementId: String) async throws -> String {
    let sid = try await ensureSession()
    let json = try await jsonRequest(
      method: "GET", path: "/session/\(sid)/element/\(elementId)/attribute/\(attribute)")
    return json["value"] as? String ?? ""
  }

  public struct ElementRect: Sendable {
    public let x: Double, y: Double, width: Double, height: Double
  }

  public func getElementRect(elementId: String) async throws -> ElementRect {
    let sid = try await ensureSession()
    let json = try await jsonRequest(
      method: "GET", path: "/session/\(sid)/element/\(elementId)/rect")
    guard let value = json["value"] as? [String: Any],
      let x = value["x"] as? Double,
      let y = value["y"] as? Double,
      let w = value["width"] as? Double,
      let h = value["height"] as? Double
    else {
      throw WDAError.invalidResponse("Invalid element rect")
    }
    return ElementRect(x: x, y: y, width: w, height: h)
  }

  public struct WindowSize: Sendable {
    public let width: Double, height: Double
  }

  public func getWindowSize() async throws -> WindowSize {
    try await withSessionRetry { sid in
      let json = try await self.jsonRequest(method: "GET", path: "/session/\(sid)/window/size")
      guard let value = json["value"] as? [String: Any],
        let w = value["width"] as? Double,
        let h = value["height"] as? Double
      else {
        throw WDAError.invalidResponse("Invalid window size")
      }
      return WindowSize(width: w, height: h)
    }
  }

  // MARK: - Touch Actions (W3C Actions API)

  public func tap(x: Double, y: Double) async throws {
    try await withSessionRetry { sid in
      let actions: [String: Any] = [
        "actions": [
          [
            "type": "pointer",
            "id": "finger1",
            "parameters": ["pointerType": "touch"],
            "actions": [
              ["type": "pointerMove", "duration": 0, "x": Int(x), "y": Int(y)],
              ["type": "pointerDown", "button": 0],
              ["type": "pause", "duration": 50],
              ["type": "pointerUp", "button": 0],
            ],
          ]
        ]
      ]
      _ = try await self.jsonRequest(
        method: "POST", path: "/session/\(sid)/actions", body: actions)
    }
  }

  public func doubleTap(x: Double, y: Double) async throws {
    try await withSessionRetry { sid in
      let actions: [String: Any] = [
        "actions": [
          [
            "type": "pointer",
            "id": "finger1",
            "parameters": ["pointerType": "touch"],
            "actions": [
              ["type": "pointerMove", "duration": 0, "x": Int(x), "y": Int(y)],
              ["type": "pointerDown", "button": 0],
              ["type": "pause", "duration": 30],
              ["type": "pointerUp", "button": 0],
              ["type": "pause", "duration": 50],
              ["type": "pointerDown", "button": 0],
              ["type": "pause", "duration": 30],
              ["type": "pointerUp", "button": 0],
            ],
          ]
        ]
      ]
      _ = try await self.jsonRequest(
        method: "POST", path: "/session/\(sid)/actions", body: actions)
    }
  }

  public func longPress(x: Double, y: Double, durationMs: Int = 1000) async throws {
    try await withSessionRetry { sid in
      let actions: [String: Any] = [
        "actions": [
          [
            "type": "pointer",
            "id": "finger1",
            "parameters": ["pointerType": "touch"],
            "actions": [
              ["type": "pointerMove", "duration": 0, "x": Int(x), "y": Int(y)],
              ["type": "pointerDown", "button": 0],
              ["type": "pause", "duration": durationMs],
              ["type": "pointerUp", "button": 0],
            ],
          ]
        ]
      ]
      _ = try await self.jsonRequest(
        method: "POST", path: "/session/\(sid)/actions", body: actions)
    }
  }

  public func swipe(
    startX: Double, startY: Double, endX: Double, endY: Double, durationMs: Int = 300
  ) async throws {
    try await withSessionRetry { sid in
      let actions: [String: Any] = [
        "actions": [
          [
            "type": "pointer",
            "id": "finger1",
            "parameters": ["pointerType": "touch"],
            "actions": [
              ["type": "pointerMove", "duration": 0, "x": Int(startX), "y": Int(startY)],
              ["type": "pointerDown", "button": 0],
              ["type": "pointerMove", "duration": durationMs, "x": Int(endX), "y": Int(endY)],
              ["type": "pointerUp", "button": 0],
            ],
          ]
        ]
      ]
      _ = try await self.jsonRequest(
        method: "POST", path: "/session/\(sid)/actions", body: actions)
    }
  }

  public func pinch(centerX: Double, centerY: Double, scale: Double, durationMs: Int = 500)
    async throws
  {
    try await withSessionRetry { sid in
      let isZoomIn = scale > 1.0

      // Calculate finger offsets so the start/end distance ratio matches the requested scale.
      // Base offset = 50px (comfortable finger spacing). For zoom-in, fingers spread apart;
      // for zoom-out, fingers move closer together.
      let baseOffset = 50.0
      let startOffset = isZoomIn ? baseOffset : baseOffset * scale
      let endOffset = isZoomIn ? baseOffset * scale : baseOffset

      let finger1Start = (x: centerX, y: centerY - startOffset)
      let finger1End = (x: centerX, y: centerY - endOffset)
      let finger2Start = (x: centerX, y: centerY + startOffset)
      let finger2End = (x: centerX, y: centerY + endOffset)

      let actions: [String: Any] = [
        "actions": [
          [
            "type": "pointer",
            "id": "finger1",
            "parameters": ["pointerType": "touch"],
            "actions": [
              [
                "type": "pointerMove", "duration": 0, "x": Int(finger1Start.x),
                "y": Int(finger1Start.y),
              ],
              ["type": "pointerDown", "button": 0],
              [
                "type": "pointerMove", "duration": durationMs, "x": Int(finger1End.x),
                "y": Int(finger1End.y),
              ],
              ["type": "pointerUp", "button": 0],
            ],
          ],
          [
            "type": "pointer",
            "id": "finger2",
            "parameters": ["pointerType": "touch"],
            "actions": [
              [
                "type": "pointerMove", "duration": 0, "x": Int(finger2Start.x),
                "y": Int(finger2Start.y),
              ],
              ["type": "pointerDown", "button": 0],
              [
                "type": "pointerMove", "duration": durationMs, "x": Int(finger2End.x),
                "y": Int(finger2End.y),
              ],
              ["type": "pointerUp", "button": 0],
            ],
          ],
        ]
      ]
      _ = try await self.jsonRequest(
        method: "POST", path: "/session/\(sid)/actions", body: actions)
    }
  }

  // dragAndDrop accepts element ids in `sourceElement`/`targetElement`. Same caveat as
  // click(elementId:) — those ids are session-scoped, so we don't auto-retry on session death.
  public func dragAndDrop(
    sourceElement: String? = nil, targetElement: String? = nil,
    fromX: Double? = nil, fromY: Double? = nil,
    toX: Double? = nil, toY: Double? = nil,
    pressDurationMs: Int = 1000, holdDurationMs: Int = 300,
    velocity: Double? = nil
  ) async throws {
    let sid = try await ensureSession()
    var body: [String: Any] = [
      "pressDuration": Double(pressDurationMs) / 1000.0,
      "holdDuration": Double(holdDurationMs) / 1000.0,
    ]
    if let se = sourceElement { body["sourceElementId"] = se }
    if let te = targetElement { body["targetElementId"] = te }
    if let x = fromX { body["fromX"] = x }
    if let y = fromY { body["fromY"] = y }
    if let x = toX { body["toX"] = x }
    if let y = toY { body["toY"] = y }
    if let v = velocity { body["velocity"] = v }
    _ = try await jsonRequest(method: "POST", path: "/session/\(sid)/wda/drag", body: body)
  }

  // MARK: - Alert Handling

  public struct AlertInfo: Sendable {
    public let text: String
    public let buttons: [String]
  }

  public struct BatchAlertResult: Sendable {
    public let count: Int
    public let alerts: [AlertDetail]

    public struct AlertDetail: Sendable {
      public let text: String
      public let buttons: [String]
      public let source: String
    }
  }

  /// Get alert text. Returns nil if no alert is visible (404 from WDA) or on any error.
  /// Wrapped in withSessionRetry so a session-death between calls doesn't masquerade as
  /// "no alert"; on a true no-alert response WDA's 404 message is "no such alert", which
  /// `isSessionDead` does not match, so the retry path is not engaged.
  public func getAlertText() async -> AlertInfo? {
    do {
      return try await withSessionRetry { sid in
        let json = try await self.jsonRequest(
          method: "GET", path: "/session/\(sid)/alert/text")
        let text = json["value"] as? String ?? ""
        let buttons = json["buttons"] as? [String] ?? []
        return AlertInfo(text: text, buttons: buttons)
      }
    } catch {
      return nil
    }
  }

  /// Accept the current alert or all visible alerts.
  public func acceptAlert(buttonLabel: String? = nil, all: Bool = false) async throws -> AlertInfo? {
    try await withSessionRetry { sid in
      var body: [String: Any] = [:]
      if let label = buttonLabel { body["name"] = label }
      if all { body["all"] = true }

      let json = try await self.jsonRequest(
        method: "POST", path: "/session/\(sid)/alert/accept", body: body.isEmpty ? nil : body)
      let text = json["alertText"] as? String
      let buttons = json["buttons"] as? [String]
      if let text, let buttons {
        return AlertInfo(text: text, buttons: buttons)
      }
      return nil
    }
  }

  /// Dismiss the current alert or all visible alerts.
  public func dismissAlert(buttonLabel: String? = nil, all: Bool = false) async throws -> AlertInfo? {
    try await withSessionRetry { sid in
      var body: [String: Any] = [:]
      if let label = buttonLabel { body["name"] = label }
      if all { body["all"] = true }

      let json = try await self.jsonRequest(
        method: "POST", path: "/session/\(sid)/alert/dismiss", body: body.isEmpty ? nil : body)
      let text = json["alertText"] as? String
      let buttons = json["buttons"] as? [String]
      if let text, let buttons {
        return AlertInfo(text: text, buttons: buttons)
      }
      return nil
    }
  }

  /// Accept or dismiss all visible alerts in batch. Returns count + details.
  public func handleAllAlerts(accept: Bool) async throws -> BatchAlertResult {
    try await withSessionRetry { sid in
      let path = accept ? "/session/\(sid)/alert/accept" : "/session/\(sid)/alert/dismiss"
      let json = try await self.jsonRequest(method: "POST", path: path, body: ["all": true])

      guard let value = json["value"] as? [String: Any] else {
        return BatchAlertResult(count: 0, alerts: [])
      }
      let count = value["count"] as? Int ?? 0
      let alertDicts = value["alerts"] as? [[String: Any]] ?? []
      let alerts = alertDicts.map {
        BatchAlertResult.AlertDetail(
          text: $0["text"] as? String ?? "",
          buttons: $0["buttons"] as? [String] ?? [],
          source: $0["source"] as? String ?? ""
        )
      }
      return BatchAlertResult(count: count, alerts: alerts)
    }
  }

  // MARK: - View Hierarchy

  public func getSource(format: String = "json") async throws -> String {
    // Health check first — getSource bypasses session management, so fail fast if WDA is dead
    guard await isHealthy() else {
      throw WDAError.wdaNotResponding
    }
    let (data, statusCode) = try await request(method: "GET", path: "/source?format=\(format)")
    guard statusCode < 400 else {
      throw WDAError.invalidResponse("Source request failed with status \(statusCode)")
    }
    return String(data: data, encoding: .utf8) ?? ""
  }

  // MARK: - Screenshot via WDA

  func wdaScreenshot() async throws -> Data {
    try await withSessionRetry { sid in
      let json = try await self.jsonRequest(method: "GET", path: "/session/\(sid)/screenshot")
      guard let b64 = json["value"] as? String,
        let data = Data(base64Encoded: b64)
      else {
        throw WDAError.invalidResponse("Invalid screenshot data")
      }
      return data
    }
  }

  // MARK: - Pasteboard (Clipboard)

  public func getPasteboard(contentType: String = "plaintext") async throws -> String {
    try await withSessionRetry { sid in
      let json = try await self.jsonRequest(
        method: "POST",
        path: "/session/\(sid)/wda/pasteboard",
        body: ["contentType": contentType]
      )
      guard let value = json["value"] as? String else {
        return ""
      }
      // WDA returns base64-encoded pasteboard content
      if let data = Data(base64Encoded: value), let text = String(data: data, encoding: .utf8) {
        return text
      }
      return value
    }
  }

  public func setPasteboard(_ text: String, contentType: String = "plaintext") async throws {
    try await withSessionRetry { sid in
      let encoded = Data(text.utf8).base64EncodedString()
      _ = try await self.jsonRequest(
        method: "POST",
        path: "/session/\(sid)/wda/setPasteboard",
        body: ["content": encoded, "contentType": contentType]
      )
    }
  }

  // MARK: - Device Orientation

  func getOrientation() async throws -> String {
    try await withSessionRetry { sid in
      let json = try await self.jsonRequest(method: "GET", path: "/session/\(sid)/orientation")
      return json["value"] as? String ?? "PORTRAIT"
    }
  }

  func setOrientation(_ orientation: String) async throws -> String {
    try await withSessionRetry { sid in
      let json = try await self.jsonRequest(
        method: "POST",
        path: "/session/\(sid)/orientation",
        body: ["orientation": orientation]
      )
      return json["value"] as? String ?? orientation
    }
  }

  // MARK: - Status

  public struct WDAStatus: Sendable {
    public let ready: Bool
    public let bundleId: String
    public let raw: String
  }

  public func status() async throws -> WDAStatus {
    let json = try await jsonRequest(method: "GET", path: "/status")
    let value = json["value"] as? [String: Any]
    let ready = value?["ready"] as? Bool ?? false
    let bundleId = (value?["build"] as? [String: Any])?["productBundleIdentifier"] as? String ?? "?"
    let raw =
      String(
        data: (try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted))
          ?? Data(), encoding: .utf8) ?? ""
    return WDAStatus(ready: ready, bundleId: bundleId, raw: raw)
  }
}

// MARK: - Errors

/// Enumerated, machine-actionable root cause for a WDA session-create failure.
///
/// Surfaced in the structured `error/cause/detail/remediation` envelope so an
/// autonomous agent can recover instead of seeing the opaque
/// `ExitCode(rawValue: 1)`. Classification is by *cheap* state checks at the
/// failure site (DerivedData present? booted sim? :8100 reachable?) — see
/// `WDAClient.classifySessionCreateFailure`.
public enum WDASessionCause: String, Codable, Sendable {
  case wdaRunnerNotRunning = "wda_runner_not_running"
  case wdaRunnerBuildFailed = "wda_runner_build_failed"
  case noBootedSimulator = "no_booted_simulator"
  case bundleNotInstalled = "bundle_not_installed"
  case sessionBindRejected = "session_bind_rejected"
  case unknown = "unknown"

  /// A copy-pasteable remediation command for this cause.
  public var remediation: String {
    switch self {
    case .wdaRunnerNotRunning:
      return "xcforge ui status   # then re-run; auto-heal rebuilds & relaunches the WDA runner"
    case .wdaRunnerBuildFailed:
      return
        "rm -rf ~/Library/Developer/Xcode/DerivedData/xcforgeWDA-deploy && xcforge ui session"
    case .noBootedSimulator:
      return "xcforge sim boot <name-or-udid>   # boot a simulator, then retry"
    case .bundleNotInstalled:
      return "xcforge build run --simulator <sim>   # install the app, then retry"
    case .sessionBindRejected:
      return
        "Verify the bundle id is installed and runnable on the booted simulator, then retry"
    case .unknown:
      return "xcforge ui status   # inspect WDA; attach the raw detail when filing an issue"
    }
  }
}

/// Structured WDA session-create failure. Carries the enumerated cause, a
/// human detail (raw stderr/error when `unknown`), and a remediation command.
public struct WDASessionCreateError: Error, CustomStringConvertible, Sendable {
  public let cause: WDASessionCause
  public let detail: String

  public init(cause: WDASessionCause, detail: String) {
    self.cause = cause
    self.detail = detail
  }

  public var remediation: String { cause.remediation }

  public var description: String {
    "wda_session_create_failed (cause: \(cause.rawValue)) — \(detail). Remediation: \(remediation)"
  }
}

enum WDAError: Error, CustomStringConvertible {
  case invalidURL(String)
  case invalidResponse(String)
  case wdaError(Int, String)
  case noSession
  case elementNotFound(String, String)
  case wdaRestart(String)
  case wdaNotResponding
  case noBackendAvailable

  var description: String {
    switch self {
    case .invalidURL(let url): return "Invalid URL: \(url)"
    case .invalidResponse(let msg): return "Invalid response: \(msg)"
    case .wdaError(let code, let msg): return "WDA error \(code): \(msg)"
    case .noSession: return "No WDA session"
    case .elementNotFound(let strategy, let value): return "Element not found: \(strategy)=\(value)"
    case .wdaRestart(let msg): return "WDA restart failed: \(msg)"
    case .wdaNotResponding:
      return "WDA not responding (timeout >10s). Try: wda_create_session or restart the simulator."
    case .noBackendAvailable:
      return
        "No WDA backend available. Neither xcforgeWDA nor Original WDA could be started. Install xcforgeWDA or start WebDriverAgent."
    }
  }
}

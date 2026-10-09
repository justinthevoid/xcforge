import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// WebDriverAgent on a physical device: build, sign, launch, find its URL, stop.
///
/// The runner is built with the caller's development team, launched with
/// `xcodebuild test-without-building` in the background (devicectl cannot reliably launch
/// an XCTest runner), and reached over the CoreDevice tunnel address or the URL WDA logs.
/// One state file per device in `~/.xcforge/wda/` records the URL and the runner pid so
/// later CLI calls and other sessions can reuse it.
public enum DeviceWDA {

  public struct State: Codable, Sendable, Equatable {
    public let udid: String
    public let name: String?
    public let url: String
    public let pid: Int32
    public let logPath: String
    public let bundleID: String
    public let startedAt: Date
  }

  public struct StartError: Error, CustomStringConvertible {
    public let description: String
  }

  public static let defaultPort = 8100

  // MARK: - State

  static func stateDirectory() -> String {
    let base =
      ProcessInfo.processInfo.environment["XCFORGE_WDA_STATE_DIR"]
      ?? NSHomeDirectory() + "/.xcforge/wda"
    try? FileManager.default.createDirectory(
      atPath: base, withIntermediateDirectories: true, attributes: nil)
    return base
  }

  static func statePath(udid: String) -> String {
    (stateDirectory() as NSString).appendingPathComponent("\(udid).json")
  }

  /// Saved state for a device, matched by UDID or name. Nil when none is recorded.
  public static func load(device: String) -> State? {
    let direct = statePath(udid: device)
    if let state = read(direct) { return state }
    return all().first { $0.name == device || $0.udid == device }
  }

  /// Every recorded device runner.
  public static func all() -> [State] {
    let dir = stateDirectory()
    let names = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
    return names.sorted().filter { $0.hasSuffix(".json") }.compactMap {
      read((dir as NSString).appendingPathComponent($0))
    }
  }

  static func save(_ state: State) {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let data = try? encoder.encode(state) else { return }
    try? data.write(to: URL(fileURLWithPath: statePath(udid: state.udid)), options: .atomic)
  }

  private static func read(_ path: String) -> State? {
    guard let data = FileManager.default.contents(atPath: path) else { return nil }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try? decoder.decode(State.self, from: data)
  }

  // MARK: - Device lookup

  public struct DeviceInfo: Sendable, Equatable {
    public let udid: String
    public let name: String
    public let tunnelIP: String?
    public let pairingState: String?
    public let developerMode: String?
  }

  /// Find `device` (UDID, CoreDevice identifier or name) in `devicectl list devices` JSON.
  static func findDevice(_ device: String, listJSON: [String: Any]) -> DeviceInfo? {
    guard let result = listJSON["result"] as? [String: Any],
      let devices = result["devices"] as? [[String: Any]]
    else { return nil }
    // Xcode 27 lists simulators here too; a simulator with the same name is not the phone.
    for entry in devices where !DeviceTools.isSimulatorEntry(entry) {
      let udid = DeviceTools.property(entry, "udid") as? String
      let identifier = entry["identifier"] as? String
      let name = DeviceTools.property(entry, "name") as? String
      guard [udid, identifier, name].contains(where: { $0 == device }) else { continue }
      return DeviceInfo(
        udid: udid ?? identifier ?? device,
        name: name ?? device,
        tunnelIP: DeviceTools.property(entry, "tunnelIPAddress") as? String,
        pairingState: DeviceTools.property(entry, "pairingState") as? String,
        developerMode: DeviceTools.property(entry, "developerModeStatus") as? String)
    }
    return nil
  }

  static func lookup(_ device: String, env: Environment) async -> DeviceInfo? {
    let jsonPath = NSTemporaryDirectory() + "xcforge-devicectl-\(UUID().uuidString).json"
    defer { try? FileManager.default.removeItem(atPath: jsonPath) }
    _ = try? await env.shell.run(
      "/usr/bin/xcrun", arguments: ["devicectl", "list", "devices", "--json-output", jsonPath],
      timeout: 30)
    guard let data = FileManager.default.contents(atPath: jsonPath),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }
    return findDevice(device, listJSON: json)
  }

  // MARK: - Failure explanations

  /// Turn a known device or signing failure in xcodebuild/devicectl output into one
  /// actionable sentence. Nil when nothing recognisable is found.
  public static func explainFailure(_ output: String) -> String? {
    let lower = output.lowercased()
    let rules: [(markers: [String], message: String)] = [
      (
        ["ui automation", "automation mode", "enable ui automation"],
        "UI Automation is off on the device. Turn on Settings > Developer > Enable UI Automation, then retry."
      ),
      (
        ["passcode", "device is locked", "is locked", "unlock"],
        "The device is locked. Unlock it (and keep it unlocked while WebDriverAgent starts), then retry."
      ),
      (
        ["developer mode"],
        "Developer Mode is off. Turn on Settings > Privacy & Security > Developer Mode and restart the device."
      ),
      (
        ["not paired", "pairing", "trust this computer"],
        "The device is not paired with this Mac. Unlock it, tap Trust, and check `xcrun devicectl list devices`."
      ),
      (
        ["requires a development team", "no account for team", "signing for", "no profiles for"],
        "Code signing failed. Pass your team with --team (or XCFORGE_WDA_TEAM) and sign in to that team in Xcode."
      ),
      (
        ["untrusted developer", "not trusted", "verify the app"],
        "The runner's developer certificate is not trusted on the device. Trust it in Settings > General > VPN & Device Management."
      ),
      (
        ["device is busy", "copying shared cache"],
        "The device is still preparing for development. Wait for Xcode to finish, then retry."
      ),
    ]
    for rule in rules where rule.markers.contains(where: { lower.contains($0) }) {
      return rule.message
    }
    return nil
  }

  // MARK: - URL discovery

  /// The URL WDA prints as `ServerURLHere->http://...<-ServerURLHere`.
  static func loggedServerURL(_ log: String) -> String? {
    guard let start = log.range(of: "ServerURLHere->"),
      let end = log.range(of: "<-ServerURLHere", range: start.upperBound..<log.endIndex)
    else { return nil }
    let url = String(log[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespaces)
    return url.isEmpty ? nil : url
  }

  /// URLs to try, most reliable first: the CoreDevice tunnel address, then the logged URL.
  static func candidateURLs(tunnelIP: String?, loggedURL: String?, port: Int) -> [String] {
    var urls: [String] = []
    if let ip = tunnelIP, !ip.isEmpty {
      urls.append(ip.contains(":") ? "http://[\(ip)]:\(port)" : "http://\(ip):\(port)")
    }
    if let logged = loggedURL {
      urls.append(logged.hasSuffix("/") ? String(logged.dropLast()) : logged)
    }
    return urls
  }

  /// True when `GET <url>/status` answers.
  public static func isHealthy(_ url: String, timeout: TimeInterval = 3) async -> Bool {
    guard let statusURL = URL(string: url + "/status") else { return false }
    var request = URLRequest(url: statusURL)
    request.timeoutInterval = timeout
    guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
    return (response as? HTTPURLResponse)?.statusCode == 200
  }

  /// PNG bytes from WDA's `/screenshot`, or nil.
  public static func screenshot(baseURL: String) async -> Data? {
    guard let url = URL(string: baseURL + "/screenshot") else { return nil }
    var request = URLRequest(url: url)
    request.timeoutInterval = 20
    guard let (data, _) = try? await URLSession.shared.data(for: request),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let base64 = json["value"] as? String
    else { return nil }
    return Data(base64Encoded: base64, options: .ignoreUnknownCharacters)
  }

  // MARK: - Start / stop

  /// Bundle id for the runner. A team-specific default avoids colliding with an id
  /// another team already registered.
  static func runnerBundleID(team: String?, explicit: String?) -> String {
    if let explicit, !explicit.isEmpty { return explicit }
    if let team, !team.isEmpty { return "com.xcforge.wda.\(team.lowercased()).runner" }
    return "com.xcforge.wda.runner"
  }

  /// Build, sign and launch WDA on `device`, wait for it to answer, and save its URL.
  public static func start(
    device: String, team: String?, bundleID: String? = nil, port: Int = defaultPort,
    startTimeout: TimeInterval = 120, env: Environment
  ) async throws -> State {
    guard let info = await lookup(device, env: env) else {
      throw StartError(
        description:
          "No connected device matches '\(device)'. Check `xcrun devicectl list devices` (it must be paired and unlocked)."
      )
    }
    if let mode = info.developerMode, mode.lowercased() != "enabled" {
      throw StartError(description: explainFailure("developer mode") ?? "Developer Mode is off.")
    }

    if let existing = load(device: info.udid), BuildLock.isAlive(existing.pid),
      await isHealthy(existing.url)
    {
      return existing
    }
    await stop(device: info.udid, env: env)

    guard let projectDir = WDAClient.locateXCForgeWDAProject() else {
      throw StartError(
        description:
          "Can't find the xcforgeWDA project. Set XCFORGE_WDA_DIR to the folder containing xcforgeWDA.xcodeproj."
      )
    }
    let team = team ?? ProcessInfo.processInfo.environment["XCFORGE_WDA_TEAM"]
    let runnerID = runnerBundleID(team: team, explicit: bundleID)
    let derivedData = (stateDirectory() as NSString).appendingPathComponent("build-\(info.udid)")

    var buildArgs = [
      "-project", "\(projectDir)/xcforgeWDA.xcodeproj",
      "-scheme", "xcforgeWDARunner",
      "-destination", "id=\(info.udid)",
      "-derivedDataPath", derivedData,
      "-allowProvisioningUpdates",
      "-allowProvisioningDeviceRegistration",
      "CODE_SIGN_STYLE=Automatic",
      "PRODUCT_BUNDLE_IDENTIFIER=\(runnerID)",
    ]
    if let team, !team.isEmpty { buildArgs.append("DEVELOPMENT_TEAM=\(team)") }
    buildArgs.append("build-for-testing")
    let build = try await Xcodebuild.run(buildArgs, timeout: 1800, env: env)
    guard build.succeeded else {
      let output = Xcodebuild.combinedOutput(build)
      let errors = TestTools.fallbackBuildIssues(stderr: output).filter { $0.severity == .error }
      let detail =
        errors.isEmpty ? String(output.suffix(1500)) : errors.prefix(5).map(\.message).joined(separator: "\n")
      throw StartError(
        description: "Building WebDriverAgent for \(info.name) failed.\n"
          + (explainFailure(output).map { $0 + "\n" } ?? "") + detail)
    }

    let products = (derivedData as NSString).appendingPathComponent("Build/Products")
    let xctestrun = (try? FileManager.default.contentsOfDirectory(atPath: products))?
      .first { $0.hasSuffix(".xctestrun") }
      .map { (products as NSString).appendingPathComponent($0) }
    guard let xctestrun else {
      throw StartError(description: "WebDriverAgent built but no .xctestrun was found in \(products).")
    }

    // Launch detached so the runner outlives this command. TEST_RUNNER_ variables reach
    // the runner without the prefix, so WDA sees USE_PORT.
    let logPath = (stateDirectory() as NSString).appendingPathComponent("\(info.udid).log")
    let command =
      "nohup /usr/bin/xcrun xcodebuild test-without-building -xctestrun \(shellQuote(xctestrun)) "
      + "-destination \(shellQuote("id=\(info.udid)")) > \(shellQuote(logPath)) 2>&1 & echo $!"
    let launched = try await env.shell.run(
      "/bin/sh", arguments: ["-c", command], workingDirectory: nil,
      environment: ["TEST_RUNNER_USE_PORT": "\(port)"], timeout: 15)
    guard let pid = Int32(launched.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) else {
      throw StartError(description: "Could not launch the WebDriverAgent runner: \(launched.stderr)")
    }

    let deadline = Date().addingTimeInterval(startTimeout)
    var tunnelIP = info.tunnelIP
    while Date() < deadline {
      let log = (try? String(contentsOfFile: logPath, encoding: .utf8)) ?? ""
      if !BuildLock.isAlive(pid) {
        throw StartError(
          description: "The WebDriverAgent runner exited before it was reachable.\n"
            + (explainFailure(log).map { $0 + "\n" } ?? "") + "Log: \(logPath)")
      }
      if tunnelIP == nil { tunnelIP = await lookup(info.udid, env: env)?.tunnelIP }
      for url in candidateURLs(tunnelIP: tunnelIP, loggedURL: loggedServerURL(log), port: port) {
        if await isHealthy(url) {
          let state = State(
            udid: info.udid, name: info.name, url: url, pid: pid, logPath: logPath,
            bundleID: runnerID + ".xctrunner", startedAt: Date())
          save(state)
          return state
        }
      }
      try? await Task.sleep(nanoseconds: 2_000_000_000)
    }
    let log = (try? String(contentsOfFile: logPath, encoding: .utf8)) ?? ""
    kill(pid, SIGTERM)
    let tried = candidateURLs(tunnelIP: tunnelIP, loggedURL: loggedServerURL(log), port: port)
    throw StartError(
      description: "WebDriverAgent did not answer within \(Int(startTimeout))s.\n"
        + (explainFailure(log).map { $0 + "\n" } ?? "")
        + "Tried: \(tried.isEmpty ? "no address yet" : tried.joined(separator: ", "))\n"
        + "Log: \(logPath)")
  }

  /// Stop the recorded runner for `device` and forget its URL. Best-effort.
  public static func stop(device: String, env: Environment) async {
    guard let state = load(device: device) else { return }
    if BuildLock.isAlive(state.pid) {
      // Children first: once xcodebuild exits they are reparented and -P no longer finds them.
      _ = try? await env.shell.run(
        "/usr/bin/pkill", arguments: ["-TERM", "-P", "\(state.pid)"], timeout: 5)
      kill(state.pid, SIGTERM)
    }
    try? FileManager.default.removeItem(atPath: statePath(udid: state.udid))
  }

  static func shellQuote(_ s: String) -> String {
    "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }
}

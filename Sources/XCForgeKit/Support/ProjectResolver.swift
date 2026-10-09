import Foundation

/// Error with a rich message for LLM consumption (e.g. lists available options).
struct ResolverError: Error, CustomStringConvertible {
  let description: String
  init(_ message: String) { self.description = message }
}

/// Thrown when a simulator name matches multiple devices with the same OS version.
struct MultipleSimulatorMatchError: Error, CustomStringConvertible {
  let description: String
  init(_ message: String) { self.description = message }
}

/// Zero-config auto-detection for project, scheme, and simulator.
/// Throws ResolverError with rich messages when ambiguous.
enum AutoDetect {

  struct SimulatorDevice: Sendable, Equatable {
    let name: String
    let udid: String
    let runtime: String
    let state: String
    let isAvailable: Bool
  }

  static func validateProject(_ project: String, env: Environment = .live) throws {
    let normalized = project.replacingOccurrences(
      of: "/+$",
      with: "",
      options: .regularExpression
    )
    let normalizedLower = normalized.lowercased()
    guard normalizedLower.hasSuffix(".xcodeproj") || normalizedLower.hasSuffix(".xcworkspace")
    else {
      throw ResolverError("Project path must point to a .xcodeproj or .xcworkspace: \(project)")
    }
    guard env.directoryExists(normalized) else {
      throw ResolverError("Project path not found: \(project)")
    }
  }

  static func validateScheme(_ scheme: String, project: String) async throws {
    let schemes = try await availableSchemes(project: project)
    guard schemes.contains(scheme) else {
      var lines = [
        "Scheme '\(scheme)' was not found in \((project as NSString).lastPathComponent)."
      ]
      if !schemes.isEmpty {
        lines.append("Available schemes:")
        for candidate in schemes {
          lines.append("  \(candidate)")
        }
      }
      throw ResolverError(lines.joined(separator: "\n"))
    }
  }

  static func validateSimulator(_ simulator: String) async throws {
    _ = try await resolveSimulatorDevice(simulator)
  }

  static func prepareSimulatorContext(_ simulator: String) async throws
    -> WorkflowSimulatorPreparation
  {
    let device = try await resolveSimulatorDevice(simulator)
    let preparedDevice = try await ensurePreparedSimulatorDevice(device, requested: simulator)
    let action: WorkflowSimulatorPreparation.Action =
      device.state == "Booted"
      ? .reusedBooted
      : .bootedForWorkflow
    return WorkflowSimulatorPreparation(
      requested: simulator,
      selected: preparedDevice.udid,
      displayName: preparedDevice.name,
      runtime: preparedDevice.runtime,
      initialState: device.state,
      state: preparedDevice.state,
      action: action,
      summary: preparationSummary(
        action: action,
        device: preparedDevice
      )
    )
  }

  // MARK: - Simulator (booted)

  /// Detect the booted simulator. Returns UDID if exactly one is booted.
  /// Throws with descriptive list when ambiguous.
  static func simulator() async throws -> String {
    let device = try await resolveBootedSimulatorDevice()
    return device.udid
  }

  // MARK: - Repo root discovery

  /// Walk up from `startDir` toward filesystem root, stopping at the first directory
  /// containing `.git`. Returns `nil` if no `.git` is found before reaching `/`.
  static func repoRoot(from startDir: String) -> String? {
    guard !startDir.isEmpty else { return nil }
    var dir = startDir
    let fm = FileManager.default
    while dir != "/" {
      let gitPath = (dir as NSString).appendingPathComponent(".git")
      var isDir: ObjCBool = false
      // .git can be a directory (normal) or a file (worktree)
      if fm.fileExists(atPath: gitPath, isDirectory: &isDir) {
        return dir
      }
      dir = (dir as NSString).deletingLastPathComponent
    }
    return nil
  }

  // MARK: - Project (CWD)

  /// Detect Xcode project in working directory. Prefers .xcworkspace over .xcodeproj.
  static func project() async throws -> String {
    try await project(env: .live)
  }

  /// Detect Xcode project with injectable environment.
  static func project(env: Environment) async throws -> String {
    let cwd = env.currentDirectoryPath()

    let result = try await env.shell.run(
      "/usr/bin/find",
      arguments: [
        cwd, "-maxdepth", "2",
        "(", "-name", "*.xcodeproj", "-o", "-name", "*.xcworkspace", ")",
        "-not", "-path", "*/Pods/*",
        "-not", "-path", "*/.build/*",
        "-not", "-path", "*/DerivedData/*",
        "-not", "-path", "*/.swiftpm/*",
        // Every .xcodeproj holds a project.xcworkspace; it isn't a separate workspace.
        "-not", "-path", "*.xcodeproj/*",
      ], timeout: 10)

    let paths = result.stdout
      .split(separator: "\n")
      .map(String.init)
      .filter { !$0.isEmpty && !$0.contains(".xcodeproj/") }

    // Prefer .xcworkspace over .xcodeproj when both exist
    let workspaces = paths.filter { $0.hasSuffix(".xcworkspace") }
    let projects = paths.filter { $0.hasSuffix(".xcodeproj") }
    let candidates = workspaces.isEmpty ? projects : workspaces

    switch candidates.count {
    case 0:
      throw ResolverError("No Xcode project found in \(cwd). Pass project explicitly.")
    case 1:
      return candidates[0]
    default:
      var lines = ["\(candidates.count) projects found — specify which one:"]
      for p in candidates {
        let short = (p as NSString).lastPathComponent
        lines.append("  \(short) — \(p)")
      }
      throw ResolverError(lines.joined(separator: "\n"))
    }
  }

  // MARK: - Scheme (xcodebuild -list)

  /// Detect scheme for a project. Returns name if exactly one scheme exists.
  static func scheme(project: String) async throws -> String {
    let schemes = try await availableSchemes(project: project)
    let projectName = ((project as NSString).lastPathComponent as NSString).deletingPathExtension

    if let preferred = preferredScheme(schemes, projectName: projectName) {
      return preferred
    }
    switch schemes.count {
    case 1:
      return schemes[0]
    default:
      var lines = ["\(schemes.count) schemes found — specify which one:"]
      for s in schemes { lines.append("  \(s)") }
      throw ResolverError(lines.joined(separator: "\n"))
    }
  }

  /// The scheme to use without asking: the only one, the one named after the project
  /// (Xcode's app scheme), or the only one that isn't a test or CocoaPods scheme.
  static func preferredScheme(_ schemes: [String], projectName: String) -> String? {
    if schemes.count == 1 { return schemes[0] }
    if schemes.contains(projectName) { return projectName }
    let apps = schemes.filter { !$0.hasSuffix("Tests") && !$0.hasPrefix("Pods-") }
    return apps.count == 1 ? apps[0] : nil
  }

  static func availableSchemes(project: String) async throws -> [String] {
    let isWorkspace = project.hasSuffix(".xcworkspace")
    let projectFlag = isWorkspace ? "-workspace" : "-project"

    let result = try await Shell.run(
      "/usr/bin/xcodebuild",
      arguments: [
        projectFlag, project, "-list", "-json",
      ], timeout: 60)  // Package resolution on a cold checkout can take most of a minute.

    guard result.succeeded,
      let data = result.stdout.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      throw ResolverError("Failed to list schemes for \((project as NSString).lastPathComponent)")
    }

    let key = isWorkspace ? "workspace" : "project"
    guard let info = json[key] as? [String: Any],
      let schemes = info["schemes"] as? [String], !schemes.isEmpty
    else {
      throw ResolverError(
        "No schemes in \((project as NSString).lastPathComponent). Pass scheme explicitly.")
    }

    return schemes
  }

  // MARK: - Test Targets

  /// Discover test target names for a project.
  /// For SPM packages: parses Package.swift for `.testTarget(name:`.
  /// For xcodeproj: gets targets from `-list` filtered by "Tests"/"UITests" suffix.
  static func testTargets(project: String, env: Environment = .live) async throws -> [String] {
    // SPM path: check for Package.swift in project's parent directory
    let projectDir = (project as NSString).deletingLastPathComponent
    let packageSwiftPath = (projectDir as NSString).appendingPathComponent("Package.swift")

    if env.fileExists(packageSwiftPath),
      let contents = try? env.readFile(packageSwiftPath)
    {
      let pattern = #"\.testTarget\s*\(\s*name\s*:\s*"([^"]+)""#
      if let regex = try? NSRegularExpression(pattern: pattern),
        case let matches = regex.matches(
          in: contents, range: NSRange(contents.startIndex..., in: contents)),
        !matches.isEmpty
      {
        return matches.compactMap { match in
          guard let range = Range(match.range(at: 1), in: contents) else { return nil }
          return String(contents[range])
        }
      }
    }

    // xcodeproj path: use -list -json to get targets, filter by convention
    let isWorkspace = project.hasSuffix(".xcworkspace")
    let projectFlag = isWorkspace ? "-workspace" : "-project"

    let result = try await env.shell.run(
      "/usr/bin/xcodebuild",
      arguments: [
        projectFlag, project, "-list", "-json",
      ], timeout: 60)  // Package resolution on a cold checkout can take most of a minute.

    guard result.succeeded,
      let data = result.stdout.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return []
    }

    let key = isWorkspace ? "workspace" : "project"
    if let info = json[key] as? [String: Any],
      let targets = info["targets"] as? [String]
    {
      return targets.filter { $0.hasSuffix("Tests") || $0.hasSuffix("UITests") }
    }

    return []
  }

  /// Test target names and how they were found.
  struct TestTargets: Sendable, Equatable {
    let names: [String]
    /// True when read from the test plan or scheme, false when guessed from target names.
    let exact: Bool
  }

  /// Test targets for filter resolution: the test plan's, else the scheme's test action's,
  /// else targets whose names end in Tests. Workspaces have no target list in `-list`, so the
  /// scheme is the only reliable source there.
  static func testTargetNames(
    project: String, scheme: String?, testplan: String?, env: Environment = .live
  ) async -> TestTargets {
    if let testplan, let names = TestPlanInspector.testTargetNames(plan: testplan, project: project),
      !names.isEmpty
    {
      return TestTargets(names: names, exact: true)
    }
    if let scheme, let names = SchemeFile.testTargets(scheme: scheme, project: project), !names.isEmpty {
      return TestTargets(names: names, exact: true)
    }
    let guessed = (try? await testTargets(project: project, env: env)) ?? []
    return TestTargets(names: guessed, exact: false)
  }

  // MARK: - Destination builder

  /// Build xcodebuild destination string from a simulator name, UDID, or physical device identifier.
  ///
  /// For simulator targets, prefers `id=<udid>` to skip DTDKRemoteDeviceConnection service browse.
  /// Falls back to `name=<sim>` with a warning when UDID resolution fails.
  static func buildDestination(_ simulator: String) async -> String {
    // Physical device UDIDs are 40-char hex (no dashes) — check first
    if isPhysicalDeviceUDID(simulator) {
      return "platform=iOS,id=\(simulator)"
    }
    if isUDID(simulator) {
      return "platform=iOS Simulator,id=\(simulator)"
    }
    if simulator == "booted" {
      if let udid = try? await Self.simulator() {
        return "platform=iOS Simulator,id=\(udid)"
      }
    }
    // Try resolving name to simulator UDID first (common case)
    if let udid = await resolveNameToUDID(simulator) {
      return "platform=iOS Simulator,id=\(udid)"
    }
    // Check if the name matches a connected physical device (expensive — last resort)
    if await isConnectedPhysicalDevice(simulator) {
      return "platform=iOS,name=\(simulator)"
    }
    // Warn and fall back to name= — avoids DTDKRemoteDeviceConnection only when UDID is known
    Log.warn(
      "Could not resolve '\(simulator)' to a simulator UDID; falling back to name= destination."
        + " This may trigger DTDKRemoteDeviceConnection service browse on iOS 26."
    )
    return "platform=iOS Simulator,name=\(simulator)"
  }

  /// Resolve a simulator name or UDID to a (name, udid) tuple.
  ///
  /// - If `nameOrUDID` is already a UDID (any format), returns it directly.
  /// - Otherwise: loads devices, filters by name (case-insensitive),
  ///   picks the highest-OS match; throws `MultipleSimulatorMatchError` when
  ///   two candidates share the same OS version.
  static func resolveSimulatorNameAndUDID(_ nameOrUDID: String) async throws -> (
    name: String, udid: String
  ) {
    if isPhysicalDeviceUDID(nameOrUDID) || isUDID(nameOrUDID) {
      return (nameOrUDID, nameOrUDID)
    }

    let winner = try pickSimulator(named: nameOrUDID, from: try await loadSimulatorDevices())
    return (winner.name, winner.udid)
  }

  /// The one simulator every name lookup resolves `name` to: an exact, case-insensitive
  /// name match that is available or booted; a booted one when exactly one match is booted,
  /// else the one with the newest OS. Two matches on the same newest OS are an error that
  /// lists their UDIDs.
  static func pickSimulator(named name: String, from devices: [SimulatorDevice]) throws -> SimulatorDevice {
    let matches = devices.filter {
      ($0.isAvailable || $0.state == "Booted") && $0.name.caseInsensitiveCompare(name) == .orderedSame
    }
    guard !matches.isEmpty else {
      throw ResolverError("No available simulator found with name '\(name)'.")
    }
    if matches.count == 1 { return matches[0] }
    let booted = matches.filter { $0.state == "Booted" }
    if booted.count == 1 { return booted[0] }
    let candidates = booted.isEmpty ? matches : booted
    let newest = candidates.map { runtimeVersion($0.runtime) }.max { $0.lexicographicallyPrecedes($1) } ?? []
    let topTier = candidates.filter { runtimeVersion($0.runtime) == newest }
    if topTier.count > 1 {
      let descriptions = topTier.map { describe($0) }.joined(separator: "\n  ")
      throw MultipleSimulatorMatchError(
        "Simulator '\(name)' matches \(topTier.count) devices with the same OS version"
          + " (\(topTier[0].runtime)). Specify a UDID instead:\n  \(descriptions)"
      )
    }
    return topTier[0]
  }

  /// `iOS-18-10` → [18, 10], so 18.10 sorts after 18.2.
  static func runtimeVersion(_ runtime: String) -> [Int] {
    runtime.split { !$0.isNumber }.compactMap { Int($0) }
  }

  /// A simulator to compile against when none is configured or booted: the booted one
  /// with the newest OS, else the available iPhone with the newest OS. Compiling only
  /// needs the platform and architecture, so any of them gives the same build.
  static func simulatorForCompile() async -> String? {
    guard let devices = try? await loadSimulatorDevices() else { return nil }
    return simulatorForCompile(from: devices)
  }

  static func simulatorForCompile(from devices: [SimulatorDevice]) -> String? {
    let ios = devices.filter { $0.isAvailable && $0.runtime.lowercased().hasPrefix("ios") }
    let booted = ios.filter { $0.state == "Booted" }
    let pool = booted.isEmpty ? ios.filter { $0.name.hasPrefix("iPhone") } : booted
    let sorted = pool.sorted {
      let (l, r) = (runtimeVersion($0.runtime), runtimeVersion($1.runtime))
      return l == r ? $0.name < $1.name : r.lexicographicallyPrecedes(l)
    }
    return sorted.first?.udid
  }

  /// Returns true if the string looks like a physical device UDID.
  /// Supports both legacy 40-char hex format and newer 8-16 hex format (e.g. 00008101-001A2B3C4D5E6F78).
  static func isPhysicalDeviceUDID(_ s: String) -> Bool {
    let legacy = #"^[0-9a-fA-F]{40}$"#
    let modern = #"^[0-9a-fA-F]{8}-[0-9a-fA-F]{16}$"#
    return s.range(of: legacy, options: .regularExpression) != nil
      || s.range(of: modern, options: .regularExpression) != nil
  }

  /// Check if a name or identifier matches a connected physical device via devicectl.
  private static func isConnectedPhysicalDevice(_ identifier: String) async -> Bool {
    await DeviceTools.isConnectedPhysicalDevice(identifier, env: .live)
  }

  private static func resolveSimulatorDevice(_ simulator: String) async throws -> SimulatorDevice {
    let devices = try await loadSimulatorDevices()

    if simulator == "booted" {
      return try await resolveBootedSimulatorDevice(from: devices)
    }

    let isUDID = Self.isUDID(simulator)
    let exactName = simulator
    var availableMatches: [String] = []
    var exactMatches: [SimulatorDevice] = []

    for device in devices {
      if (isUDID && device.udid.caseInsensitiveCompare(simulator) == .orderedSame)
        || (!isUDID && device.name.caseInsensitiveCompare(exactName) == .orderedSame)
      {
        exactMatches.append(device)
        continue
      }

      if !isUDID && device.isAvailable {
        availableMatches.append(Self.describe(device))
      }
    }

    if exactMatches.count == 1 {
      let exactMatch = exactMatches[0]
      guard exactMatch.isAvailable else {
        throw ResolverError(
          "Simulator '\(simulator)' is not available for this workflow context.\nMatched simulator:\n  \(Self.describe(exactMatch))"
        )
      }
      return exactMatch
    }
    if exactMatches.count > 1 {
      var lines = ["Simulator '\(simulator)' is ambiguous for this workflow context."]
      lines.append("Matching simulators:")
      for match in exactMatches {
        lines.append("  \(Self.describe(match))")
      }
      throw ResolverError(lines.joined(separator: "\n"))
    }

    var lines = ["Simulator '\(simulator)' is not available for this workflow context."]
    if !availableMatches.isEmpty {
      lines.append("Available simulators:")
      for match in availableMatches.prefix(8) {
        lines.append("  \(match)")
      }
    }
    throw ResolverError(lines.joined(separator: "\n"))
  }

  private static func resolveBootedSimulatorDevice(from devices: [SimulatorDevice]? = nil)
    async throws -> SimulatorDevice
  {
    let deviceList: [SimulatorDevice]
    if let devices {
      deviceList = devices
    } else {
      deviceList = try await loadSimulatorDevices()
    }
    let booted = deviceList.filter { $0.state == "Booted" && $0.isAvailable }

    switch booted.count {
    case 0:
      throw ResolverError(
        "No booted simulator found. Boot one with boot_sim or pass simulator explicitly.")
    case 1:
      return booted[0]
    default:
      var lines = ["\(booted.count) simulators booted — specify which one:"]
      for sim in booted {
        lines.append("  \(Self.describe(sim))")
      }
      throw ResolverError(lines.joined(separator: "\n"))
    }
  }

  /// False only when the simulator list loads and has no simulator with this name or UDID.
  /// Physical device UDIDs are taken as they are.
  static func simulatorExists(_ nameOrUDID: String) async -> Bool {
    if isPhysicalDeviceUDID(nameOrUDID) { return true }
    guard let devices = try? await loadSimulatorDevices() else { return true }
    return devices.contains {
      $0.udid.caseInsensitiveCompare(nameOrUDID) == .orderedSame
        || $0.name.caseInsensitiveCompare(nameOrUDID) == .orderedSame
    }
  }

  private static func loadSimulatorDevices() async throws -> [SimulatorDevice] {
    let shellResult: ShellResult
    do {
      shellResult = try await Shell.xcrun(timeout: 15, "simctl", "list", "devices", "-j")
    } catch {
      throw ResolverError("Simulator validation failed: \(error)")
    }

    guard shellResult.succeeded, let results = parseSimulatorDevices(shellResult.stdout) else {
      throw ResolverError("Failed to parse simulator list")
    }
    return results
  }

  /// Devices from `simctl list devices -j` output, or nil when it doesn't parse.
  static func parseSimulatorDevices(_ output: String) -> [SimulatorDevice]? {
    guard let data = output.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let devices = json["devices"] as? [String: [[String: Any]]]
    else { return nil }

    var results: [SimulatorDevice] = []
    for (runtime, deviceList) in devices {
      let runtimeShort = runtime.split(separator: ".").last.map(String.init) ?? runtime
      for device in deviceList {
        guard let name = device["name"] as? String,
          let udid = device["udid"] as? String
        else { continue }
        let state = (device["state"] as? String) ?? "Unknown"
        let availability = (device["availability"] as? String)?.lowercased()
        let isAvailable =
          (device["isAvailable"] as? Bool ?? true) && availability?.contains("unavailable") != true
        results.append(
          SimulatorDevice(
            name: name,
            udid: udid,
            runtime: runtimeShort,
            state: state,
            isAvailable: isAvailable
          )
        )
      }
    }
    return results
  }

  static func describe(_ device: SimulatorDevice) -> String {
    let availabilityLabel = device.isAvailable ? device.state : "Unavailable"
    return "\(device.name) (\(device.runtime)) — \(availabilityLabel) — \(device.udid)"
  }

  private static func ensurePreparedSimulatorDevice(
    _ device: SimulatorDevice,
    requested: String
  ) async throws -> SimulatorDevice {
    if device.state == "Booted" {
      return device
    }

    if device.state == "Booting" {
      return try await waitForPreparedSimulatorDevice(device, requested: requested)
    }

    let bootResult: ShellResult
    do {
      bootResult = try await Shell.xcrun(timeout: 60, "simctl", "boot", device.udid)
    } catch {
      throw ResolverError(
        "Simulator '\(requested)' resolved to \(describe(device)) but could not be prepared for this workflow: \(error)"
      )
    }

    let alreadyBooted = bootResult.stderr.contains("current state: Booted")
    guard bootResult.succeeded || alreadyBooted else {
      let detail =
        bootResult.stderr.isEmpty ? "simctl boot returned a non-zero status." : bootResult.stderr
      throw ResolverError(
        "Simulator '\(requested)' resolved to \(describe(device)) but could not be prepared for this workflow: \(detail)"
      )
    }

    return try await waitForPreparedSimulatorDevice(device, requested: requested)
  }

  private static func waitForPreparedSimulatorDevice(
    _ device: SimulatorDevice,
    requested: String
  ) async throws -> SimulatorDevice {
    await SimulatorApp.open(shell: LiveShell())

    do {
      _ = try await Shell.xcrun(timeout: 30, "simctl", "bootstatus", device.udid, "-b")
    } catch {
      throw ResolverError(
        "Simulator '\(requested)' resolved to \(describe(device)) but could not be prepared for this workflow: \(error)"
      )
    }

    let refreshed = try await resolveSimulatorDevice(device.udid)
    guard refreshed.state == "Booted" else {
      throw ResolverError(
        "Simulator '\(requested)' resolved to \(describe(device)) but could not be prepared for this workflow: selected target remained \(describe(refreshed))."
      )
    }
    return refreshed
  }

  private static func preparationSummary(
    action: WorkflowSimulatorPreparation.Action,
    device: SimulatorDevice
  ) -> String {
    switch action {
    case .reusedBooted:
      return "Reused the already booted simulator target for this workflow."
    case .bootedForWorkflow:
      return "Booted the selected simulator target for this workflow."
    }
  }

  /// Check if string is a UDID (UUID format)
  static func isUDID(_ s: String) -> Bool {
    let pattern = #"^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$"#
    return s.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
  }

  /// Resolve simulator name to UDID via simctl
  private static func resolveNameToUDID(_ name: String) async -> String? {
    guard let devices = try? await loadSimulatorDevices() else { return nil }
    return try? pickSimulator(named: name, from: devices).udid
  }
}

/// Reads a scheme's test action from its `.xcscheme` file.
enum SchemeFile {
  /// The `.xcscheme` for `scheme`, looked for in the project (or the workspace and the
  /// projects beside it), shared schemes first.
  static func locate(scheme: String, project: String) -> String? {
    let fm = FileManager.default
    var containers = [project]
    if project.hasSuffix(".xcworkspace") {
      containers += projects(near: (project as NSString).deletingLastPathComponent)
    }
    for container in containers {
      let shared = "\(container)/xcshareddata/xcschemes/\(scheme).xcscheme"
      if fm.fileExists(atPath: shared) { return shared }
    }
    for container in containers {
      let userData = "\(container)/xcuserdata"
      for user in (try? fm.contentsOfDirectory(atPath: userData)) ?? [] {
        let path = "\(userData)/\(user)/xcschemes/\(scheme).xcscheme"
        if fm.fileExists(atPath: path) { return path }
      }
    }
    return nil
  }

  /// `.xcodeproj` bundles within three levels of `directory`, skipping build output.
  static func projects(near directory: String) -> [String] {
    guard
      let enumerator = FileManager.default.enumerator(
        at: URL(fileURLWithPath: directory), includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles, .skipsPackageDescendants])
    else { return [] }
    var found: [String] = []
    for case let url as URL in enumerator {
      if SourceChanges.skippedDirectories.contains(url.lastPathComponent) {
        enumerator.skipDescendants()
        continue
      }
      if url.pathExtension == "xcodeproj" { found.append(url.path) }
      if enumerator.level >= 3 { enumerator.skipDescendants() }
    }
    return found.sorted()
  }

  /// Test target names the scheme's test action runs: those of its test plans when it uses
  /// them, else its testables. Nil when the scheme file can't be found.
  static func testTargets(scheme: String, project: String) -> [String]? {
    guard let path = locate(scheme: scheme, project: project),
      let xml = try? String(contentsOfFile: path, encoding: .utf8)
    else { return nil }
    // `container:` paths are relative to the folder holding the project or workspace that
    // owns the scheme, which for a workspace may be a project in a subfolder.
    var container = (path as NSString).deletingLastPathComponent
    while !container.hasSuffix(".xcodeproj") && !container.hasSuffix(".xcworkspace") && container.count > 1 {
      container = (container as NSString).deletingLastPathComponent
    }
    return testTargets(schemeXML: xml, projectDirectory: (container as NSString).deletingLastPathComponent)
  }

  static func testTargets(schemeXML xml: String, projectDirectory: String) -> [String] {
    guard let start = xml.range(of: "<TestAction"),
      let end = xml.range(of: "</TestAction>", range: start.upperBound..<xml.endIndex)
    else { return [] }
    let action = String(xml[start.lowerBound..<end.upperBound])

    var names: [String] = []
    for plan in matches(#"reference\s*=\s*"container:([^"]+\.xctestplan)""#, in: action) {
      let path = plan.hasPrefix("/") ? plan : (projectDirectory as NSString).appendingPathComponent(plan)
      names += TestPlanInspector.testTargetNames(atPath: path) ?? []
    }
    if names.isEmpty {
      let enabled = #"<TestableReference[^>]*?skipped\s*=\s*"NO"[\s\S]*?</TestableReference>"#
      let testables = matches(enabled, in: action, group: 0)
      for testable in testables {
        names += matches(#"BlueprintName\s*=\s*"([^"]+)""#, in: testable).prefix(1)
      }
    }
    var seen = Set<String>()
    return names.filter { seen.insert($0).inserted }
  }

  private static func matches(_ pattern: String, in text: String, group: Int = 1) -> [String] {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
      Range($0.range(at: group), in: text).map { String(text[$0]) }
    }
  }
}

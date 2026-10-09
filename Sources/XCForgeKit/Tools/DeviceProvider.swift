import Foundation
import MCP

public enum DeviceTools {
  public struct DeviceResult: Codable, Sendable {
    public let succeeded: Bool
    public let message: String
  }

  public struct DeviceEntry: Codable, Sendable {
    public let name: String
    public let udid: String
    public let osVersion: String
    public let state: String
    public let connectionType: String
  }

  public struct DeviceListResult: Codable, Sendable {
    public let succeeded: Bool
    public let devices: [DeviceEntry]
    public let message: String
  }

  public struct DeviceAppEntry: Codable, Sendable {
    public let bundleId: String
    public let name: String
    public let version: String
  }

  public struct DeviceAppListResult: Codable, Sendable {
    public let succeeded: Bool
    public let apps: [DeviceAppEntry]
    public let message: String
  }

  public static let tools: [Tool] = [
    Tool(
      name: "list_devices",
      description:
        "List connected physical iOS/iPadOS devices with their name, UDID, OS version, and connection state.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "filter": .object([
            "type": .string("string"),
            "description": .string("Optional filter string, e.g. 'iPhone' or 'iPad'"),
          ])
        ]),
      ])
    ),
    Tool(
      name: "device_info",
      description: "Get detailed information about a connected physical device.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "device": .object([
            "type": .string("string"),
            "description": .string("Device name, UDID, or serial number"),
          ])
        ]),
        "required": .array([.string("device")]),
      ])
    ),
    Tool(
      name: "device_install",
      description: "Install an .app bundle on a connected physical device.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "device": .object([
            "type": .string("string"), "description": .string("Device name or UDID"),
          ]),
          "app_path": .object([
            "type": .string("string"), "description": .string("Path to the .app bundle to install"),
          ]),
        ]),
        "required": .array([.string("device"), .string("app_path")]),
      ])
    ),
    Tool(
      name: "device_uninstall",
      description: "Uninstall an app from a connected physical device by bundle ID.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "device": .object([
            "type": .string("string"), "description": .string("Device name or UDID"),
          ]),
          "bundle_id": .object([
            "type": .string("string"),
            "description": .string("Bundle identifier of the app to uninstall"),
          ]),
        ]),
        "required": .array([.string("device"), .string("bundle_id")]),
      ])
    ),
    Tool(
      name: "device_launch",
      description:
        "Launch an app on a connected physical device. Optionally attach console to capture stdout/stderr.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "device": .object([
            "type": .string("string"), "description": .string("Device name or UDID"),
          ]),
          "bundle_id": .object([
            "type": .string("string"),
            "description": .string("Bundle identifier of the app to launch"),
          ]),
          "console": .object([
            "type": .string("boolean"),
            "description": .string(
              "If true, attach console and wait for app exit. Defaults to false."),
          ]),
          "terminate_existing": .object([
            "type": .string("boolean"),
            "description": .string(
              "If true, terminate any existing instance before launching. Defaults to true."),
          ]),
          "timeout": .object([
            "type": .string("integer"),
            "description": .string(
              "Console timeout in seconds. Defaults to 30. Only used when console is true."),
          ]),
          "arguments": .object([
            "type": .string("array"),
            "items": .object(["type": .string("string")]),
            "description": .string("Arguments to pass to the launched app"),
          ]),
          "url": .object([
            "type": .string("string"),
            "description": .string("Open this URL (deep link or universal link) in the app at launch."),
          ]),
          "env": .object([
            "type": .string("object"),
            "additionalProperties": .object(["type": .string("string")]),
            "description": .string("Environment variables for the launched app."),
          ]),
        ]),
        "required": .array([.string("device"), .string("bundle_id")]),
      ])
    ),
    Tool(
      name: "device_terminate",
      description:
        "Terminate a running process on a connected physical device by bundle ID or PID.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "device": .object([
            "type": .string("string"), "description": .string("Device name or UDID"),
          ]),
          "identifier": .object([
            "type": .string("string"),
            "description": .string("Bundle ID or PID of the process to terminate"),
          ]),
        ]),
        "required": .array([.string("device"), .string("identifier")]),
      ])
    ),
    Tool(
      name: "device_apps",
      description: "List apps installed on a connected physical device.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "device": .object([
            "type": .string("string"), "description": .string("Device name or UDID"),
          ]),
          "include_system": .object([
            "type": .string("boolean"),
            "description": .string("Include system/built-in apps. Defaults to false."),
          ]),
          "bundle_id": .object([
            "type": .string("string"), "description": .string("Filter to a specific bundle ID"),
          ]),
        ]),
        "required": .array([.string("device")]),
      ])
    ),
    Tool(
      name: "device_screenshot",
      description:
        "Save a screenshot of a connected physical device as PNG. Uses devicectl, or the device's WebDriverAgent when devicectl can't capture.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "device": .object([
            "type": .string("string"), "description": .string("Device name or UDID"),
          ]),
          "path": .object([
            "type": .string("string"),
            "description": .string("Where to write the PNG. Default: a new file in the artifact directory."),
          ]),
        ]),
        "required": .array([.string("device")]),
      ])
    ),
    Tool(
      name: "wda_start",
      description:
        "Build, sign and start WebDriverAgent on a connected physical device, then point this server's UI tools (find_element, tap, ...) at it. Reuses a runner that is already answering.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "device": .object([
            "type": .string("string"), "description": .string("Device name or UDID"),
          ]),
          "team": .object([
            "type": .string("string"),
            "description": .string("Apple development team ID for signing. Default: XCFORGE_WDA_TEAM."),
          ]),
          "bundle_id": .object([
            "type": .string("string"),
            "description": .string(
              "Runner bundle id. Default: com.xcforge.wda.<team>.runner (or com.xcforge.wda.runner without a team)."),
          ]),
          "port": .object([
            "type": .string("integer"), "description": .string("Port WDA listens on. Default: 8100."),
          ]),
        ]),
        "required": .array([.string("device")]),
      ])
    ),
    Tool(
      name: "wda_stop",
      description: "Stop WebDriverAgent started on a physical device with wda_start.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "device": .object([
            "type": .string("string"), "description": .string("Device name or UDID"),
          ])
        ]),
        "required": .array([.string("device")]),
      ])
    ),
  ]

  // MARK: - Input Structs

  private struct FilterInput: Decodable {
    let filter: String?
  }

  private struct DeviceInput: Decodable {
    let device: String
  }

  private struct InstallInput: Decodable {
    let device: String
    let app_path: String
  }

  private struct UninstallInput: Decodable {
    let device: String
    let bundle_id: String
  }

  private struct LaunchInput: Decodable {
    let device: String
    let bundle_id: String
    let console: Bool?
    let terminate_existing: Bool?
    let timeout: Int?
    let arguments: [String]?
    let url: String?
    let env: [String: String]?
  }

  private struct WDAStartInput: Decodable {
    let device: String
    let team: String?
    let bundle_id: String?
    let port: Int?
  }

  private struct ScreenshotInput: Decodable {
    let device: String
    let path: String?
  }

  private struct TerminateInput: Decodable {
    let device: String
    let identifier: String
  }

  private struct AppsInput: Decodable {
    let device: String
    let include_system: Bool?
    let bundle_id: String?
  }

  // MARK: - JSON Output Helpers

  private static func runDevicectl(
    arguments: [String],
    timeout: TimeInterval = 30,
    env: Environment
  ) async throws -> (ShellResult, [String: Any]?) {
    let jsonPath = NSTemporaryDirectory() + "xcforge-devicectl-\(UUID().uuidString).json"
    defer { try? FileManager.default.removeItem(atPath: jsonPath) }

    let fullArgs = ["devicectl"] + arguments + ["--json-output", jsonPath]
    let result = try await env.shell.xcrun(timeout: timeout, arguments: fullArgs)

    var jsonOutput: [String: Any]?
    if let data = FileManager.default.contents(atPath: jsonPath),
      let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    {
      jsonOutput = parsed
    }

    return (result, jsonOutput)
  }

  // MARK: - Typed Execute Methods

  public static func executeListDevices(filter: String?, env: Environment) async -> DeviceListResult {
    do {
      let (result, json) = try await runDevicectl(
        arguments: ["list", "devices"],
        env: env
      )

      guard result.succeeded,
        let json = json,
        let resultObj = json["result"] as? [String: Any],
        let deviceList = resultObj["devices"] as? [[String: Any]]
      else {
        let errorMsg = json.flatMap { extractError(from: $0) } ?? result.stderr
        return DeviceListResult(
          succeeded: false,
          devices: [],
          message: errorMsg.isEmpty ? "Failed to list devices" : errorMsg
        )
      }

      // Xcode 27's devicectl (Device Hub) lists simulators too; this tool is for phones and tablets.
      let simulatorUDIDs = await simulatorUDIDs(env: env)
      let devices = deviceList.compactMap { physicalEntry($0, simulatorUDIDs: simulatorUDIDs) }

      if let filter = filter?.lowercased(), !filter.isEmpty {
        let filtered = devices.filter {
          $0.name.lowercased().contains(filter) || $0.udid.lowercased().contains(filter)
            || $0.osVersion.lowercased().contains(filter)
        }
        let message =
          filtered.isEmpty
          ? "No devices matching '\(filter)'"
          : formatDeviceList(filtered)
        return DeviceListResult(succeeded: true, devices: filtered, message: message)
      }

      let message =
        devices.isEmpty
        ? "No physical devices connected"
        : formatDeviceList(devices)
      return DeviceListResult(succeeded: true, devices: devices, message: message)
    } catch {
      return DeviceListResult(succeeded: false, devices: [], message: "Error: \(error)")
    }
  }

  public static func executeDeviceInfo(device: String, env: Environment) async -> DeviceResult {
    do {
      let (result, json) = try await runDevicectl(
        arguments: ["device", "info", "details", "--device", device],
        env: env
      )

      guard result.succeeded,
        let json = json,
        let resultObj = json["result"] as? [String: Any]
      else {
        let errorMsg = json.flatMap { extractError(from: $0) } ?? result.stderr
        return DeviceResult(
          succeeded: false,
          message: errorMsg.isEmpty ? "Failed to get device info" : errorMsg
        )
      }

      var lines: [String] = []
      if let name = property(resultObj, "name") as? String { lines.append("Name: \(name)") }
      if let osVersion = property(resultObj, "osVersionNumber") as? String {
        lines.append("OS: \(osVersion)")
      }
      if let udid = property(resultObj, "udid") as? String { lines.append("UDID: \(udid)") }
      if let model = property(resultObj, "marketingName") as? String
        ?? property(resultObj, "productType") as? String
      {
        lines.append("Model: \(model)")
      }
      if let platform = property(resultObj, "platform") as? String {
        lines.append("Platform: \(platform)")
      }
      if let transport = property(resultObj, "transportType") as? String {
        lines.append("Connection: \(transport)")
      }
      if let tunnel = property(resultObj, "tunnelState") as? String {
        lines.append("Tunnel: \(tunnel)")
      }
      if let address = property(resultObj, "tunnelIPAddress") as? String {
        lines.append("Tunnel IP: \(address)")
      }
      if let pairing = property(resultObj, "pairingState") as? String {
        lines.append("Pairing: \(pairing)")
      }
      if let devMode = property(resultObj, "developerModeStatus") as? String {
        lines.append("Developer Mode: \(devMode)")
      }

      return DeviceResult(
        succeeded: true,
        message: lines.isEmpty ? result.stdout : lines.joined(separator: "\n")
      )
    } catch {
      return DeviceResult(succeeded: false, message: "Error: \(error)")
    }
  }

  public static func executeDeviceInstall(device: String, appPath: String, env: Environment) async
    -> DeviceResult
  {
    do {
      let (result, json) = try await runDevicectl(
        arguments: ["device", "install", "app", "--device", device, appPath],
        timeout: 120,
        env: env
      )

      if result.succeeded {
        let bundleInfo =
          (json?["result"] as? [String: Any])?["installedApplications"] as? [[String: Any]]
        let bundleId = bundleInfo?.first?["bundleID"] as? String
        let msg =
          bundleId != nil
          ? "Installed \(bundleId!) on device"
          : "App installed successfully"
        return DeviceResult(succeeded: true, message: msg)
      }

      let errorMsg = json.flatMap { extractError(from: $0) } ?? result.stderr
      return DeviceResult(
        succeeded: false,
        message: errorMsg.isEmpty ? "Failed to install app" : errorMsg
      )
    } catch {
      return DeviceResult(succeeded: false, message: "Error: \(error)")
    }
  }

  public static func executeDeviceUninstall(device: String, bundleId: String, env: Environment)
    async -> DeviceResult
  {
    do {
      let (result, json) = try await runDevicectl(
        arguments: ["device", "uninstall", "app", "--device", device, bundleId],
        env: env
      )

      if result.succeeded {
        return DeviceResult(succeeded: true, message: "Uninstalled \(bundleId) from device")
      }

      let errorMsg = json.flatMap { extractError(from: $0) } ?? result.stderr
      return DeviceResult(
        succeeded: false,
        message: errorMsg.isEmpty ? "Failed to uninstall app" : errorMsg
      )
    } catch {
      return DeviceResult(succeeded: false, message: "Error: \(error)")
    }
  }

  public static func executeDeviceLaunch(
    device: String,
    bundleId: String,
    console: Bool,
    terminateExisting: Bool,
    timeout: Int,
    arguments: [String]?,
    url: String? = nil,
    environment: [String: String]? = nil,
    env: Environment
  ) async -> DeviceResult {
    do {
      var args = ["device", "process", "launch", "--device", device]

      if console {
        args.append("--console")
      }
      if terminateExisting {
        args.append("--terminate-existing")
      }
      if let url, !url.isEmpty {
        args += ["--payload-url", url]
      }
      if let environment, !environment.isEmpty,
        let data = try? JSONSerialization.data(withJSONObject: environment, options: [.sortedKeys]),
        let json = String(data: data, encoding: .utf8)
      {
        args += ["--environment-variables", json]
      }

      args.append(bundleId)

      if let launchArgs = arguments, !launchArgs.isEmpty {
        args += ["--"] + launchArgs
      }

      let (result, json) = try await runDevicectl(
        arguments: args,
        timeout: TimeInterval(console ? timeout : 30),
        env: env
      )

      if result.succeeded {
        var message = "Launched \(bundleId)"
        if console {
          let output = [result.stdout, result.stderr]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
          if !output.isEmpty {
            message += "\n\n--- Console Output ---\n\(output)"
          }
        }
        return DeviceResult(succeeded: true, message: message)
      }

      let errorMsg = json.flatMap { extractError(from: $0) } ?? result.stderr
      return DeviceResult(
        succeeded: false,
        message: errorMsg.isEmpty ? "Failed to launch app" : errorMsg
      )
    } catch {
      return DeviceResult(succeeded: false, message: "Error: \(error)")
    }
  }

  public static func executeDeviceTerminate(device: String, identifier: String, env: Environment)
    async -> DeviceResult
  {
    do {
      let (result, json) = try await runDevicectl(
        arguments: ["device", "process", "terminate", "--device", device, identifier],
        env: env
      )

      if result.succeeded {
        return DeviceResult(succeeded: true, message: "Terminated \(identifier)")
      }

      let errorMsg = json.flatMap { extractError(from: $0) } ?? result.stderr
      return DeviceResult(
        succeeded: false,
        message: errorMsg.isEmpty ? "Failed to terminate process" : errorMsg
      )
    } catch {
      return DeviceResult(succeeded: false, message: "Error: \(error)")
    }
  }

  public static func executeDeviceApps(
    device: String, includeSystem: Bool, bundleId: String?, env: Environment
  ) async -> DeviceAppListResult {
    do {
      var args = ["device", "info", "apps", "--device", device]
      if includeSystem {
        args.append("--include-all-apps")
      }
      if let bundleId = bundleId {
        args += ["--bundle-id", bundleId]
      }

      let (result, json) = try await runDevicectl(
        arguments: args,
        env: env
      )

      guard result.succeeded,
        let json = json,
        let resultObj = json["result"] as? [String: Any],
        let appList = resultObj["apps"] as? [[String: Any]]
      else {
        let errorMsg = json.flatMap { extractError(from: $0) } ?? result.stderr
        return DeviceAppListResult(
          succeeded: false,
          apps: [],
          message: errorMsg.isEmpty ? "Failed to list apps" : errorMsg
        )
      }

      let apps = appList.compactMap { app -> DeviceAppEntry? in
        guard let bid = app["bundleIdentifier"] as? String ?? app["bundleID"] as? String else {
          return nil
        }
        let name = app["name"] as? String ?? app["displayName"] as? String ?? bid
        let version = app["bundleShortVersion"] as? String ?? app["version"] as? String ?? ""
        return DeviceAppEntry(bundleId: bid, name: name, version: version)
      }

      var lines: [String] = []
      for app in apps.sorted(by: { $0.name < $1.name }) {
        let ver = app.version.isEmpty ? "" : " (\(app.version))"
        lines.append("  \(app.name)\(ver) — \(app.bundleId)")
      }

      let message =
        apps.isEmpty
        ? "No apps found"
        : "\(apps.count) app(s):\n" + lines.joined(separator: "\n")
      return DeviceAppListResult(succeeded: true, apps: apps, message: message)
    } catch {
      return DeviceAppListResult(succeeded: false, apps: [], message: "Error: \(error)")
    }
  }

  // MARK: - Physical Device UDID Detection

  /// Capture the device screen to `path` (PNG). devicectl first (Xcode 26.6 and later), then
  /// the device's WebDriverAgent when `xcforge wda start` has one running.
  public static func executeDeviceScreenshot(device: String, path: String?, env: Environment) async
    -> DeviceResult
  {
    let output = path ?? XcodebuildOptions.uniqueArtifactPath(prefix: "device-shot", extension: "png")
    var devicectlError = ""
    do {
      let (result, json) = try await runDevicectl(
        arguments: ["device", "capture", "screenshot", "--device", device, "--destination", output],
        timeout: 60, env: env)
      if result.succeeded, FileManager.default.fileExists(atPath: output) {
        return DeviceResult(succeeded: true, message: "Screenshot: \(output)")
      }
      devicectlError = json.flatMap { extractError(from: $0) } ?? result.stderr
    } catch {
      devicectlError = "\(error)"
    }

    if let state = DeviceWDA.load(device: device),
      let data = await DeviceWDA.screenshot(baseURL: state.url)
    {
      do {
        try data.write(to: URL(fileURLWithPath: output))
        return DeviceResult(succeeded: true, message: "Screenshot (via WebDriverAgent): \(output)")
      } catch {
        return DeviceResult(succeeded: false, message: "Could not write \(output): \(error)")
      }
    }
    let reason = DeviceWDA.explainFailure(devicectlError) ?? devicectlError
    return DeviceResult(
      succeeded: false,
      message:
        "Screenshot failed: \(reason.isEmpty ? "devicectl returned no image" : reason)\n"
        + "devicectl screen capture needs Xcode 26.6 or later. Alternatively start WebDriverAgent "
        + "on the device with `xcforge wda start --device \(device)` and retry.")
  }

  /// A device from `devicectl list devices` JSON, or nil when it is a simulator.
  static func physicalEntry(_ device: [String: Any], simulatorUDIDs: Set<String> = []) -> DeviceEntry? {
    let udid =
      property(device, "udid") as? String
      ?? (device["identifier"] as? String)
      ?? "Unknown"
    if isSimulatorEntry(device) || simulatorUDIDs.contains(udid.uppercased()) { return nil }
    if let identifier = device["identifier"] as? String, simulatorUDIDs.contains(identifier.uppercased()) {
      return nil
    }
    return DeviceEntry(
      name: property(device, "name") as? String ?? "Unknown",
      udid: udid,
      osVersion: property(device, "osVersionNumber") as? String ?? "Unknown",
      state: connectionState(device),
      connectionType: property(device, "transportType") as? String ?? "unknown")
  }

  /// devicectl marks hardware as `reality: physical` and simulators as `simulated`; older or
  /// partial entries are caught by the simulator visibility class, provider, platform or type.
  static func isSimulatorEntry(_ device: [String: Any]) -> Bool {
    if let reality = property(device, "reality") as? String, reality.lowercased() != "physical" { return true }
    if (device["visibilityClass"] as? String)?.lowercased() == "simulators" { return true }
    if let provider = property(device, "provider") as? String, provider.contains("CoreSimulator") { return true }
    for key in ["platform", "deviceType", "transportType"] {
      if let value = property(device, key) as? String, value.lowercased().contains("simulator") { return true }
    }
    return false
  }

  /// Connected, disconnected or unavailable from the tunnel; else pairing or boot state.
  /// `visibilityClass` is a display hint, not a state.
  static func connectionState(_ device: [String: Any]) -> String {
    for key in ["tunnelState", "pairingState", "bootState"] {
      if let value = property(device, key) as? String, !value.isEmpty { return value }
    }
    return "unknown"
  }

  /// Upper-cased UDIDs of every simulator, so a simulator devicectl doesn't label is still dropped.
  private static func simulatorUDIDs(env: Environment) async -> Set<String> {
    guard let result = try? await env.shell.xcrun(timeout: 10, arguments: ["simctl", "list", "devices", "-j"]),
      result.succeeded,
      let json = try? JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [String: Any],
      let runtimes = json["devices"] as? [String: [[String: Any]]]
    else { return [] }
    return Set(runtimes.values.flatMap { $0 }.compactMap { ($0["udid"] as? String)?.uppercased() })
  }

  public static func isConnectedPhysicalDevice(_ identifier: String, env: Environment) async -> Bool {
    let list = await executeListDevices(filter: nil, env: env)
    return list.devices.contains { $0.udid == identifier || $0.name == identifier }
  }

  /// Read a device field from devicectl JSON. Xcode 27 groups fields under `properties`
  /// (`properties.hardware.udid`, `properties.state.name`, ...); earlier versions split them
  /// across `deviceProperties`, `hardwareProperties` and `connectionProperties`, which Xcode 27
  /// still writes. Both layouts are read.
  static func property(_ device: [String: Any], _ key: String) -> Any? {
    if let properties = device["properties"] as? [String: Any] {
      if let value = properties[key], !(value is [String: Any]) { return value }
      for group in ["hardware", "state", "connection", "device"] {
        if let dict = properties[group] as? [String: Any], let value = dict[key] { return value }
      }
    }
    for container in ["deviceProperties", "hardwareProperties", "connectionProperties"] {
      if let dict = device[container] as? [String: Any], let value = dict[key] { return value }
    }
    return device[key]
  }

  // MARK: - Formatting Helpers

  private static func formatDeviceList(_ devices: [DeviceEntry]) -> String {
    var lines: [String] = ["\(devices.count) device(s):"]
    for device in devices {
      lines.append("  \(device.name) — \(device.osVersion) [\(device.connectionType), \(device.state)]")
      lines.append("    UDID: \(device.udid)")
    }
    return lines.joined(separator: "\n")
  }

  private static func extractError(from json: [String: Any]) -> String? {
    if let error = json["error"] as? [String: Any] {
      if let userInfo = error["userInfo"] as? [String: Any],
        let desc = userInfo["NSLocalizedDescription"] as? String
      {
        return desc
      }
      return (error["localizedDescription"] as? String)
        ?? (error["description"] as? String)
    }
    return nil
  }

  // MARK: - MCP Dispatch Helpers

  private static func dispatchResult(_ result: DeviceResult) -> CallTool.Result {
    result.succeeded ? .ok(result.message) : .fail(result.message)
  }

  private static func dispatchListResult(_ result: DeviceListResult) -> CallTool.Result {
    result.succeeded ? .ok(result.message) : .fail(result.message)
  }

  private static func dispatchAppListResult(_ result: DeviceAppListResult) -> CallTool.Result {
    result.succeeded ? .ok(result.message) : .fail(result.message)
  }
}

extension DeviceTools: ToolProvider {
  public static func dispatch(_ name: String, _ args: [String: Value]?, env: Environment) async
    -> CallTool.Result?
  {
    switch name {
    case "list_devices":
      switch ToolInput.decode(FilterInput.self, from: args) {
      case .failure(let err): return err
      case .success(let input):
        return dispatchListResult(await executeListDevices(filter: input.filter, env: env))
      }
    case "device_info":
      switch ToolInput.decode(DeviceInput.self, from: args) {
      case .failure(let err): return err
      case .success(let input):
        return dispatchResult(await executeDeviceInfo(device: input.device, env: env))
      }
    case "device_install":
      switch ToolInput.decode(InstallInput.self, from: args) {
      case .failure(let err): return err
      case .success(let input):
        return dispatchResult(
          await executeDeviceInstall(device: input.device, appPath: input.app_path, env: env))
      }
    case "device_uninstall":
      switch ToolInput.decode(UninstallInput.self, from: args) {
      case .failure(let err): return err
      case .success(let input):
        return dispatchResult(
          await executeDeviceUninstall(device: input.device, bundleId: input.bundle_id, env: env))
      }
    case "device_launch":
      switch ToolInput.decode(LaunchInput.self, from: args) {
      case .failure(let err): return err
      case .success(let input):
        return dispatchResult(
          await executeDeviceLaunch(
            device: input.device,
            bundleId: input.bundle_id,
            console: input.console ?? false,
            terminateExisting: input.terminate_existing ?? true,
            timeout: input.timeout ?? 30,
            arguments: input.arguments,
            url: input.url,
            environment: input.env,
            env: env
          ))
      }
    case "wda_start":
      switch ToolInput.decode(WDAStartInput.self, from: args) {
      case .failure(let err): return err
      case .success(let input):
        do {
          let state = try await DeviceWDA.start(
            device: input.device, team: input.team, bundleID: input.bundle_id,
            port: input.port ?? DeviceWDA.defaultPort, env: env)
          await env.wdaClient.setBaseURL(state.url)
          return .ok(
            "WebDriverAgent running on \(state.name ?? state.udid) at \(state.url)\n"
              + "UI tools in this session now target the device. Runner log: \(state.logPath)")
        } catch {
          return .fail("\(error)")
        }
      }
    case "wda_stop":
      switch ToolInput.decode(DeviceInput.self, from: args) {
      case .failure(let err): return err
      case .success(let input):
        let state = DeviceWDA.load(device: input.device)
        await DeviceWDA.stop(device: input.device, env: env)
        if let state, await env.wdaClient.getBaseURL() == state.url {
          await env.wdaClient.useSimulators()
        }
        return .ok(
          state == nil
            ? "No WebDriverAgent recorded for \(input.device)" : "Stopped WebDriverAgent on \(input.device)")
      }
    case "device_screenshot":
      switch ToolInput.decode(ScreenshotInput.self, from: args) {
      case .failure(let err): return err
      case .success(let input):
        return dispatchResult(
          await executeDeviceScreenshot(device: input.device, path: input.path, env: env))
      }
    case "device_terminate":
      switch ToolInput.decode(TerminateInput.self, from: args) {
      case .failure(let err): return err
      case .success(let input):
        return dispatchResult(
          await executeDeviceTerminate(device: input.device, identifier: input.identifier, env: env)
        )
      }
    case "device_apps":
      switch ToolInput.decode(AppsInput.self, from: args) {
      case .failure(let err): return err
      case .success(let input):
        return dispatchAppListResult(
          await executeDeviceApps(
            device: input.device, includeSystem: input.include_system ?? false,
            bundleId: input.bundle_id, env: env))
      }
    default:
      return nil
    }
  }
}

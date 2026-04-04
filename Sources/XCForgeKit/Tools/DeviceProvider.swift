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
            description: "List connected physical iOS/iPadOS devices with their name, UDID, OS version, and connection state.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "filter": .object(["type": .string("string"), "description": .string("Optional filter string, e.g. 'iPhone' or 'iPad'")]),
                ]),
            ])
        ),
        Tool(
            name: "device_info",
            description: "Get detailed information about a connected physical device.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "device": .object(["type": .string("string"), "description": .string("Device name, UDID, or serial number")]),
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
                    "device": .object(["type": .string("string"), "description": .string("Device name or UDID")]),
                    "app_path": .object(["type": .string("string"), "description": .string("Path to the .app bundle to install")]),
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
                    "device": .object(["type": .string("string"), "description": .string("Device name or UDID")]),
                    "bundle_id": .object(["type": .string("string"), "description": .string("Bundle identifier of the app to uninstall")]),
                ]),
                "required": .array([.string("device"), .string("bundle_id")]),
            ])
        ),
        Tool(
            name: "device_launch",
            description: "Launch an app on a connected physical device. Optionally attach console to capture stdout/stderr.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "device": .object(["type": .string("string"), "description": .string("Device name or UDID")]),
                    "bundle_id": .object(["type": .string("string"), "description": .string("Bundle identifier of the app to launch")]),
                    "console": .object(["type": .string("boolean"), "description": .string("If true, attach console and wait for app exit. Defaults to false.")]),
                    "terminate_existing": .object(["type": .string("boolean"), "description": .string("If true, terminate any existing instance before launching. Defaults to true.")]),
                    "timeout": .object(["type": .string("integer"), "description": .string("Console timeout in seconds. Defaults to 30. Only used when console is true.")]),
                    "arguments": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string("Arguments to pass to the launched app"),
                    ]),
                ]),
                "required": .array([.string("device"), .string("bundle_id")]),
            ])
        ),
        Tool(
            name: "device_terminate",
            description: "Terminate a running process on a connected physical device by bundle ID or PID.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "device": .object(["type": .string("string"), "description": .string("Device name or UDID")]),
                    "identifier": .object(["type": .string("string"), "description": .string("Bundle ID or PID of the process to terminate")]),
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
                    "device": .object(["type": .string("string"), "description": .string("Device name or UDID")]),
                    "include_system": .object(["type": .string("boolean"), "description": .string("Include system/built-in apps. Defaults to false.")]),
                    "bundle_id": .object(["type": .string("string"), "description": .string("Filter to a specific bundle ID")]),
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

        var fullArgs = ["devicectl"] + arguments + ["--json-output", jsonPath]
        let result = try await env.shell.xcrun(timeout: timeout, arguments: fullArgs)

        var jsonOutput: [String: Any]?
        if let data = FileManager.default.contents(atPath: jsonPath),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
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
                  let deviceList = resultObj["devices"] as? [[String: Any]] else {
                let errorMsg = json.flatMap { extractError(from: $0) } ?? result.stderr
                return DeviceListResult(
                    succeeded: false,
                    devices: [],
                    message: errorMsg.isEmpty ? "Failed to list devices" : errorMsg
                )
            }

            var devices: [DeviceEntry] = []
            for device in deviceList {
                let properties = device["deviceProperties"] as? [String: Any] ?? [:]
                let connectionProperties = device["connectionProperties"] as? [String: Any] ?? [:]
                let name = properties["name"] as? String ?? "Unknown"
                let osVersion = (device["deviceProperties"] as? [String: Any])?["osVersionNumber"] as? String ?? "Unknown"
                let udid = (device["hardwareProperties"] as? [String: Any])?["udid"] as? String
                    ?? (device["identifier"] as? String)
                    ?? "Unknown"
                let state = (device["visibilityClass"] as? String) ?? "available"
                let connectionType = connectionProperties["transportType"] as? String ?? "unknown"

                devices.append(DeviceEntry(
                    name: name,
                    udid: udid,
                    osVersion: osVersion,
                    state: state,
                    connectionType: connectionType
                ))
            }

            if let filter = filter?.lowercased(), !filter.isEmpty {
                let filtered = devices.filter {
                    $0.name.lowercased().contains(filter) ||
                    $0.udid.lowercased().contains(filter) ||
                    $0.osVersion.lowercased().contains(filter)
                }
                let message = filtered.isEmpty
                    ? "No devices matching '\(filter)'"
                    : formatDeviceList(filtered)
                return DeviceListResult(succeeded: true, devices: filtered, message: message)
            }

            let message = devices.isEmpty
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
                  let resultObj = json["result"] as? [String: Any] else {
                let errorMsg = json.flatMap { extractError(from: $0) } ?? result.stderr
                return DeviceResult(
                    succeeded: false,
                    message: errorMsg.isEmpty ? "Failed to get device info" : errorMsg
                )
            }

            let deviceInfo = resultObj["deviceProperties"] as? [String: Any] ?? resultObj
            var lines: [String] = []
            if let name = deviceInfo["name"] as? String { lines.append("Name: \(name)") }
            if let osVersion = deviceInfo["osVersionNumber"] as? String { lines.append("OS: \(osVersion)") }

            let hw = resultObj["hardwareProperties"] as? [String: Any] ?? [:]
            if let udid = hw["udid"] as? String { lines.append("UDID: \(udid)") }
            if let model = hw["marketingName"] as? String ?? hw["productType"] as? String {
                lines.append("Model: \(model)")
            }
            if let platform = hw["platform"] as? String { lines.append("Platform: \(platform)") }

            let conn = resultObj["connectionProperties"] as? [String: Any] ?? [:]
            if let transport = conn["transportType"] as? String { lines.append("Connection: \(transport)") }

            return DeviceResult(
                succeeded: true,
                message: lines.isEmpty ? result.stdout : lines.joined(separator: "\n")
            )
        } catch {
            return DeviceResult(succeeded: false, message: "Error: \(error)")
        }
    }

    public static func executeDeviceInstall(device: String, appPath: String, env: Environment) async -> DeviceResult {
        do {
            let (result, json) = try await runDevicectl(
                arguments: ["device", "install", "app", "--device", device, appPath],
                timeout: 120,
                env: env
            )

            if result.succeeded {
                let bundleInfo = (json?["result"] as? [String: Any])?["installedApplications"] as? [[String: Any]]
                let bundleId = bundleInfo?.first?["bundleID"] as? String
                let msg = bundleId != nil
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

    public static func executeDeviceUninstall(device: String, bundleId: String, env: Environment) async -> DeviceResult {
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

    public static func executeDeviceTerminate(device: String, identifier: String, env: Environment) async -> DeviceResult {
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

    public static func executeDeviceApps(device: String, includeSystem: Bool, bundleId: String?, env: Environment) async -> DeviceAppListResult {
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
                  let appList = resultObj["apps"] as? [[String: Any]] else {
                let errorMsg = json.flatMap { extractError(from: $0) } ?? result.stderr
                return DeviceAppListResult(
                    succeeded: false,
                    apps: [],
                    message: errorMsg.isEmpty ? "Failed to list apps" : errorMsg
                )
            }

            let apps = appList.compactMap { app -> DeviceAppEntry? in
                guard let bid = app["bundleIdentifier"] as? String ?? app["bundleID"] as? String else { return nil }
                let name = app["name"] as? String ?? app["displayName"] as? String ?? bid
                let version = app["bundleShortVersion"] as? String ?? app["version"] as? String ?? ""
                return DeviceAppEntry(bundleId: bid, name: name, version: version)
            }

            var lines: [String] = []
            for app in apps.sorted(by: { $0.name < $1.name }) {
                let ver = app.version.isEmpty ? "" : " (\(app.version))"
                lines.append("  \(app.name)\(ver) — \(app.bundleId)")
            }

            let message = apps.isEmpty
                ? "No apps found"
                : "\(apps.count) app(s):\n" + lines.joined(separator: "\n")
            return DeviceAppListResult(succeeded: true, apps: apps, message: message)
        } catch {
            return DeviceAppListResult(succeeded: false, apps: [], message: "Error: \(error)")
        }
    }

    // MARK: - Physical Device UDID Detection

    public static func isConnectedPhysicalDevice(_ identifier: String, env: Environment) async -> Bool {
        let list = await executeListDevices(filter: nil, env: env)
        return list.devices.contains { $0.udid == identifier || $0.name == identifier }
    }

    // MARK: - Formatting Helpers

    private static func formatDeviceList(_ devices: [DeviceEntry]) -> String {
        var lines: [String] = ["\(devices.count) device(s):"]
        for device in devices {
            lines.append("  \(device.name) — \(device.osVersion) [\(device.connectionType)]")
            lines.append("    UDID: \(device.udid)")
        }
        return lines.joined(separator: "\n")
    }

    private static func extractError(from json: [String: Any]) -> String? {
        if let error = json["error"] as? [String: Any] {
            if let userInfo = error["userInfo"] as? [String: Any],
               let desc = userInfo["NSLocalizedDescription"] as? String {
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
    public static func dispatch(_ name: String, _ args: [String: Value]?, env: Environment) async -> CallTool.Result? {
        switch name {
        case "list_devices":
            switch ToolInput.decode(FilterInput.self, from: args) {
            case .failure(let err): return err
            case .success(let input): return dispatchListResult(await executeListDevices(filter: input.filter, env: env))
            }
        case "device_info":
            switch ToolInput.decode(DeviceInput.self, from: args) {
            case .failure(let err): return err
            case .success(let input): return dispatchResult(await executeDeviceInfo(device: input.device, env: env))
            }
        case "device_install":
            switch ToolInput.decode(InstallInput.self, from: args) {
            case .failure(let err): return err
            case .success(let input): return dispatchResult(await executeDeviceInstall(device: input.device, appPath: input.app_path, env: env))
            }
        case "device_uninstall":
            switch ToolInput.decode(UninstallInput.self, from: args) {
            case .failure(let err): return err
            case .success(let input): return dispatchResult(await executeDeviceUninstall(device: input.device, bundleId: input.bundle_id, env: env))
            }
        case "device_launch":
            switch ToolInput.decode(LaunchInput.self, from: args) {
            case .failure(let err): return err
            case .success(let input):
                return dispatchResult(await executeDeviceLaunch(
                    device: input.device,
                    bundleId: input.bundle_id,
                    console: input.console ?? false,
                    terminateExisting: input.terminate_existing ?? true,
                    timeout: input.timeout ?? 30,
                    arguments: input.arguments,
                    env: env
                ))
            }
        case "device_terminate":
            switch ToolInput.decode(TerminateInput.self, from: args) {
            case .failure(let err): return err
            case .success(let input): return dispatchResult(await executeDeviceTerminate(device: input.device, identifier: input.identifier, env: env))
            }
        case "device_apps":
            switch ToolInput.decode(AppsInput.self, from: args) {
            case .failure(let err): return err
            case .success(let input): return dispatchAppListResult(await executeDeviceApps(device: input.device, includeSystem: input.include_system ?? false, bundleId: input.bundle_id, env: env))
            }
        default:
            return nil
        }
    }
}

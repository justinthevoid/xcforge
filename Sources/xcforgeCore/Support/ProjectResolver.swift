import Foundation

/// Error with a rich message for LLM consumption (e.g. lists available options).
struct ResolverError: Error, CustomStringConvertible {
    let description: String
    init(_ message: String) { self.description = message }
}

/// Zero-config auto-detection for project, scheme, and simulator.
/// Throws ResolverError with rich messages when ambiguous.
enum AutoDetect {

    private struct SimulatorDevice: Sendable {
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
        guard normalizedLower.hasSuffix(".xcodeproj") || normalizedLower.hasSuffix(".xcworkspace") else {
            throw ResolverError("Project path must point to a .xcodeproj or .xcworkspace: \(project)")
        }
        guard env.directoryExists(normalized) else {
            throw ResolverError("Project path not found: \(project)")
        }
    }

    static func validateScheme(_ scheme: String, project: String) async throws {
        let schemes = try await availableSchemes(project: project)
        guard schemes.contains(scheme) else {
            var lines = ["Scheme '\(scheme)' was not found in \((project as NSString).lastPathComponent)."]
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

    static func prepareSimulatorContext(_ simulator: String) async throws -> WorkflowSimulatorPreparation {
        let device = try await resolveSimulatorDevice(simulator)
        let preparedDevice = try await ensurePreparedSimulatorDevice(device, requested: simulator)
        let action: WorkflowSimulatorPreparation.Action = device.state == "Booted"
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

    // MARK: - Project (CWD)

    /// Detect Xcode project in working directory. Prefers .xcworkspace over .xcodeproj.
    static func project() async throws -> String {
        try await project(env: .live)
    }

    /// Detect Xcode project with injectable environment.
    static func project(env: Environment) async throws -> String {
        let cwd = env.currentDirectoryPath()

        let result = try await env.shell.run("/usr/bin/find", arguments: [
            cwd, "-maxdepth", "2",
            "(", "-name", "*.xcodeproj", "-o", "-name", "*.xcworkspace", ")",
            "-not", "-path", "*/Pods/*",
            "-not", "-path", "*/.build/*",
            "-not", "-path", "*/DerivedData/*",
            "-not", "-path", "*/.swiftpm/*",
        ], timeout: 10)

        let paths = result.stdout
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty }

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

        switch schemes.count {
        case 1:
            return schemes[0]
        default:
            var lines = ["\(schemes.count) schemes found — specify which one:"]
            for s in schemes { lines.append("  \(s)") }
            throw ResolverError(lines.joined(separator: "\n"))
        }
    }

    static func availableSchemes(project: String) async throws -> [String] {
        let isWorkspace = project.hasSuffix(".xcworkspace")
        let projectFlag = isWorkspace ? "-workspace" : "-project"

        let result = try await Shell.run("/usr/bin/xcodebuild", arguments: [
            projectFlag, project, "-list", "-json",
        ], timeout: 15)

        guard result.succeeded,
              let data = result.stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ResolverError("Failed to list schemes for \((project as NSString).lastPathComponent)")
        }

        let key = isWorkspace ? "workspace" : "project"
        guard let info = json[key] as? [String: Any],
              let schemes = info["schemes"] as? [String], !schemes.isEmpty else {
            throw ResolverError("No schemes in \((project as NSString).lastPathComponent). Pass scheme explicitly.")
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
           let contents = try? env.readFile(packageSwiftPath) {
            let pattern = #"\.testTarget\s*\(\s*name\s*:\s*"([^"]+)""#
            if let regex = try? NSRegularExpression(pattern: pattern),
               case let matches = regex.matches(in: contents, range: NSRange(contents.startIndex..., in: contents)),
               !matches.isEmpty {
                return matches.compactMap { match in
                    guard let range = Range(match.range(at: 1), in: contents) else { return nil }
                    return String(contents[range])
                }
            }
        }

        // xcodeproj path: use -list -json to get targets, filter by convention
        let isWorkspace = project.hasSuffix(".xcworkspace")
        let projectFlag = isWorkspace ? "-workspace" : "-project"

        let result = try await env.shell.run("/usr/bin/xcodebuild", arguments: [
            projectFlag, project, "-list", "-json",
        ], timeout: 15)

        guard result.succeeded,
              let data = result.stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        let key = isWorkspace ? "workspace" : "project"
        if let info = json[key] as? [String: Any],
           let targets = info["targets"] as? [String] {
            return targets.filter { $0.hasSuffix("Tests") || $0.hasSuffix("UITests") }
        }

        return []
    }

    // MARK: - Destination builder

    /// Build xcodebuild destination string from a simulator name, UDID, or physical device identifier.
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
        // Fallback: pass name directly as simulator
        return "platform=iOS Simulator,name=\(simulator)"
    }

    /// Returns true if the string looks like a physical device UDID.
    /// Supports both legacy 40-char hex format and newer 8-16 hex format (e.g. 00008101-001A2B3C4D5E6F78).
    private static func isPhysicalDeviceUDID(_ s: String) -> Bool {
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
            if (isUDID && device.udid.caseInsensitiveCompare(simulator) == .orderedSame) ||
                (!isUDID && device.name.caseInsensitiveCompare(exactName) == .orderedSame) {
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

    private static func resolveBootedSimulatorDevice(from devices: [SimulatorDevice]? = nil) async throws -> SimulatorDevice {
        let deviceList: [SimulatorDevice]
        if let devices {
            deviceList = devices
        } else {
            deviceList = try await loadSimulatorDevices()
        }
        let booted = deviceList.filter { $0.state == "Booted" && $0.isAvailable }

        switch booted.count {
        case 0:
            throw ResolverError("No booted simulator found. Boot one with boot_sim or pass simulator explicitly.")
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

    private static func loadSimulatorDevices() async throws -> [SimulatorDevice] {
        let shellResult: ShellResult
        do {
            shellResult = try await Shell.xcrun(timeout: 15, "simctl", "list", "devices", "-j")
        } catch {
            throw ResolverError("Simulator validation failed: \(error)")
        }

        guard shellResult.succeeded,
              let data = shellResult.stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let devices = json["devices"] as? [String: [[String: Any]]] else {
            throw ResolverError("Failed to parse simulator list")
        }

        var results: [SimulatorDevice] = []
        for (runtime, deviceList) in devices {
            let runtimeShort = runtime.split(separator: ".").last.map(String.init) ?? runtime
            for device in deviceList {
                guard let name = device["name"] as? String,
                      let udid = device["udid"] as? String else { continue }
                let state = (device["state"] as? String) ?? "Unknown"
                let availability = (device["availability"] as? String)?.lowercased()
                let isAvailable = (device["isAvailable"] as? Bool ?? true) &&
                    availability?.contains("unavailable") != true
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

    private static func describe(_ device: SimulatorDevice) -> String {
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
            let detail = bootResult.stderr.isEmpty ? "simctl boot returned a non-zero status." : bootResult.stderr
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
        _ = try? await Shell.run("/usr/bin/open", arguments: ["-a", "Simulator"], timeout: 5)

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
        guard let result = try? await Shell.xcrun(timeout: 15, "simctl", "list", "devices", "-j"),
              result.succeeded,
              let data = result.stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let devices = json["devices"] as? [String: [[String: Any]]] else {
            return nil
        }

        let nameLower = name.lowercased()
        var exactMatch: String?
        var caseInsensitive: String?
        var prefixBooted: String?
        var prefixMatch: String?

        for (_, deviceList) in devices {
            for device in deviceList {
                guard let deviceName = device["name"] as? String,
                      let udid = device["udid"] as? String else { continue }
                let usable = (device["isAvailable"] as? Bool ?? false) ||
                             (device["state"] as? String) == "Booted"
                guard usable else { continue }

                let isBooted = (device["state"] as? String) == "Booted"

                if deviceName == name {
                    exactMatch = udid
                } else if exactMatch == nil && deviceName.lowercased() == nameLower {
                    caseInsensitive = udid
                } else if deviceName.lowercased().hasPrefix(nameLower) {
                    if isBooted { prefixBooted = udid }
                    else if prefixMatch == nil { prefixMatch = udid }
                }
            }
        }

        return exactMatch ?? caseInsensitive ?? prefixBooted ?? prefixMatch
    }
}

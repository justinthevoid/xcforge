import Foundation
import MCP

public enum BuildTools {
    public struct BuildProductInfo: Sendable, Equatable {
        public let bundleId: String
        public let appPath: String
    }

    public struct BuildExecution: Codable, Sendable {
        public let succeeded: Bool
        public let elapsed: String
        public let scheme: String
        public let simulator: String
        public let configuration: String
        public let bundleId: String?
        public let appPath: String?
        public let errors: [String]
        public let failureReason: String?
        public let structuredErrors: [String]?
    }

    /// Classify the reason a build failed from xcodebuild stderr.
    static func classifyFailureReason(stderr: String) -> String {
        let lower = stderr.lowercased()
        if lower.contains("unable to open database") || lower.contains("locked database")
            || lower.contains("database is locked") || lower.contains("corrupted")
            || lower.contains("couldn't load project") {
            return "infrastructure"
        }
        if lower.contains("no signing certificate") || lower.contains("provisioning profile")
            || lower.contains("code signing") || lower.contains("requires a provisioning profile")
            || lower.contains("signing certificate") {
            return "signing_error"
        }
        if lower.contains("undefined symbols") || lower.contains("ld: ")
            || lower.contains("linker command failed") {
            return "linker_error"
        }
        if lower.contains(": error:") {
            return "compiler_error"
        }
        return "unknown"
    }

    /// Extract structured error lines with file:line locations from stderr.
    static func extractStructuredErrors(stderr: String, failureReason: String) -> [String] {
        // For infrastructure failures, suppress SourceKit/compiler noise
        if failureReason == "infrastructure" {
            let lines = stderr.split(separator: "\n").map(String.init)
            return lines.filter { line in
                let lower = line.lowercased()
                return lower.contains("unable to open database")
                    || lower.contains("locked database")
                    || lower.contains("database is locked")
                    || lower.contains("corrupted")
                    || lower.contains("couldn't load project")
                    || (lower.contains("error:") && !lower.contains("sourcekit"))
            }.prefix(20).map { $0 }
        }

        // Reuse TestTools' stderr parser for structured error extraction
        let issues = TestTools.fallbackBuildIssues(stderr: stderr)
        let errorIssues = issues.filter { $0.severity == .error }
        if !errorIssues.isEmpty {
            return Array(errorIssues.prefix(20).map { issue in
                if let loc = issue.location {
                    var s = loc.filePath
                    if let line = loc.line { s += ":\(line)" }
                    if let col = loc.column { s += ":\(col)" }
                    return "\(s): error: \(issue.message)"
                }
                return "error: \(issue.message)"
            })
        }

        // Fallback: tail of stderr
        let tail = String(stderr.suffix(2000))
        return tail.isEmpty ? [] : [tail]
    }

    public static let tools: [Tool] = [
        Tool(
            name: "build_sim",
            description: """
                Build an iOS app for simulator. Uses xcodebuild with optimized flags. \
                Project, scheme, and simulator are auto-detected if omitted.
                """,
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project": .object(["type": .string("string"), "description": .string("Path to .xcodeproj or .xcworkspace. Auto-detected from working directory if omitted.")]),
                    "scheme": .object(["type": .string("string"), "description": .string("Xcode scheme name. Auto-detected if project has only one scheme.")]),
                    "simulator": .object(["type": .string("string"), "description": .string("Simulator name or UDID. Auto-detected from booted simulator if omitted.")]),
                    "configuration": .object(["type": .string("string"), "description": .string("Build configuration (Debug/Release). Default: Debug")]),
                ]),
            ])
        ),
        Tool(
            name: "build_run_sim",
            description: """
                Build, install, and launch an iOS app on a simulator in one call. \
                Runs build, settings extraction, simulator boot, and Simulator.app \
                in parallel for maximum speed. Equivalent to Xcode's Cmd+R. \
                Project, scheme, and simulator are auto-detected if omitted.
                """,
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project": .object(["type": .string("string"), "description": .string("Path to .xcodeproj or .xcworkspace. Auto-detected from working directory if omitted.")]),
                    "scheme": .object(["type": .string("string"), "description": .string("Xcode scheme name. Auto-detected if project has only one scheme.")]),
                    "simulator": .object(["type": .string("string"), "description": .string("Simulator name or UDID. Auto-detected from booted simulator if omitted.")]),
                    "configuration": .object(["type": .string("string"), "description": .string("Build configuration (Debug/Release). Default: Debug")]),
                ]),
            ])
        ),
        Tool(
            name: "clean",
            description: """
                Clean Xcode build artifacts for a project/scheme. \
                Project and scheme are auto-detected if omitted.
                """,
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project": .object(["type": .string("string"), "description": .string("Path to .xcodeproj or .xcworkspace. Auto-detected if omitted.")]),
                    "scheme": .object(["type": .string("string"), "description": .string("Xcode scheme name. Auto-detected if omitted.")]),
                ]),
            ])
        ),
        Tool(
            name: "discover_projects",
            description: "Find Xcode projects and workspaces in a directory.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "path": .object(["type": .string("string"), "description": .string("Directory to search in")]),
                ]),
                "required": .array([.string("path")]),
            ])
        ),
        Tool(
            name: "list_schemes",
            description: """
                List available schemes for a project. \
                Project is auto-detected if omitted.
                """,
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project": .object(["type": .string("string"), "description": .string("Path to .xcodeproj or .xcworkspace. Auto-detected if omitted.")]),
                ]),
            ])
        ),
    ]

    // MARK: - Input Types

    struct BuildInput: Decodable {
        let project: String?
        let scheme: String?
        let simulator: String?
        let configuration: String?
    }

    struct CleanInput: Decodable {
        let project: String?
        let scheme: String?
    }

    struct DiscoverInput: Decodable {
        let path: String
    }

    struct ListSchemesInput: Decodable {
        let project: String?
    }

    // MARK: - Implementations

    public static func executeBuild(
        project: String? = nil,
        scheme: String? = nil,
        simulator: String? = nil,
        configuration: String = "Debug",
        env: Environment = .live
    ) async throws -> BuildExecution {
        let resolvedProject = try await env.session.resolveProject(project)
        let resolvedScheme = try await env.session.resolveScheme(scheme, project: resolvedProject)
        let resolvedSimulator = try await env.session.resolveSimulator(simulator)

        let isWorkspace = resolvedProject.hasSuffix(".xcworkspace")
        let projectFlag = isWorkspace ? "-workspace" : "-project"
        let destination = await AutoDetect.buildDestination(resolvedSimulator)

        var buildArgs = [
            projectFlag, resolvedProject,
            "-scheme", resolvedScheme,
            "-configuration", configuration,
            "-destination", destination,
            "-skipMacroValidation",
            "-parallelizeTargets",
            "build",
        ]
        buildArgs += ["COMPILATION_CACHE_ENABLE_CACHING=YES"]

        let start = CFAbsoluteTimeGetCurrent()
        let result = try await env.shell.run("/usr/bin/xcodebuild", arguments: buildArgs, timeout: 600)
        let elapsed = String(format: "%.1f", CFAbsoluteTimeGetCurrent() - start)

        if result.succeeded {
            let buildInfo = await extractBuildInfo(
                project: resolvedProject, scheme: resolvedScheme,
                simulator: resolvedSimulator, configuration: configuration,
                env: env
            )

            if let bid = buildInfo.bundleId {
                await env.session.setBuildInfo(bundleId: bid, appPath: buildInfo.appPath)
            }

            return BuildExecution(
                succeeded: true,
                elapsed: elapsed,
                scheme: resolvedScheme,
                simulator: resolvedSimulator,
                configuration: configuration,
                bundleId: buildInfo.bundleId,
                appPath: buildInfo.appPath,
                errors: [],
                failureReason: nil,
                structuredErrors: nil
            )
        } else {
            let reason = classifyFailureReason(stderr: result.stderr)
            let structured = extractStructuredErrors(stderr: result.stderr, failureReason: reason)

            // Keep legacy errors field for backward compat
            let errorLines = result.stderr.split(separator: "\n")
                .filter { $0.contains(": error:") }
                .prefix(20)
                .map(String.init)
            let stderrTail = String(result.stderr.suffix(2000))
            let errors = errorLines.isEmpty
                ? (stderrTail.isEmpty ? [] : [stderrTail])
                : Array(errorLines)

            return BuildExecution(
                succeeded: false,
                elapsed: elapsed,
                scheme: resolvedScheme,
                simulator: resolvedSimulator,
                configuration: configuration,
                bundleId: nil,
                appPath: nil,
                errors: errors,
                failureReason: reason,
                structuredErrors: structured
            )
        }
    }

    static func buildSim(_ args: [String: Value]?, env: Environment) async -> CallTool.Result {
        switch ToolInput.decode(BuildInput.self, from: args) {
        case .failure(let err): return err
        case .success(let input):
            do {
                let execution = try await executeBuild(
                    project: input.project,
                    scheme: input.scheme,
                    simulator: input.simulator,
                    configuration: input.configuration ?? "Debug",
                    env: env
                )

                if execution.succeeded {
                    var output = "Build succeeded in \(execution.elapsed)s\nScheme: \(execution.scheme)\nSimulator: \(execution.simulator)"
                    if let bid = execution.bundleId {
                        output += "\nBundle ID: \(bid)"
                    }
                    if let path = execution.appPath {
                        output += "\nApp path: \(path)"
                    }
                    return .ok(output)
                } else {
                    return .fail(formatBuildFailure(execution))
                }
            } catch {
                return .fail("Build error: \(error)")
            }
        }
    }

    static func formatBuildFailure(_ execution: BuildExecution) -> String {
        var lines: [String] = []
        lines.append("Build FAILED in \(execution.elapsed)s")

        if let reason = execution.failureReason {
            lines.append("Failure reason: \(reason)")
        }

        lines.append("Scheme: \(execution.scheme)")
        lines.append("Simulator: \(execution.simulator)")

        if let structured = execution.structuredErrors, !structured.isEmpty {
            lines.append("")
            lines.append("Errors (\(structured.count)):")
            for error in structured {
                lines.append("  \(error)")
            }
        } else if !execution.errors.isEmpty {
            lines.append("")
            lines.append(execution.errors.joined(separator: "\n"))
        }

        return lines.joined(separator: "\n")
    }

    static func clean(_ args: [String: Value]?, env: Environment) async -> CallTool.Result {
        switch ToolInput.decode(CleanInput.self, from: args) {
        case .failure(let err): return err
        case .success(let input):
            let project: String
            let scheme: String
            do {
                project = try await env.session.resolveProject(input.project)
                scheme = try await env.session.resolveScheme(input.scheme, project: project)
            } catch {
                return .fail("\(error)")
            }

            let isWorkspace = project.hasSuffix(".xcworkspace")
            let projectFlag = isWorkspace ? "-workspace" : "-project"

            do {
                let result = try await env.shell.run("/usr/bin/xcodebuild", arguments: [
                    projectFlag, project, "-scheme", scheme, "clean",
                ], timeout: 60)
                return result.succeeded ? .ok("Clean succeeded") : .fail("Clean failed: \(result.stderr)")
            } catch {
                return .fail("Clean error: \(error)")
            }
        }
    }

    static func discoverProjects(_ args: [String: Value]?, env: Environment) async -> CallTool.Result {
        switch ToolInput.decode(DiscoverInput.self, from: args) {
        case .failure(let err): return err
        case .success(let input):
            do {
                let result = try await env.shell.run("/usr/bin/find", arguments: [
                    input.path, "-maxdepth", "3",
                    "(", "-name", "*.xcodeproj", "-o", "-name", "*.xcworkspace", ")",
                    "-not", "-path", "*/Pods/*",
                    "-not", "-path", "*/.build/*",
                ], timeout: 15)
                return .ok(result.stdout.isEmpty ? "No projects found" : result.stdout)
            } catch {
                return .fail("Discovery error: \(error)")
            }
        }
    }

    // MARK: - Build → Boot → Install → Launch (parallel pipeline)

    static func buildRunSim(_ args: [String: Value]?, env: Environment) async -> CallTool.Result {
        switch ToolInput.decode(BuildInput.self, from: args) {
        case .failure(let err): return err
        case .success(let input): return await buildRunSimImpl(input, env: env)
        }
    }

    private static func buildRunSimImpl(_ input: BuildInput, env: Environment) async -> CallTool.Result {
        let project: String
        let scheme: String
        let simulator: String
        do {
            project = try await env.session.resolveProject(input.project)
            scheme = try await env.session.resolveScheme(input.scheme, project: project)
            simulator = try await env.session.resolveSimulator(input.simulator)
        } catch {
            return .fail("\(error)")
        }

        let configuration = input.configuration ?? "Debug"
        let isWorkspace = project.hasSuffix(".xcworkspace")
        let projectFlag = isWorkspace ? "-workspace" : "-project"
        let destination = await AutoDetect.buildDestination(simulator)

        let udid: String
        do {
            udid = try await SimTools.resolveSimulator(simulator)
        } catch {
            return .fail("Cannot resolve simulator UDID: \(error)")
        }

        let totalStart = CFAbsoluteTimeGetCurrent()

        let buildArgs = [
            projectFlag, project,
            "-scheme", scheme,
            "-configuration", configuration,
            "-destination", destination,
            "-skipMacroValidation",
            "-parallelizeTargets",
            "build",
            "COMPILATION_CACHE_ENABLE_CACHING=YES",
        ]

        let settingsArgs = [
            projectFlag, project,
            "-scheme", scheme,
            "-configuration", configuration,
            "-destination", destination,
            "-showBuildSettings",
        ]

        // ── Phase 1: Parallel ──
        // Build is the critical path (~10-60s). Settings extraction, simulator boot,
        // and Simulator.app launch run concurrently — they complete while the build
        // is still compiling, adding zero wall-clock overhead.
        async let buildTask = env.shell.run("/usr/bin/xcodebuild", arguments: buildArgs, timeout: 600)
        async let settingsTask = env.shell.run("/usr/bin/xcodebuild", arguments: settingsArgs, timeout: 30)
        async let bootTask = env.shell.run("/usr/bin/xcrun", arguments: ["simctl", "boot", udid], timeout: 60)
        async let openTask = env.shell.run("/usr/bin/open", arguments: ["-a", "Simulator"], timeout: 10)

        // Await build first (critical — abort if it fails)
        let buildResult: ShellResult
        do {
            buildResult = try await buildTask
        } catch {
            return .fail("Build error: \(error)")
        }

        let buildElapsed = String(format: "%.1f", CFAbsoluteTimeGetCurrent() - totalStart)

        guard buildResult.succeeded else {
            let errorLines = buildResult.stderr.split(separator: "\n")
                .filter { $0.contains(": error:") }
                .prefix(20)
                .joined(separator: "\n")
            let errors = errorLines.isEmpty ? String(buildResult.stderr.suffix(2000)) : errorLines
            return .fail("Build FAILED in \(buildElapsed)s\n\(errors)")
        }

        // Await settings — 3-tier fallback for app path + bundle ID:
        // 1. -showBuildSettings (parallel, fastest when it works)
        // 2. Parse build stdout for .app paths
        // 3. Search DerivedData with find
        // Bundle ID always via PlistBuddy once we have the .app path.
        var appPath: String?
        var infoSource = "showBuildSettings"

        // Tier 1: -showBuildSettings
        if let settingsResult = try? await settingsTask, settingsResult.succeeded {
            var builtProductsDir: String?
            var fullProductName: String?

            for line in settingsResult.stdout.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("BUILT_PRODUCTS_DIR = ") {
                    builtProductsDir = String(trimmed.dropFirst("BUILT_PRODUCTS_DIR = ".count))
                } else if trimmed.hasPrefix("FULL_PRODUCT_NAME = ") {
                    fullProductName = String(trimmed.dropFirst("FULL_PRODUCT_NAME = ".count))
                }
            }

            if let dir = builtProductsDir, let name = fullProductName {
                appPath = "\(dir)/\(name)"
            }
        }

        // Tier 2: Parse build stdout for .app path
        if appPath == nil {
            let suffix = "/\(configuration)-iphonesimulator/"
            for line in buildResult.stdout.split(separator: "\n").reversed() {
                let s = String(line)
                if let range = s.range(of: suffix) {
                    let afterConfig = s[range.upperBound...]
                    if let appEnd = afterConfig.range(of: ".app") {
                        let fullLine = String(s[s.startIndex..<appEnd.upperBound])
                        if let absStart = fullLine.firstIndex(of: "/") {
                            appPath = String(fullLine[absStart...])
                            infoSource = "build output"
                            break
                        }
                    }
                }
            }
        }

        // Tier 3: Search DerivedData
        if appPath == nil {
            let ddPath = NSHomeDirectory() + "/Library/Developer/Xcode/DerivedData"
            let findResult = try? await env.shell.run("/usr/bin/find", arguments: [
                ddPath, "-maxdepth", "6",
                "-name", "\(scheme).app",
                "-path", "*/\(configuration)-iphonesimulator/*",
            ], timeout: 10)
            if let r = findResult, r.succeeded, !r.stdout.isEmpty {
                appPath = r.stdout.split(separator: "\n").first.map(String.init)
                infoSource = "DerivedData search"
            }
        }

        guard let finalAppPath = appPath else {
            return .fail("Build succeeded in \(buildElapsed)s but could not locate .app bundle")
        }

        // Bundle ID: always via PlistBuddy (instant, works regardless of how we found the .app)
        let bundleId: String
        let plistPath = "\(finalAppPath)/Info.plist"
        let plistResult = try? await env.shell.run("/usr/libexec/PlistBuddy",
            arguments: ["-c", "Print :CFBundleIdentifier", plistPath], timeout: 5)
        if let r = plistResult, r.succeeded, !r.stdout.isEmpty {
            bundleId = r.stdout
        } else {
            return .fail("Build succeeded in \(buildElapsed)s but could not read bundle ID from \(plistPath)")
        }

        await env.session.setBuildInfo(bundleId: bundleId, appPath: finalAppPath)

        // Await boot (non-critical — already booted is fine)
        let bootResult = try? await bootTask
        let bootStatus: String
        if bootResult?.succeeded == true {
            bootStatus = "booted"
        } else if bootResult?.stderr.contains("current state: Booted") == true {
            bootStatus = "already running"
        } else {
            bootStatus = "boot failed: \(bootResult?.stderr ?? "unknown")"
        }

        // Await Simulator.app (fire and forget)
        _ = try? await openTask

        // ── Phase 2: Sequential (needs build artifacts + booted simulator) ──

        // Install
        let installStart = CFAbsoluteTimeGetCurrent()
        let installResult: ShellResult
        do {
            installResult = try await env.shell.run("/usr/bin/xcrun",
                arguments: ["simctl", "install", udid, finalAppPath], timeout: 60)
        } catch {
            return .fail("Build succeeded in \(buildElapsed)s\nInstall error: \(error)")
        }

        guard installResult.succeeded else {
            return .fail("Build succeeded in \(buildElapsed)s\nInstall FAILED: \(installResult.stderr)")
        }

        _ = await env.wdaClient.deleteSession()
        let installElapsed = String(format: "%.1f", CFAbsoluteTimeGetCurrent() - installStart)

        // Launch (--terminate-running-process replaces separate terminate + 0.5s sleep)
        let launchResult: ShellResult
        do {
            launchResult = try await env.shell.run("/usr/bin/xcrun",
                arguments: ["simctl", "launch", "--terminate-running-process", udid, bundleId],
                timeout: 15)
        } catch {
            return .fail("Build + Install succeeded\nLaunch error: \(error)")
        }

        guard launchResult.succeeded else {
            if launchResult.exitCode == -1 {
                return .fail("Build + Install succeeded\nLaunch timed out after 15s")
            }
            return .fail("Build + Install succeeded\nLaunch FAILED: \(launchResult.stderr)")
        }

        let totalElapsed = String(format: "%.1f", CFAbsoluteTimeGetCurrent() - totalStart)

        var output = "build_run_sim completed in \(totalElapsed)s"
        output += "\nScheme: \(scheme) | Simulator: \(simulator)"
        output += "\nBundle ID: \(bundleId)"
        output += "\nApp path: \(finalAppPath)"
        output += "\n"
        output += "\n  Build:     \(buildElapsed)s"
        output += "\n  App info:  \(infoSource) (parallel)"
        output += "\n  Boot:      \(bootStatus) (parallel)"
        output += "\n  Install:   \(installElapsed)s"
        output += "\n  Launch:    OK"
        output += "\n  Simulator: opened"

        return .ok(output)
    }

    // MARK: - Build info extraction

    static func resolveBuildProductInfo(
        project: String, scheme: String, simulator: String, configuration: String,
        env: Environment
    ) async throws -> BuildProductInfo {
        let isWorkspace = project.hasSuffix(".xcworkspace")
        let projectFlag = isWorkspace ? "-workspace" : "-project"
        let destination = await AutoDetect.buildDestination(simulator)

        let result = try await env.shell.run("/usr/bin/xcodebuild", arguments: [
            projectFlag, project,
            "-scheme", scheme,
            "-configuration", configuration,
            "-destination", destination,
            "-showBuildSettings",
        ], timeout: 30)

        guard result.succeeded else {
            let details = result.stderr.isEmpty ? result.stdout : result.stderr
            throw SmartContextError("Unable to resolve app context for \(scheme): \(details.trimmingCharacters(in: .whitespacesAndNewlines))")
        }

        var bundleId: String?
        var builtProductsDir: String?
        var fullProductName: String?

        for line in result.stdout.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("PRODUCT_BUNDLE_IDENTIFIER = ") {
                bundleId = String(trimmed.dropFirst("PRODUCT_BUNDLE_IDENTIFIER = ".count))
            } else if trimmed.hasPrefix("BUILT_PRODUCTS_DIR = ") {
                builtProductsDir = String(trimmed.dropFirst("BUILT_PRODUCTS_DIR = ".count))
            } else if trimmed.hasPrefix("FULL_PRODUCT_NAME = ") {
                fullProductName = String(trimmed.dropFirst("FULL_PRODUCT_NAME = ".count))
            }
        }

        guard let bundleId else {
            throw SmartContextError("Build settings did not contain PRODUCT_BUNDLE_IDENTIFIER for \(scheme)")
        }
        guard let builtProductsDir, let fullProductName else {
            throw SmartContextError("Build settings did not contain an app product path for \(scheme)")
        }

        return BuildProductInfo(bundleId: bundleId, appPath: "\(builtProductsDir)/\(fullProductName)")
    }

    private static func extractBuildInfo(
        project: String, scheme: String, simulator: String, configuration: String,
        env: Environment
    ) async -> (bundleId: String?, appPath: String?) {
        guard let info = try? await resolveBuildProductInfo(
            project: project,
            scheme: scheme,
            simulator: simulator,
            configuration: configuration,
            env: env
        ) else {
            return (nil, nil)
        }

        return (info.bundleId, info.appPath)
    }

    static func listSchemes(_ args: [String: Value]?, env: Environment) async -> CallTool.Result {
        switch ToolInput.decode(ListSchemesInput.self, from: args) {
        case .failure(let err): return err
        case .success(let input): return await listSchemesImpl(input, env: env)
        }
    }

    private static func listSchemesImpl(_ input: ListSchemesInput, env: Environment) async -> CallTool.Result {
        let project: String
        do {
            project = try await env.session.resolveProject(input.project)
        } catch {
            return .fail("\(error)")
        }

        let isWorkspace = project.hasSuffix(".xcworkspace")
        let projectFlag = isWorkspace ? "-workspace" : "-project"

        do {
            let result = try await env.shell.run("/usr/bin/xcodebuild", arguments: [
                projectFlag, project, "-list", "-json",
            ], timeout: 15)
            if result.succeeded {
                if let data = result.stdout.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let key = isWorkspace ? "workspace" : "project"
                    if let info = json[key] as? [String: Any],
                       let schemes = info["schemes"] as? [String] {
                        return .ok("Schemes:\n" + schemes.map { "  - \($0)" }.joined(separator: "\n"))
                    }
                }
                return .ok(result.stdout)
            }
            return .fail("Failed: \(result.stderr)")
        } catch {
            return .fail("Error: \(error)")
        }
    }

    // MARK: - Public execution functions for CLI

    public struct CleanExecution: Codable, Sendable {
        public let succeeded: Bool
        public let project: String
        public let scheme: String
        public let error: String?
    }

    public static func executeClean(
        project: String? = nil,
        scheme: String? = nil,
        env: Environment = .live
    ) async throws -> CleanExecution {
        let resolvedProject = try await env.session.resolveProject(project)
        let resolvedScheme = try await env.session.resolveScheme(scheme, project: resolvedProject)

        let isWorkspace = resolvedProject.hasSuffix(".xcworkspace")
        let projectFlag = isWorkspace ? "-workspace" : "-project"

        let result = try await Shell.run("/usr/bin/xcodebuild", arguments: [
            projectFlag, resolvedProject, "-scheme", resolvedScheme, "clean",
        ], timeout: 60)

        return CleanExecution(
            succeeded: result.succeeded,
            project: resolvedProject,
            scheme: resolvedScheme,
            error: result.succeeded ? nil : result.stderr
        )
    }

    public struct DiscoverExecution: Codable, Sendable {
        public let path: String
        public let projects: [String]
    }

    public static func executeDiscover(path: String) async throws -> DiscoverExecution {
        let result = try await Shell.run("/usr/bin/find", arguments: [
            path, "-maxdepth", "3",
            "(", "-name", "*.xcodeproj", "-o", "-name", "*.xcworkspace", ")",
            "-not", "-path", "*/Pods/*",
            "-not", "-path", "*/.build/*",
        ], timeout: 15)

        let projects = result.stdout
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty }

        return DiscoverExecution(path: path, projects: projects)
    }

    public struct SchemesExecution: Codable, Sendable {
        public let succeeded: Bool
        public let project: String
        public let schemes: [String]
        public let error: String?
    }

    public static func executeListSchemes(
        project: String? = nil,
        env: Environment = .live
    ) async throws -> SchemesExecution {
        let resolvedProject = try await env.session.resolveProject(project)

        let isWorkspace = resolvedProject.hasSuffix(".xcworkspace")
        let projectFlag = isWorkspace ? "-workspace" : "-project"

        let result = try await Shell.run("/usr/bin/xcodebuild", arguments: [
            projectFlag, resolvedProject, "-list", "-json",
        ], timeout: 15)

        guard result.succeeded else {
            return SchemesExecution(
                succeeded: false,
                project: resolvedProject,
                schemes: [],
                error: result.stderr
            )
        }

        var schemes: [String] = []
        if let data = result.stdout.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let key = isWorkspace ? "workspace" : "project"
            if let info = parsed[key] as? [String: Any],
               let s = info["schemes"] as? [String] {
                schemes = s
            }
        }

        return SchemesExecution(
            succeeded: true,
            project: resolvedProject,
            schemes: schemes,
            error: nil
        )
    }
}

extension BuildTools: ToolProvider {
    public static func dispatch(_ name: String, _ args: [String: Value]?, env: Environment) async -> CallTool.Result? {
        switch name {
        case "build_sim":         return await buildSim(args, env: env)
        case "build_run_sim":     return await buildRunSim(args, env: env)
        case "clean":             return await clean(args, env: env)
        case "discover_projects": return await discoverProjects(args, env: env)
        case "list_schemes":      return await listSchemes(args, env: env)
        default: return nil
        }
    }
}

import Foundation
import MCP

/// Error for build settings resolution failures (bundle ID, product path).
struct BuildSettingsError: Error, CustomStringConvertible {
  let description: String
  init(_ message: String) { self.description = message }
}

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
    public let xcresultPath: String?
    public let issues: [TestTools.BuildIssueObservation]?
    public let errorCount: Int?
    public let warningCount: Int?
  }

  /// Returns true if `text` contains a known infrastructure failure pattern.
  static func isInfrastructureMessage(_ text: String) -> Bool {
    let lower = text.lowercased()
    return lower.contains("unable to open database")
      || lower.contains("locked database")
      || lower.contains("database is locked")
      || (lower.contains("corrupted") && lower.contains("database"))
      || lower.contains("couldn't load project")
      || lower.contains("operation never finished bootstrapping")
  }

  /// Classify the reason a build failed from xcodebuild stderr.
  static func classifyFailureReason(stderr: String) -> String {
    let lower = stderr.lowercased()
    if isInfrastructureMessage(stderr) {
      return "infrastructure"
    }
    if lower.contains("no signing certificate") || lower.contains("provisioning profile")
      || lower.contains("code signing") || lower.contains("requires a provisioning profile")
      || lower.contains("signing certificate")
    {
      return "signing_error"
    }
    if lower.contains("undefined symbols") || lower.contains("ld: ")
      || lower.contains("linker command failed")
    {
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
        return isInfrastructureMessage(line)
          || (lower.contains("error:") && !lower.contains("sourcekit"))
      }.prefix(20).map { $0 }
    }

    // Reuse TestTools' stderr parser for structured error extraction
    let issues = TestTools.fallbackBuildIssues(stderr: stderr)
    let errorIssues = issues.filter { $0.severity == .error }
    if !errorIssues.isEmpty {
      return Array(
        errorIssues.prefix(20).map { issue in
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
          "project": .object([
            "type": .string("string"),
            "description": .string(
              "Path to .xcodeproj or .xcworkspace. Auto-detected from working directory if omitted."
            ),
          ]),
          "scheme": .object([
            "type": .string("string"),
            "description": .string(
              "Xcode scheme name. Auto-detected if project has only one scheme."),
          ]),
          "simulator": .object([
            "type": .string("string"),
            "description": .string(
              "Simulator name or UDID. Auto-detected from booted simulator if omitted."),
          ]),
          "configuration": .object([
            "type": .string("string"),
            "description": .string("Build configuration (Debug/Release). Default: Debug"),
          ]),
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
          "project": .object([
            "type": .string("string"),
            "description": .string(
              "Path to .xcodeproj or .xcworkspace. Auto-detected from working directory if omitted."
            ),
          ]),
          "scheme": .object([
            "type": .string("string"),
            "description": .string(
              "Xcode scheme name. Auto-detected if project has only one scheme."),
          ]),
          "simulator": .object([
            "type": .string("string"),
            "description": .string(
              "Simulator name or UDID. Auto-detected from booted simulator if omitted."),
          ]),
          "configuration": .object([
            "type": .string("string"),
            "description": .string("Build configuration (Debug/Release). Default: Debug"),
          ]),
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
          "project": .object([
            "type": .string("string"),
            "description": .string("Path to .xcodeproj or .xcworkspace. Auto-detected if omitted."),
          ]),
          "scheme": .object([
            "type": .string("string"),
            "description": .string("Xcode scheme name. Auto-detected if omitted."),
          ]),
        ]),
      ])
    ),
    Tool(
      name: "discover_projects",
      description: "Find Xcode projects and workspaces in a directory.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "path": .object([
            "type": .string("string"), "description": .string("Directory to search in"),
          ])
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
          "project": .object([
            "type": .string("string"),
            "description": .string("Path to .xcodeproj or .xcworkspace. Auto-detected if omitted."),
          ])
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

    // Always generate an xcresult bundle for structured diagnostics
    let resultPath = TestTools.xcresultPath(prefix: "build")
    _ = try? await env.shell.run("/bin/rm", arguments: ["-rf", resultPath], timeout: 5)

    var buildArgs = [
      projectFlag, resolvedProject,
      "-scheme", resolvedScheme,
      "-configuration", configuration,
      "-destination", destination,
      "-skipMacroValidation",
      "-parallelizeTargets",
      "-resultBundlePath", resultPath,
      "build",
    ]
    buildArgs += ["COMPILATION_CACHE_ENABLE_CACHING=YES"]

    let start = CFAbsoluteTimeGetCurrent()
    let result = try await env.shell.run("/usr/bin/xcodebuild", arguments: buildArgs, timeout: 1800)
    let elapsed = String(format: "%.1f", CFAbsoluteTimeGetCurrent() - start)

    // Extract structured issues from xcresult (best source of diagnostics)
    let xcresultIssues = await extractIssuesFromXcresult(resultPath, env: env)

    if result.succeeded {
      let buildInfo = await extractBuildInfo(
        project: resolvedProject, scheme: resolvedScheme,
        simulator: resolvedSimulator, configuration: configuration,
        env: env
      )

      if let bid = buildInfo.bundleId {
        await env.session.setBuildInfo(
          bundleId: bid, appPath: buildInfo.appPath, scheme: resolvedScheme)
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
        structuredErrors: nil,
        xcresultPath: resultPath,
        issues: xcresultIssues.issues.isEmpty ? nil : xcresultIssues.issues,
        errorCount: xcresultIssues.errorCount,
        warningCount: xcresultIssues.warningCount
      )
    } else {
      // Use xcresult issues if available, fall back to stderr parsing
      var issues = xcresultIssues.issues
      var errorCount = xcresultIssues.errorCount
      var warningCount = xcresultIssues.warningCount

      if issues.isEmpty {
        issues = TestTools.fallbackBuildIssues(stderr: result.stderr)
        errorCount = issues.filter { $0.severity == .error }.count
        warningCount = issues.filter { $0.severity == .warning }.count
      }

      // Classify failure from xcresult issues first, then stderr
      let reason: String
      if !issues.isEmpty {
        reason = classifyFailureFromIssues(issues)
      } else {
        reason = classifyFailureReason(stderr: result.stderr)
      }

      let structured = extractStructuredErrors(stderr: result.stderr, failureReason: reason)
      let errors = extractLegacyErrors(from: result.stderr)

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
        structuredErrors: structured,
        xcresultPath: resultPath,
        issues: issues.isEmpty ? nil : issues,
        errorCount: errorCount,
        warningCount: warningCount
      )
    }
  }

  /// Extract structured issues from an xcresult bundle.
  private static func extractIssuesFromXcresult(
    _ path: String, env: Environment
  ) async -> (
    issues: [TestTools.BuildIssueObservation], errorCount: Int, warningCount: Int,
    analyzerWarningCount: Int
  ) {
    guard let buildJSON = await TestTools.parseBuildResults(path, env: env),
      let data = buildJSON.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return ([], 0, 0, 0)
    }
    let parsed = TestTools.parseBuildIssues(json)
    return (parsed.issues, parsed.errorCount, parsed.warningCount, parsed.analyzerWarningCount)
  }

  /// Classify failure reason from structured issues (more reliable than stderr).
  private static func classifyFailureFromIssues(
    _ issues: [TestTools.BuildIssueObservation]
  ) -> String {
    let errors = issues.filter { $0.severity == .error }
    for error in errors {
      let lower = error.message.lowercased()
      if isInfrastructureMessage(error.message) {
        return "infrastructure"
      }
      if lower.contains("no signing certificate") || lower.contains("provisioning profile")
        || lower.contains("code signing") || lower.contains("requires a provisioning profile")
      {
        return "signing_error"
      }
      if lower.contains("undefined symbols") || lower.contains("linker command failed") {
        return "linker_error"
      }
    }
    return errors.isEmpty ? "unknown" : "compiler_error"
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
          var output =
            "Build succeeded in \(execution.elapsed)s\nScheme: \(execution.scheme)\nSimulator: \(execution.simulator)"
          if let bid = execution.bundleId {
            output += "\nBundle ID: \(bid)"
          }
          if let path = execution.appPath {
            output += "\nApp path: \(path)"
          }
          if let path = execution.xcresultPath {
            output += "\nxcresult: \(path)"
          }
          if let issues = execution.issues {
            let warnings = issues.filter { $0.severity == .warning }
            if !warnings.isEmpty {
              output += "\nWarnings (\(warnings.count)):"
              for w in warnings.prefix(5) {
                output += "\n  \(formatIssue(w))"
              }
            }
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

  private static func extractLegacyErrors(from stderr: String) -> [String] {
    let errorLines = stderr.split(separator: "\n")
      .filter { $0.contains(": error:") }
      .prefix(20)
      .map(String.init)
    let stderrTail = String(stderr.suffix(2000))
    return errorLines.isEmpty
      ? (stderrTail.isEmpty ? [] : [stderrTail])
      : Array(errorLines)
  }

  static func formatBuildFailure(_ execution: BuildExecution) -> String {
    var lines: [String] = []
    lines.append("Build FAILED in \(execution.elapsed)s")

    if let reason = execution.failureReason {
      lines.append("Failure reason: \(reason)")
    }

    lines.append("Scheme: \(execution.scheme)")
    lines.append("Simulator: \(execution.simulator)")
    lines.append("Configuration: \(execution.configuration)")

    // Prefer xcresult-parsed issues (most structured and actionable)
    if let issues = execution.issues, !issues.isEmpty {
      let errors = issues.filter { $0.severity == .error }
      let warnings = issues.filter { $0.severity != .error }
      if !errors.isEmpty {
        lines.append("")
        lines.append("Errors (\(errors.count)):")
        for issue in errors.prefix(20) {
          lines.append("  \(formatIssue(issue))")
        }
      }
      if !warnings.isEmpty {
        lines.append("")
        lines.append("Warnings (\(warnings.count)):")
        for issue in warnings.prefix(10) {
          lines.append("  \(formatIssue(issue))")
        }
      }
    } else if let structured = execution.structuredErrors, !structured.isEmpty {
      lines.append("")
      lines.append("Errors (\(structured.count)):")
      for error in structured {
        lines.append("  \(error)")
      }
    } else if !execution.errors.isEmpty {
      lines.append("")
      lines.append("Errors (\(execution.errors.count)):")
      for error in execution.errors {
        lines.append("  \(error)")
      }
    }

    if let path = execution.xcresultPath {
      lines.append("")
      lines.append("xcresult: \(path)")
    }

    return lines.joined(separator: "\n")
  }

  /// Format a single build issue for display.
  private static func formatIssue(_ issue: TestTools.BuildIssueObservation) -> String {
    if let loc = issue.location {
      let shortPath = (loc.filePath as NSString).lastPathComponent
      var location = shortPath
      if let line = loc.line {
        location += ":\(line)"
        if let col = loc.column { location += ":\(col)" }
      }
      return "\(location): \(issue.message)"
    }
    return issue.message
  }

  /// Find the most recent xcresult bundle from a build in /tmp.
  public static func findRecentBuildXcresult(env: Environment = .live) async -> String? {
    do {
      let result = try await env.shell.run(
        "/bin/ls", arguments: ["-1t", "/tmp/"], timeout: 5)
      guard result.succeeded else { return nil }
      let candidates = result.stdout.split(separator: "\n")
        .map(String.init)
        .filter { $0.hasPrefix("xcf-build-") && $0.hasSuffix(".xcresult") }
      return candidates.first.map { "/tmp/\($0)" }
    } catch {
      return nil
    }
  }

  /// Parse issues from an existing xcresult bundle without rebuilding.
  public static func diagnoseFromXcresult(
    path: String, errorsOnly: Bool = false, env: Environment = .live
  ) async -> (
    issues: [TestTools.BuildIssueObservation], errorCount: Int, warningCount: Int,
    analyzerWarningCount: Int, xcresultPath: String
  ) {
    guard let buildJSON = await TestTools.parseBuildResults(path, env: env),
      let data = buildJSON.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return ([], 0, 0, 0, path)
    }
    let parsed = TestTools.parseBuildIssues(json)
    let issues =
      errorsOnly
      ? parsed.issues.filter { $0.severity == .error }
      : parsed.issues
    return (issues, parsed.errorCount, parsed.warningCount, parsed.analyzerWarningCount, path)
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
        let result = try await env.shell.run(
          "/usr/bin/xcodebuild",
          arguments: [
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
        let result = try await env.shell.run(
          "/usr/bin/find",
          arguments: [
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

  private static func buildRunSimImpl(_ input: BuildInput, env: Environment) async
    -> CallTool.Result
  {
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

    // Always generate xcresult for structured diagnostics
    let resultPath = TestTools.xcresultPath(prefix: "build")
    _ = try? await env.shell.run("/bin/rm", arguments: ["-rf", resultPath], timeout: 5)

    let buildArgs = [
      projectFlag, project,
      "-scheme", scheme,
      "-configuration", configuration,
      "-destination", destination,
      "-skipMacroValidation",
      "-parallelizeTargets",
      "-resultBundlePath", resultPath,
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
    async let buildTask = env.shell.run("/usr/bin/xcodebuild", arguments: buildArgs, timeout: 1800)
    async let settingsTask = env.shell.run(
      "/usr/bin/xcodebuild", arguments: settingsArgs, timeout: 30)
    async let bootTask = env.shell.run(
      "/usr/bin/xcrun", arguments: ["simctl", "boot", udid], timeout: 60)
    async let openTask = env.shell.run(
      "/usr/bin/open", arguments: ["-a", "Simulator"], timeout: 10)

    // Await build first (critical — abort if it fails)
    let buildResult: ShellResult
    do {
      buildResult = try await buildTask
    } catch {
      return .fail("Build error: \(error)")
    }

    let buildElapsed = String(format: "%.1f", CFAbsoluteTimeGetCurrent() - totalStart)

    guard buildResult.succeeded else {
      let xcresultIssues = await extractIssuesFromXcresult(resultPath, env: env)
      var issues = xcresultIssues.issues
      var errorCount = xcresultIssues.errorCount
      var warningCount = xcresultIssues.warningCount

      if issues.isEmpty {
        issues = TestTools.fallbackBuildIssues(stderr: buildResult.stderr)
        errorCount = issues.filter { $0.severity == .error }.count
        warningCount = issues.filter { $0.severity == .warning }.count
      }

      let reason =
        !issues.isEmpty
        ? classifyFailureFromIssues(issues) : classifyFailureReason(stderr: buildResult.stderr)
      let structured = extractStructuredErrors(stderr: buildResult.stderr, failureReason: reason)
      let legacyErrors = extractLegacyErrors(from: buildResult.stderr)

      let execution = BuildExecution(
        succeeded: false,
        elapsed: buildElapsed,
        scheme: scheme,
        simulator: simulator,
        configuration: configuration,
        bundleId: nil,
        appPath: nil,
        errors: legacyErrors,
        failureReason: reason,
        structuredErrors: structured,
        xcresultPath: resultPath,
        issues: issues.isEmpty ? nil : issues,
        errorCount: errorCount,
        warningCount: warningCount
      )
      return .fail(formatBuildFailure(execution))
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
      let findResult = try? await env.shell.run(
        "/usr/bin/find",
        arguments: [
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
    let plistResult = try? await env.shell.run(
      "/usr/libexec/PlistBuddy",
      arguments: ["-c", "Print :CFBundleIdentifier", plistPath], timeout: 5)
    if let r = plistResult, r.succeeded, !r.stdout.isEmpty {
      bundleId = r.stdout
    } else {
      return .fail(
        "Build succeeded in \(buildElapsed)s but could not read bundle ID from \(plistPath)")
    }

    await env.session.setBuildInfo(bundleId: bundleId, appPath: finalAppPath, scheme: scheme)

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
      installResult = try await env.shell.run(
        "/usr/bin/xcrun",
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
      launchResult = try await env.shell.run(
        "/usr/bin/xcrun",
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

    // simctl launch prints "<bundleId>: <pid>" on stdout
    let appPid = launchResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
      .split(separator: ":").last
      .map { String($0).trimmingCharacters(in: .whitespaces) }

    let totalElapsed = String(format: "%.1f", CFAbsoluteTimeGetCurrent() - totalStart)

    var output = "build_run_sim completed in \(totalElapsed)s"
    output += "\nScheme: \(scheme) | Simulator: \(simulator)"
    output += "\nBundle ID: \(bundleId)"
    output += "\nApp path: \(finalAppPath)"
    if let pid = appPid, !pid.isEmpty {
      output += "\nApp PID: \(pid)"
    }
    output += "\nApp running: true"
    output += "\n"
    output += "\n  Build:     \(buildElapsed)s"
    output += "\n  App info:  \(infoSource) (parallel)"
    output += "\n  Boot:      \(bootStatus) (parallel)"
    output += "\n  Install:   \(installElapsed)s"
    output += "\n  Launch:    OK"
    output += "\n  Simulator: opened"

    // Surface build warnings from xcresult if any
    let xcresultIssues = await extractIssuesFromXcresult(resultPath, env: env)
    let buildWarnings = xcresultIssues.issues.filter { $0.severity == .warning }
    if !buildWarnings.isEmpty {
      output += "\n"
      output += "\nWarnings (\(buildWarnings.count)):"
      for w in buildWarnings.prefix(5) {
        output += "\n  \(formatIssue(w))"
      }
    }

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

    let result = try await env.shell.run(
      "/usr/bin/xcodebuild",
      arguments: [
        projectFlag, project,
        "-scheme", scheme,
        "-configuration", configuration,
        "-destination", destination,
        "-showBuildSettings",
      ], timeout: 30)

    guard result.succeeded else {
      let details = result.stderr.isEmpty ? result.stdout : result.stderr
      throw BuildSettingsError(
        "Unable to resolve app context for \(scheme): \(details.trimmingCharacters(in: .whitespacesAndNewlines))"
      )
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
      throw BuildSettingsError(
        "Build settings did not contain PRODUCT_BUNDLE_IDENTIFIER for \(scheme)")
    }
    guard let builtProductsDir, let fullProductName else {
      throw BuildSettingsError("Build settings did not contain an app product path for \(scheme)")
    }

    return BuildProductInfo(bundleId: bundleId, appPath: "\(builtProductsDir)/\(fullProductName)")
  }

  private static func extractBuildInfo(
    project: String, scheme: String, simulator: String, configuration: String,
    env: Environment
  ) async -> (bundleId: String?, appPath: String?) {
    guard
      let info = try? await resolveBuildProductInfo(
        project: project,
        scheme: scheme,
        simulator: simulator,
        configuration: configuration,
        env: env
      )
    else {
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

  private static func listSchemesImpl(_ input: ListSchemesInput, env: Environment) async
    -> CallTool.Result
  {
    let project: String
    do {
      project = try await env.session.resolveProject(input.project)
    } catch {
      return .fail("\(error)")
    }

    let isWorkspace = project.hasSuffix(".xcworkspace")
    let projectFlag = isWorkspace ? "-workspace" : "-project"

    do {
      let result = try await env.shell.run(
        "/usr/bin/xcodebuild",
        arguments: [
          projectFlag, project, "-list", "-json",
        ], timeout: 15)
      if result.succeeded {
        if let data = result.stdout.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
          let key = isWorkspace ? "workspace" : "project"
          if let info = json[key] as? [String: Any],
            let schemes = info["schemes"] as? [String]
          {
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

    let result = try await Shell.run(
      "/usr/bin/xcodebuild",
      arguments: [
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
    let result = try await Shell.run(
      "/usr/bin/find",
      arguments: [
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

    let result = try await Shell.run(
      "/usr/bin/xcodebuild",
      arguments: [
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
      let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    {
      let key = isWorkspace ? "workspace" : "project"
      if let info = parsed[key] as? [String: Any],
        let s = info["schemes"] as? [String]
      {
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
  public static func dispatch(_ name: String, _ args: [String: Value]?, env: Environment) async
    -> CallTool.Result?
  {
    switch name {
    case "build_sim": return await buildSim(args, env: env)
    case "build_run_sim": return await buildRunSim(args, env: env)
    case "clean": return await clean(args, env: env)
    case "discover_projects": return await discoverProjects(args, env: env)
    case "list_schemes": return await listSchemes(args, env: env)
    default: return nil
    }
  }
}

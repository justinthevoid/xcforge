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
    public let hangDiagnosticPath: String?
    public let hangDiagnosticSummary: String?

    init(
      succeeded: Bool,
      elapsed: String,
      scheme: String,
      simulator: String,
      configuration: String,
      bundleId: String?,
      appPath: String?,
      errors: [String],
      failureReason: String?,
      structuredErrors: [String]?,
      xcresultPath: String?,
      issues: [TestTools.BuildIssueObservation]?,
      errorCount: Int?,
      warningCount: Int?,
      hangDiagnosticPath: String? = nil,
      hangDiagnosticSummary: String? = nil
    ) {
      self.succeeded = succeeded
      self.elapsed = elapsed
      self.scheme = scheme
      self.simulator = simulator
      self.configuration = configuration
      self.bundleId = bundleId
      self.appPath = appPath
      self.errors = errors
      self.failureReason = failureReason
      self.structuredErrors = structuredErrors
      self.xcresultPath = xcresultPath
      self.issues = issues
      self.errorCount = errorCount
      self.warningCount = warningCount
      self.hangDiagnosticPath = hangDiagnosticPath
      self.hangDiagnosticSummary = hangDiagnosticSummary
    }
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
        errorIssues.prefix(50).map { issue in
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

  public static let tools: [Tool] = coreTools + typecheckTools

  static let coreTools: [Tool] = [
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
          "long": .object([
            "type": .string("boolean"),
            "description": .string(
              "Raise the total time limit from 1800s to 7200s. Hangs are caught by idleTimeoutSeconds either way."
            ),
          ]),
          "diagnose": .object([
            "type": .string("boolean"),
            "description": .string(
              "Capture a diagnostic snapshot on completion even without a hang."
            ),
          ]),
        ]),
      ])
    ),
    Tool(
      name: "build_run_sim",
      description: """
        Build, install, and launch an iOS app on a simulator in one call (Xcode's Cmd+R). \
        Boots the simulator once the build succeeds, then reports whether the app is still \
        running 2s after launch, with the crash reason and top frames when it isn't. \
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
          "long": .object([
            "type": .string("boolean"),
            "description": .string(
              "Raise the total time limit from 1800s to 7200s. Hangs are caught by idleTimeoutSeconds either way."
            ),
          ]),
          "diagnose": .object([
            "type": .string("boolean"),
            "description": .string(
              "Capture a diagnostic snapshot on completion even without a hang, for baseline inspection."
            ),
          ]),
          "args": .object([
            "type": .string("array"), "items": .object(["type": .string("string")]),
            "description": .string("Launch arguments passed to the app."),
          ]),
          "env": .object([
            "type": .string("array"), "items": .object(["type": .string("string")]),
            "description": .string("Environment for the app, as KEY=VALUE strings."),
          ]),
          "url": .object([
            "type": .string("string"),
            "description": .string("URL or deep link to open once the app is running."),
          ]),
        ]),
      ])
    ),
    Tool(
      name: "build_compile",
      description: """
        Compile-only iOS build (no boot, install, or launch). \
        Fast feedback loop for "does it still compile?" — wraps `build_sim` semantics \
        without running the simulator pipeline. \
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
          "long": .object([
            "type": .string("boolean"),
            "description": .string(
              "Raise the total time limit from 1800s to 7200s. Hangs are caught by idleTimeoutSeconds either way."
            ),
          ]),
          "diagnose": .object([
            "type": .string("boolean"),
            "description": .string(
              "Capture a diagnostic snapshot on completion even without a hang."
            ),
          ]),
          "fromSnapshot": .object([
            "type": .string("boolean"),
            "description": .string(
              "Build a snapshot of the working tree (a git worktree under ~/.xcforge/snapshots), so edits made during the build don't affect it. Errors name the real files."
            ),
          ]),
        ]),
      ])
    ),
    Tool(
      name: "clean",
      description: """
        Clean the scheme's simulator build products. derivedData: true also deletes this \
        project's DerivedData folder (only this project's), the fix for "database is locked" \
        or a stale index. Project and scheme are auto-detected if omitted.
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
          "configuration": .object([
            "type": .string("string"),
            "description": .string("Build configuration (Debug/Release). Default: Debug"),
          ]),
          "derivedData": .object([
            "type": .string("boolean"),
            "description": .string("Also delete this project's DerivedData folder. Default: false"),
          ]),
        ]),
      ])
    ),
    Tool(
      name: "build_lock_status",
      description: """
        Show who holds the shared build lock and who is queued behind it, with wait times.         The lock path comes from the 'lock' argument, XCFORGE_BUILD_LOCK, or .xcforge.yaml buildLock.
        """,
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "lock": .object([
            "type": .string("string"),
            "description": .string("Lock file path. Defaults to the configured build lock."),
          ])
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
    let long: Bool?
    let diagnose: Bool?
    var args: [String]? = nil
    var env: [String]? = nil
    var url: String? = nil
    var fromSnapshot: Bool? = nil
  }

  struct CleanInput: Decodable {
    let project: String?
    let scheme: String?
    var configuration: String? = nil
    var derivedData: Bool? = nil
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
    long: Bool = false,
    diagnose: Bool = false,
    compileOnly: Bool = false,
    target: String? = nil,
    fromSnapshot: Bool = false,
    env: Environment = .live
  ) async throws -> BuildExecution {
    guard fromSnapshot else {
      return try await runBuild(
        project: project, scheme: scheme, simulator: simulator, configuration: configuration, long: long,
        diagnose: diagnose, compileOnly: compileOnly, target: target, buildProject: nil, env: env)
    }
    // Build a frozen copy of the tree so other agents' edits mid-build don't land in it, and
    // report file paths in the real tree, where the agent edits.
    let source = try await env.session.resolveProject(project)
    let handle = try await SourceSnapshot.prepare(project: source, env: env)
    defer { handle.release() }
    let execution = try await runBuild(
      project: source, scheme: scheme, simulator: simulator, configuration: configuration, long: long,
      diagnose: diagnose, compileOnly: compileOnly, target: target, buildProject: handle.project, env: env)
    return SourceSnapshot.remap(execution, from: handle.worktree, to: handle.repoRoot)
  }

  /// `buildProject` is the project actually built (a snapshot's copy) when it isn't `project`.
  private static func runBuild(
    project: String?, scheme: String?, simulator: String?, configuration: String, long: Bool, diagnose: Bool,
    compileOnly: Bool, target: String?, buildProject: String?, env: Environment
  ) async throws -> BuildExecution {
    let sourceProject = try await env.session.resolveProject(project)
    let resolvedProject = buildProject ?? sourceProject
    let isWorkspace = resolvedProject.hasSuffix(".xcworkspace")
    let projectFlag = isWorkspace ? "-workspace" : "-project"
    // One target compiles through its own scheme, or `-target` when it has none.
    let resolvedScheme: String
    let selector: [String]
    if let target {
      selector = try await resolveTargetSelector(target, project: resolvedProject, env: env)
      resolvedScheme = target
    } else {
      resolvedScheme = try await env.session.resolveScheme(scheme, project: sourceProject)
      selector = [projectFlag, resolvedProject, "-scheme", resolvedScheme]
    }
    let resolvedSimulator: String
    do {
      resolvedSimulator = try await env.session.resolveSimulator(simulator)
    } catch {
      // Compiling needs a simulator platform, not a particular booted device.
      guard compileOnly, simulator == nil, let fallback = await AutoDetect.simulatorForCompile() else {
        throw error
      }
      resolvedSimulator = fallback
    }

    let destination = await AutoDetect.buildDestination(resolvedSimulator)

    // Always generate an xcresult bundle for structured diagnostics
    let resultPath = TestTools.xcresultPath(prefix: "build")
    _ = try? await env.shell.run("/bin/rm", arguments: ["-rf", resultPath], timeout: 5)

    var buildArgs = selector + ["-configuration", configuration]
    if selector.contains("-target") {
      // -target builds take an SDK, not a destination; DerivedData is the scheme's so the
      // dependencies it already built are reused.
      buildArgs += ["-sdk", "iphonesimulator", "ONLY_ACTIVE_ARCH=YES"]
      let projectDir = (resolvedProject as NSString).deletingLastPathComponent
      if XcodebuildOptions.effective(cwd: projectDir).derivedDataPath == nil,
        let defaultScheme = try? await env.session.resolveScheme(nil, project: sourceProject),
        let derivedData = await schemeDerivedData(project: resolvedProject, scheme: defaultScheme, env: env)
      {
        buildArgs += ["-derivedDataPath", derivedData]
      }
    } else {
      buildArgs += ["-destination", destination]
    }
    buildArgs.append("-skipMacroValidation")
    buildArgs += TestTools.compileFlags
    buildArgs += ["-resultBundlePath", resultPath, "build"] + TestTools.compileSettings

    let start = CFAbsoluteTimeGetCurrent()
    let buildTimeout = await TestTools.resolveTestTimeout(long: long, env: env)
    let snapshotPath = TestTools.diagnosticSnapshotPath()
    let watchdog = HangWatchdog(
      udid: resolvedSimulator, snapshotPath: snapshotPath, sampleAt: HangWatchdog.defaultSampleAt,
      processMatch: resultPath, env: env)
    let result = try await Xcodebuild.run(buildArgs, timeout: buildTimeout, env: env)
    watchdog.cancel()
    let watchdogCapture = await watchdog.latestResult
    let diagResult: DiagnosticSnapshot.Result?
    if result.exitCode == -1 {
      if let captured = watchdogCapture {
        diagResult = captured
      } else {
        diagResult = await DiagnosticSnapshot.capture(
          udid: resolvedSimulator, snapshotPath: snapshotPath, processMatch: resultPath, env: env)
      }
    } else if diagnose {
      if let captured = watchdogCapture {
        diagResult = captured
      } else {
        diagResult = await DiagnosticSnapshot.capture(
          udid: resolvedSimulator, snapshotPath: snapshotPath, processMatch: resultPath, env: env)
      }
    } else {
      // A sample of a healthy build is noise; only a timeout or `diagnose` reports one.
      diagResult = nil
    }
    let elapsed = String(format: "%.1f", CFAbsoluteTimeGetCurrent() - start)

    // Extract structured issues from xcresult (best source of diagnostics)
    let xcresultIssues = await extractIssuesFromXcresult(resultPath, env: env)

    if result.succeeded {
      // Finding the app costs another xcodebuild call; a compile check doesn't need it.
      var buildInfo: (bundleId: String?, appPath: String?) = (nil, nil)
      if !compileOnly {
        buildInfo = await extractBuildInfo(
          project: resolvedProject, scheme: resolvedScheme,
          simulator: resolvedSimulator, configuration: configuration,
          env: env
        )
      }

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
        warningCount: xcresultIssues.warningCount,
        hangDiagnosticPath: diagResult?.filePath,
        hangDiagnosticSummary: diagResult?.summaryLine
      )
    } else {
      // Use xcresult issues if available, fall back to stderr parsing
      var issues = xcresultIssues.issues
      var errorCount = xcresultIssues.errorCount
      var warningCount = xcresultIssues.warningCount

      if issues.isEmpty {
        issues = TestTools.fallbackBuildIssues(stderr: Xcodebuild.combinedOutput(result))
        errorCount = issues.filter { $0.severity == .error }.count
        warningCount = issues.filter { $0.severity == .warning }.count
      }

      // Classify failure from xcresult issues first, then stderr
      let output = Xcodebuild.combinedOutput(result)
      let reason: String
      if let timeout = Xcodebuild.timeoutKind(result) {
        reason = "timeout_\(timeout.rawValue)"
      } else if !issues.isEmpty {
        reason = classifyFailureFromIssues(issues)
      } else {
        reason = classifyFailureReason(stderr: output)
      }

      var structured = extractStructuredErrors(stderr: output, failureReason: reason)
      if let explanation = Xcodebuild.timeoutExplanation(result) {
        structured.insert(explanation, at: 0)
      }
      let errors = extractLegacyErrors(from: output)

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
        warningCount: warningCount,
        hangDiagnosticPath: diagResult?.filePath,
        hangDiagnosticSummary: diagResult?.summaryLine
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

  /// MCP wrapper around `executeBuild` that performs only the compile step —
  /// no simulator boot, install, or launch. Faster path for "does it compile?" loops.
  static func buildCompile(_ args: [String: Value]?, env: Environment) async -> CallTool.Result {
    switch ToolInput.decode(BuildInput.self, from: args) {
    case .failure(let err): return err
    case .success(let input):
      do {
        let execution = try await executeBuild(
          project: input.project,
          scheme: input.scheme,
          simulator: input.simulator,
          configuration: await env.session.resolveConfiguration(input.configuration),
          long: input.long ?? false,
          diagnose: input.diagnose ?? false,
          compileOnly: true,
          fromSnapshot: input.fromSnapshot ?? false,
          env: env
        )
        if wantsAgentJSON(args) { return agentJSON(execution, action: "Compile") }

        if execution.succeeded {
          var output = "Compile succeeded in \(execution.elapsed)s"
          output += "\nScheme: \(execution.scheme)"
          output += "\nSimulator: \(execution.simulator)"
          output += "\nConfiguration: \(execution.configuration)"
          if let path = execution.xcresultPath {
            output += "\nxcresult: \(path)"
          }
          if let issues = execution.issues {
            let warnings = issues.filter { $0.severity == .warning }
            if !warnings.isEmpty {
              output += "\nWarnings (\(warnings.count)):"
              for w in warnings.prefix(5) {
                let loc = w.location.map { l -> String in
                  let short = (l.filePath as NSString).lastPathComponent
                  return l.line.map { "\(short):\($0)" } ?? short
                }
                output += "\n  \(loc ?? "-"): \(w.message)"
              }
            }
          }
          if let diag = execution.hangDiagnosticPath {
            output += "\nDiagnostic snapshot: \(diag)"
            if let summary = execution.hangDiagnosticSummary {
              output += "\nSummary: \(summary)"
            }
          }
          return .ok(output)
        }

        var failMsg = formatBuildFailure(execution)
        if let diag = execution.hangDiagnosticPath {
          failMsg += "\nDiagnostic snapshot: \(diag)"
          if let summary = execution.hangDiagnosticSummary {
            failMsg += "\nSummary: \(summary)"
          }
        }
        return .fail(failMsg)
      } catch {
        return .fail("Compile error: \(error)")
      }
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
          configuration: await env.session.resolveConfiguration(input.configuration),
          long: input.long ?? false,
          diagnose: input.diagnose ?? false,
          env: env
        )
        if wantsAgentJSON(args) { return agentJSON(execution, action: "Build") }

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
          if let diagPath = execution.hangDiagnosticPath {
            output += "\nDiagnostic snapshot: \(diagPath)"
            if let summary = execution.hangDiagnosticSummary {
              output += "\nSummary: \(summary)"
            }
          }
          return .ok(output)
        } else {
          var failMsg = formatBuildFailure(execution)
          if let diagPath = execution.hangDiagnosticPath {
            failMsg += "\nDiagnostic snapshot: \(diagPath)"
            if let summary = execution.hangDiagnosticSummary {
              failMsg += "\nSummary: \(summary)"
            }
          }
          return .fail(failMsg)
        }
      } catch {
        return .fail("Build error: \(error)")
      }
    }
  }

  private static func extractLegacyErrors(from stderr: String) -> [String] {
    let errorLines = stderr.split(separator: "\n")
      .filter { $0.contains(": error:") }
      .reduce(into: [Substring]()) { if !$0.contains($1) { $0.append($1) } }
      .prefix(50)
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
      // The timeout explanation is always the first structured line; show it even when
      // xcresult issues take over the error list below.
      if reason.hasPrefix("timeout"), let note = execution.structuredErrors?.first {
        lines.append(note)
      }
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
        for issue in errors.prefix(50) {
          lines.append("  \(formatIssue(issue))")
        }
        if errors.count > 50 { lines.append("  ... \(errors.count - 50) more in the xcresult") }
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

  /// Find this project's most recent build result bundle. Falls back to the newest
  /// xcforge build bundle in the artifact directory when no project can be resolved.
  public static func findRecentBuildXcresult(project: String? = nil, env: Environment = .live)
    async -> String?
  {
    if let resolved = try? await env.session.resolveProject(project) {
      return LastResultStore.latest(project: resolved, kind: .build)
    }
    let dir = XcodebuildOptions.artifactDirectory()
    do {
      let result = try await env.shell.run("/bin/ls", arguments: ["-1t", dir], timeout: 5)
      guard result.succeeded else { return nil }
      let candidates = result.stdout.split(separator: "\n")
        .map(String.init)
        .filter { $0.hasPrefix("xcf-build-") && $0.hasSuffix(".xcresult") }
      return candidates.first.map { (dir as NSString).appendingPathComponent($0) }
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
      do {
        let execution = try await executeClean(
          project: input.project, scheme: input.scheme, configuration: input.configuration,
          deleteDerivedData: input.derivedData ?? false, env: env)
        guard execution.succeeded else { return .fail("Clean failed: \(execution.error ?? "unknown error")") }
        var message = "Clean succeeded (\(execution.scheme))"
        if let removed = execution.removedDerivedData { message += "\nDeleted DerivedData: \(removed)" }
        return .ok(message)
      } catch {
        return .fail("\(error)")
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
            "-not", "-path", "*.xcodeproj/*",
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

    let configuration = await env.session.resolveConfiguration(input.configuration)
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

    var args = [
      projectFlag, project,
      "-scheme", scheme,
      "-configuration", configuration,
      "-destination", destination,
      "-skipMacroValidation",
    ]
    args += TestTools.compileFlags
    args += ["-resultBundlePath", resultPath, "build"] + TestTools.compileSettings
    let buildArgs = args

    let settingsArgs = [
      projectFlag, project,
      "-scheme", scheme,
      "-configuration", configuration,
      "-destination", destination,
      "-showBuildSettings", "-json",
    ]

    // ── Phase 1: build, with settings extraction alongside ──
    // The simulator boots only once the build succeeds: a failed build shouldn't cost a
    // booted simulator's memory on a shared Mac.
    let buildTimeout = await TestTools.resolveTestTimeout(long: input.long ?? false, env: env)
    let buildSnapshotPath = TestTools.diagnosticSnapshotPath()
    let buildWatchdog = HangWatchdog(
      udid: udid, snapshotPath: buildSnapshotPath, sampleAt: HangWatchdog.defaultSampleAt, processMatch: resultPath,
      env: env)
    async let buildTask = Xcodebuild.run(buildArgs, timeout: buildTimeout, env: env)
    async let settingsTask = Xcodebuild.run(settingsArgs, timeout: 60, env: env)

    // Await build first (critical — abort if it fails)
    let buildResult: ShellResult
    do {
      buildResult = try await buildTask
    } catch {
      buildWatchdog.cancel()
      return .fail("Build error: \(error)")
    }
    buildWatchdog.cancel()
    let buildDiagResult: DiagnosticSnapshot.Result?
    // A sample of a healthy build is noise; only a timeout or `diagnose` reports one.
    if buildResult.exitCode != -1 && !(input.diagnose ?? false) {
      buildDiagResult = nil
    } else if let captured = await buildWatchdog.latestResult {
      buildDiagResult = captured
    } else {
      buildDiagResult = await DiagnosticSnapshot.capture(
        udid: udid, snapshotPath: buildSnapshotPath, processMatch: resultPath, env: env)
    }

    let buildElapsed = String(format: "%.1f", CFAbsoluteTimeGetCurrent() - totalStart)

    guard buildResult.succeeded else {
      let xcresultIssues = await extractIssuesFromXcresult(resultPath, env: env)
      var issues = xcresultIssues.issues
      var errorCount = xcresultIssues.errorCount
      var warningCount = xcresultIssues.warningCount

      if issues.isEmpty {
        issues = TestTools.fallbackBuildIssues(stderr: Xcodebuild.combinedOutput(buildResult))
        errorCount = issues.filter { $0.severity == .error }.count
        warningCount = issues.filter { $0.severity == .warning }.count
      }

      let output = Xcodebuild.combinedOutput(buildResult)
      let reason =
        Xcodebuild.timeoutKind(buildResult).map { "timeout_\($0.rawValue)" }
        ?? (!issues.isEmpty
          ? classifyFailureFromIssues(issues) : classifyFailureReason(stderr: output))
      var structured = extractStructuredErrors(stderr: output, failureReason: reason)
      if let explanation = Xcodebuild.timeoutExplanation(buildResult) {
        structured.insert(explanation, at: 0)
      }
      let legacyErrors = extractLegacyErrors(from: output)

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
      var failMsg = formatBuildFailure(execution)
      if let diag = buildDiagResult {
        failMsg += "\nDiagnostic snapshot: \(diag.filePath)\nSummary: \(diag.summaryLine)"
      }
      return .fail(failMsg)
    }

    // The scheme's application target, from the JSON settings. Schemes also build
    // extensions and frameworks, so the last product listed isn't necessarily the app.
    var product: BuildProductInfo?
    if let settings = try? await settingsTask, settings.succeeded {
      product = appProduct(fromSettings: settings.stdout)
    }
    if product == nil {
      product = try? await resolveBuildProductInfo(
        project: project, scheme: scheme, simulator: simulator, configuration: configuration, env: env)
    }
    guard let product else {
      return .fail("Build succeeded in \(buildElapsed)s but scheme \(scheme) names no application target to install")
    }
    let finalAppPath = product.appPath

    // Info.plist is the truth for the bundle ID; build settings can hold unexpanded values.
    var bundleId = product.bundleId
    let plistResult = try? await env.shell.run(
      "/usr/libexec/PlistBuddy",
      arguments: ["-c", "Print :CFBundleIdentifier", "\(finalAppPath)/Info.plist"], timeout: 5)
    if let r = plistResult, r.succeeded, !r.stdout.isEmpty {
      bundleId = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    await env.session.setBuildInfo(bundleId: bundleId, appPath: finalAppPath, scheme: scheme)

    // Boot, and wait until the simulator can take an install.
    let bootStart = CFAbsoluteTimeGetCurrent()
    let bootResult = try? await env.shell.run(
      "/usr/bin/xcrun", arguments: ["simctl", "boot", udid], timeout: 60)
    let bootStatus: String
    if bootResult?.succeeded == true {
      bootStatus = "booted"
    } else if bootResult?.stderr.contains("current state: Booted") == true {
      bootStatus = "already running"
    } else {
      return .fail("Build succeeded in \(buildElapsed)s\nBoot FAILED: \(bootResult?.stderr ?? "unknown")")
    }
    _ = try? await env.shell.run(
      "/usr/bin/xcrun", arguments: ["simctl", "bootstatus", udid, "-b"], timeout: 120)
    await SimulatorApp.open(shell: env.shell)
    let bootElapsed = String(format: "%.1f", CFAbsoluteTimeGetCurrent() - bootStart)

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

    // Launch, then check the app is still up: a crash at startup still "launches".
    let launch = await SimTools.executeLaunchApp(
      simulator: udid, bundleId: bundleId, args: input.args, environment: input.env ?? [], url: input.url, env: env)
    guard launch.succeeded else {
      return .fail("Build + Install succeeded in \(buildElapsed)s\n\(launch.message)")
    }
    let appPid = launch.message.split(separator: "\n").lazy
      .compactMap { AppLiveness.pid(fromLaunchOutput: String($0)) }.first

    let totalElapsed = String(format: "%.1f", CFAbsoluteTimeGetCurrent() - totalStart)

    var output = "build_run_sim completed in \(totalElapsed)s"
    output += "\nScheme: \(scheme) | Simulator: \(simulator)"
    output += "\nBundle ID: \(bundleId)"
    output += "\nApp path: \(finalAppPath)"
    if let appPid { output += "\nApp PID: \(appPid)" }
    output += "\nApp running: true"
    if let url = input.url { output += "\nOpened: \(url)" }
    output += "\n"
    output += "\n  Build:     \(buildElapsed)s"
    output += "\n  Boot:      \(bootStatus) (\(bootElapsed)s)"
    output += "\n  Install:   \(installElapsed)s"
    output += "\n  Launch:    OK"

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

    if let diag = buildDiagResult {
      output += "\nDiagnostic snapshot: \(diag.filePath)\nSummary: \(diag.summaryLine)"
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

    let result = try await Xcodebuild.run(
      [
        projectFlag, project,
        "-scheme", scheme,
        "-configuration", configuration,
        "-destination", destination,
        "-showBuildSettings", "-json",
      ], timeout: 60, env: env)

    guard result.succeeded else {
      let details = result.stderr.isEmpty ? result.stdout : result.stderr
      throw BuildSettingsError(
        "Unable to resolve app context for \(scheme): \(details.trimmingCharacters(in: .whitespacesAndNewlines))"
      )
    }
    guard let product = appProduct(fromSettings: result.stdout) else {
      throw BuildSettingsError("Scheme \(scheme) builds no application target, so there is no app to install")
    }
    return product
  }

  /// The application target's product in `-showBuildSettings -json` output. Schemes also
  /// build extensions, frameworks and test bundles; only the app can be installed and
  /// launched, whichever target the output lists last.
  static func appProduct(fromSettings output: String) -> BuildProductInfo? {
    guard let data = output.data(using: .utf8),
      let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
    else { return nil }
    for entry in entries {
      guard let settings = entry["buildSettings"] as? [String: String],
        settings["PRODUCT_TYPE"] == "com.apple.product-type.application" || settings["WRAPPER_EXTENSION"] == "app",
        let bundleId = settings["PRODUCT_BUNDLE_IDENTIFIER"],
        let directory = settings["BUILT_PRODUCTS_DIR"],
        let name = settings["FULL_PRODUCT_NAME"]
      else { continue }
      return BuildProductInfo(bundleId: bundleId, appPath: "\(directory)/\(name)")
    }
    return nil
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
    /// The project's DerivedData folder, when `deleteDerivedData` removed it.
    public var removedDerivedData: String? = nil
  }

  /// Clean the scheme's products for the simulator build xcforge runs (same configuration,
  /// same build folder), and optionally delete this project's DerivedData folder, the fix
  /// for a corrupted build database or index.
  public static func executeClean(
    project: String? = nil,
    scheme: String? = nil,
    configuration: String? = nil,
    deleteDerivedData: Bool = false,
    env: Environment = .live
  ) async throws -> CleanExecution {
    let resolvedProject = try await env.session.resolveProject(project)
    let resolvedScheme = try await env.session.resolveScheme(scheme, project: resolvedProject)
    let resolvedConfiguration = await env.session.resolveConfiguration(configuration)

    let isWorkspace = resolvedProject.hasSuffix(".xcworkspace")
    let projectFlag = isWorkspace ? "-workspace" : "-project"
    let base = [
      projectFlag, resolvedProject, "-scheme", resolvedScheme, "-configuration", resolvedConfiguration,
      "-destination", "generic/platform=iOS Simulator",
    ]

    // Look the folder up before cleaning: the settings call needs a working project.
    var derivedData: String?
    if deleteDerivedData {
      let settings = try await Xcodebuild.run(base + ["-showBuildSettings", "-json"], timeout: 120, env: env)
      derivedData = settings.succeeded ? derivedDataFolder(fromSettings: settings.stdout) : nil
    }

    // A clean is killed after the usual stretch of silence, not a fixed 60s.
    let result = try await Xcodebuild.run(base + ["clean"], timeout: 1800, env: env)
    var execution = CleanExecution(
      succeeded: result.succeeded,
      project: resolvedProject,
      scheme: resolvedScheme,
      error: result.succeeded ? nil : Xcodebuild.combinedOutput(result)
    )
    guard deleteDerivedData else { return execution }
    guard let derivedData else {
      return CleanExecution(
        succeeded: false, project: resolvedProject, scheme: resolvedScheme,
        error: "Couldn't find this project's DerivedData folder from its build settings; nothing deleted.")
    }
    do {
      if FileManager.default.fileExists(atPath: derivedData) {
        try FileManager.default.removeItem(atPath: derivedData)
      }
      execution.removedDerivedData = derivedData
    } catch {
      return CleanExecution(
        succeeded: false, project: resolvedProject, scheme: resolvedScheme,
        error: "Deleting \(derivedData) failed: \(error)")
    }
    return execution
  }

  /// This project's DerivedData folder: BUILD_ROOT is `<folder>/Build/Products`. Anything
  /// that doesn't look like that, or is too short a path to be one project's folder, is
  /// refused rather than deleted.
  static func derivedDataFolder(fromSettings output: String) -> String? {
    guard let data = output.data(using: .utf8),
      let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
      let settings = entries.first?["buildSettings"] as? [String: String],
      let root = settings["BUILD_ROOT"]
    else { return nil }
    return derivedDataFolder(fromBuildRoot: root)
  }

  static func derivedDataFolder(fromBuildRoot root: String) -> String? {
    let suffix = "/Build/Products"
    guard root.hasPrefix("/"), root.hasSuffix(suffix) else { return nil }
    let folder = String(root.dropLast(suffix.count))
    let depth = folder.split(separator: "/").count
    guard depth >= 3, folder != NSHomeDirectory() else { return nil }
    return folder
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
        "-not", "-path", "*.xcodeproj/*",
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
  static func buildLockStatus(_ args: [String: Value]?, env: Environment) async -> CallTool.Result {
    let explicit = args?["lock"]?.stringValue
    guard let path = BuildLock.configuredPath(explicit: explicit, cwd: env.currentDirectoryPath())
    else {
      return .fail("No build lock configured. Pass 'lock', set XCFORGE_BUILD_LOCK, or add buildLock to .xcforge.yaml.")
    }
    let status = await BuildLock.status(path: path, env: env)
    return .ok(BuildLock.format(status))
  }

  public static func dispatch(_ name: String, _ args: [String: Value]?, env: Environment) async
    -> CallTool.Result?
  {
    switch name {
    case "build_sim": return await buildSim(args, env: env)
    case "build_compile": return await buildCompile(args, env: env)
    case "build_typecheck": return await buildTypecheck(args, env: env)
    case "lsp_setup": return await lspSetup(args, env: env)
    case "build_run_sim": return await buildRunSim(args, env: env)
    case "clean": return await clean(args, env: env)
    case "discover_projects": return await discoverProjects(args, env: env)
    case "list_schemes": return await listSchemes(args, env: env)
    case "build_lock_status": return await buildLockStatus(args, env: env)
    default: return nil
    }
  }
}

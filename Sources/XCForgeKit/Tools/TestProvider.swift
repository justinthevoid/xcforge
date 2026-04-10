import Foundation
import MCP

/// Error for coverage parsing and xccov failures.
struct CoverageError: Error, CustomStringConvertible {
  let description: String
  init(_ message: String) { self.description = message }
}

/// Error for test enumeration and discovery failures.
struct TestDiscoveryError: Error, CustomStringConvertible {
  let description: String
  init(_ message: String) { self.description = message }
}

public enum TestTools {
  public struct TestFailureObservation: Codable, Sendable, Equatable {
    public let testName: String
    public let testIdentifier: String
    public let message: String
    public let source: String
  }

  public struct BuildIssueObservation: Codable, Sendable, Equatable {
    public let severity: BuildIssueSeverity
    public let message: String
    public let location: SourceLocation?
    public let source: String
  }

  public struct BuildDiagnosisExecution: Codable, Sendable, Equatable {
    public let succeeded: Bool
    public let elapsed: String
    public let xcresultPath: String
    public let stderrEvidencePath: String?
    public let issues: [BuildIssueObservation]
    public let errorCount: Int
    public let warningCount: Int
    public let analyzerWarningCount: Int
    public let destinationDeviceName: String?
    public let destinationOSVersion: String?

    init(
      succeeded: Bool,
      elapsed: String,
      xcresultPath: String,
      stderrEvidencePath: String? = nil,
      issues: [BuildIssueObservation],
      errorCount: Int,
      warningCount: Int,
      analyzerWarningCount: Int,
      destinationDeviceName: String?,
      destinationOSVersion: String?
    ) {
      self.succeeded = succeeded
      self.elapsed = elapsed
      self.xcresultPath = xcresultPath
      self.stderrEvidencePath = stderrEvidencePath
      self.issues = issues
      self.errorCount = errorCount
      self.warningCount = warningCount
      self.analyzerWarningCount = analyzerWarningCount
      self.destinationDeviceName = destinationDeviceName
      self.destinationOSVersion = destinationOSVersion
    }
  }

  struct TestDiagnosisExecution: Sendable, Equatable {
    let succeeded: Bool
    let elapsed: String
    let xcresultPath: String
    let stderrEvidencePath: String?
    let failures: [TestFailureObservation]
    let totalTestCount: Int
    let failedTestCount: Int
    let passedTestCount: Int
    let skippedTestCount: Int
    let expectedFailureCount: Int
    let destinationDeviceName: String?
    let destinationOSVersion: String?
    let executionFailureMessage: String?
    let hasStructuredSummary: Bool

    init(
      succeeded: Bool,
      elapsed: String,
      xcresultPath: String,
      stderrEvidencePath: String? = nil,
      failures: [TestFailureObservation],
      totalTestCount: Int,
      failedTestCount: Int,
      passedTestCount: Int,
      skippedTestCount: Int,
      expectedFailureCount: Int,
      destinationDeviceName: String?,
      destinationOSVersion: String?,
      executionFailureMessage: String? = nil,
      hasStructuredSummary: Bool = true
    ) {
      self.succeeded = succeeded
      self.elapsed = elapsed
      self.xcresultPath = xcresultPath
      self.stderrEvidencePath = stderrEvidencePath
      self.failures = failures
      self.totalTestCount = totalTestCount
      self.failedTestCount = failedTestCount
      self.passedTestCount = passedTestCount
      self.skippedTestCount = skippedTestCount
      self.expectedFailureCount = expectedFailureCount
      self.destinationDeviceName = destinationDeviceName
      self.destinationOSVersion = destinationOSVersion
      self.executionFailureMessage = executionFailureMessage
      self.hasStructuredSummary = hasStructuredSummary
    }
  }

  public struct TestExecution: Codable, Sendable {
    public let succeeded: Bool
    public let elapsed: String
    public let xcresultPath: String
    public let scheme: String
    public let simulator: String
    public let totalTestCount: Int
    public let passedTestCount: Int
    public let failedTestCount: Int
    public let skippedTestCount: Int
    public let expectedFailureCount: Int
    public let failures: [TestFailureObservation]
    public let deviceName: String?
    public let osVersion: String?
    public let screenshotPaths: [ScreenshotAttachment]
    public let hasStructuredSummary: Bool
    public let buildFailed: Bool
    public let buildDiagnostics: [BuildIssueObservation]?
  }

  public struct ScreenshotAttachment: Codable, Sendable {
    public let testName: String
    public let path: String
  }

  public struct TestFailuresResult: Codable, Sendable {
    public let failures: [TestFailureObservation]
    public let screenshots: [ScreenshotAttachment]
    public let consoleByTest: [String: String]
    public let xcresultPath: String
  }

  public struct CoverageResult: Codable, Sendable {
    public let overallCoverage: Double?
    public let targets: [TargetCoverage]
    public let xcresultPath: String
  }

  public struct TargetCoverage: Codable, Sendable {
    public let name: String
    public let lineCoverage: Double
    public let files: [FileCoverage]
  }

  public struct FileCoverage: Codable, Sendable {
    public let name: String
    public let lineCoverage: Double
  }

  public struct FileCoverageDetail: Codable, Sendable {
    public let fileName: String
    public let lineCoverage: Double
    public let coveredLines: Int
    public let executableLines: Int
    public let functions: [FunctionCoverage]
    public let xcresultPath: String
  }

  public struct FunctionCoverage: Codable, Sendable {
    public let name: String
    public let lineNumber: Int
    public let lineCoverage: Double
    public let executionCount: Int
    public let executableLines: Int
  }

  private struct ParsedTestSummary {
    let result: String
    let totalTestCount: Int
    let failedTestCount: Int
    let passedTestCount: Int
    let skippedTestCount: Int
    let expectedFailureCount: Int
    let destinationDeviceName: String?
    let destinationOSVersion: String?
    let failures: [TestFailureObservation]
  }

  // MARK: - Input Structs

  struct TestSimInput: Decodable {
    var project: String?
    var scheme: String?
    var simulator: String?
    var configuration: String?
    var testplan: String?
    var filter: String?
    var coverage: Bool?
  }

  struct TestFailuresInput: Decodable {
    var xcresult_path: String?
    var project: String?
    var scheme: String?
    var simulator: String?
    var include_console: Bool?
  }

  struct TestCoverageInput: Decodable {
    var file: String?
    var xcresult_path: String?
    var project: String?
    var scheme: String?
    var simulator: String?
    var min_coverage: Double?
  }

  struct BuildAndDiagnoseInput: Decodable {
    var project: String?
    var scheme: String?
    var simulator: String?
    var configuration: String?
  }

  struct BuildAndTestInput: Decodable {
    var project: String?
    var scheme: String?
    var simulator: String?
    var configuration: String?
    var testplan: String?
    var filter: String?
    var coverage: Bool?
  }

  struct ListTestsInput: Decodable {
    var project: String?
    var scheme: String?
    var simulator: String?
    var filter: String?
  }

  // MARK: - Public Result Types for build_and_test

  public struct BuildAndTestResult: Codable, Sendable {
    public let phase: String  // "build" or "test"
    public let buildSucceeded: Bool
    public let buildElapsed: String
    public let buildDiagnostics: [BuildIssueObservation]?
    public let testResult: TestExecution?
  }

  public struct TestIdentifier: Codable, Sendable {
    public let target: String
    public let className: String
    public let methodName: String
    public let fullIdentifier: String
  }

  public struct ListTestsResult: Codable, Sendable {
    public let tests: [TestIdentifier]
    public let targetCount: Int
    public let classCount: Int
    public let testCount: Int
  }

  public static let tools: [Tool] = [
    Tool(
      name: "test_sim",
      description: """
        Run xcodebuild test on simulator and return structured xcresult summary. \
        Shows passed/failed/skipped/expected-failure counts and duration. \
        Project, scheme, and simulator are auto-detected if omitted.
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
          "simulator": .object([
            "type": .string("string"),
            "description": .string(
              "Simulator name or UDID. Auto-detected from booted simulator if omitted."),
          ]),
          "configuration": .object([
            "type": .string("string"),
            "description": .string("Build configuration (Debug/Release). Default: Debug"),
          ]),
          "testplan": .object([
            "type": .string("string"),
            "description": .string(
              "Test plan name. Required when filtering Swift Testing @Test suites (they are not discoverable by -only-testing without a testplan). Optional for XCTest."
            ),
          ]),
          "filter": .object([
            "type": .string("string"),
            "description": .string(
              "Test filter. Accepts: 'testMethod', 'TestClass/testMethod', or full 'TestTarget/TestClass/testMethod'. Target prefix auto-resolution works for XCTest only. Swift Testing @Test suites require the full Target/Suite path AND a testplan to be discoverable."
            ),
          ]),
          "coverage": .object([
            "type": .string("boolean"),
            "description": .string("Enable code coverage collection. Default: false"),
          ]),
        ]),
      ])
    ),
    Tool(
      name: "test_failures",
      description: """
        Get only failed tests with their error messages from an xcresult bundle. \
        Either provide an xcresult_path from a previous test_sim run, \
        or provide project/scheme to run tests first (auto-detected if omitted). \
        Returns test name + failure message for each failed test.
        """,
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "xcresult_path": .object([
            "type": .string("string"),
            "description": .string(
              "Path to existing .xcresult bundle. If provided, skips running tests."),
          ]),
          "project": .object([
            "type": .string("string"),
            "description": .string("Path to .xcodeproj or .xcworkspace. Auto-detected if omitted."),
          ]),
          "scheme": .object([
            "type": .string("string"),
            "description": .string("Xcode scheme name. Auto-detected if omitted."),
          ]),
          "simulator": .object([
            "type": .string("string"),
            "description": .string("Simulator name or UDID. Auto-detected if omitted."),
          ]),
          "include_console": .object([
            "type": .string("boolean"),
            "description": .string(
              "Include console output (print/NSLog) for each failed test. Default: false. Use when assertion message alone is not enough to diagnose the failure."
            ),
          ]),
        ]),
      ])
    ),
    Tool(
      name: "test_coverage",
      description: """
        Get code coverage report from an xcresult bundle. \
        Without file param: per-file overview (which files need tests?). \
        With file param: per-function detail (which functions are untested? how often called?). \
        Either provide xcresult_path or project/scheme (will run tests with coverage enabled). \
        Project, scheme, and simulator are auto-detected if omitted.
        """,
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "file": .object([
            "type": .string("string"),
            "description": .string(
              "Drill into a specific file: shows per-function coverage + execution counts. Filename or path (e.g. 'LoginViewModel.swift')."
            ),
          ]),
          "xcresult_path": .object([
            "type": .string("string"),
            "description": .string(
              "Path to existing .xcresult bundle (must have been built with coverage enabled)"),
          ]),
          "project": .object([
            "type": .string("string"),
            "description": .string("Path to .xcodeproj or .xcworkspace. Auto-detected if omitted."),
          ]),
          "scheme": .object([
            "type": .string("string"),
            "description": .string("Xcode scheme name. Auto-detected if omitted."),
          ]),
          "simulator": .object([
            "type": .string("string"),
            "description": .string("Simulator name or UDID. Auto-detected if omitted."),
          ]),
          "min_coverage": .object([
            "type": .string("number"),
            "description": .string(
              "Only show files below this coverage %. Default: 100 (show all)"),
          ]),
        ]),
      ])
    ),
    Tool(
      name: "build_and_diagnose",
      description: """
        Build an iOS app and extract structured errors/warnings from the xcresult bundle. \
        Returns only actionable diagnostics (errors, warnings) with file paths and line numbers. \
        Project, scheme, and simulator are auto-detected if omitted.
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
          "simulator": .object([
            "type": .string("string"),
            "description": .string("Simulator name or UDID. Auto-detected if omitted."),
          ]),
          "configuration": .object([
            "type": .string("string"),
            "description": .string("Build configuration (Debug/Release). Default: Debug"),
          ]),
        ]),
      ])
    ),
    Tool(
      name: "build_and_test",
      description: """
        Build an iOS app then run tests in one call. Short-circuits on build failure \
        with structured diagnostics (errors with file:line). If build succeeds, runs \
        tests and returns pass/fail summary. Preferred over separate build_and_diagnose + test_sim calls. \
        Project, scheme, and simulator are auto-detected if omitted.
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
          "simulator": .object([
            "type": .string("string"),
            "description": .string("Simulator name or UDID. Auto-detected if omitted."),
          ]),
          "configuration": .object([
            "type": .string("string"),
            "description": .string("Build configuration (Debug/Release). Default: Debug"),
          ]),
          "testplan": .object([
            "type": .string("string"),
            "description": .string(
              "Test plan name. Required when filtering Swift Testing @Test suites (they are not discoverable by -only-testing without a testplan). Optional for XCTest."
            ),
          ]),
          "filter": .object([
            "type": .string("string"),
            "description": .string(
              "Test filter. Accepts: 'testMethod', 'TestClass/testMethod', or full 'TestTarget/TestClass/testMethod'. Target prefix auto-resolution works for XCTest only. Swift Testing @Test suites require the full Target/Suite path AND a testplan to be discoverable."
            ),
          ]),
          "coverage": .object([
            "type": .string("boolean"),
            "description": .string("Enable code coverage collection. Default: false"),
          ]),
        ]),
      ])
    ),
    Tool(
      name: "list_tests",
      description: """
        List available test identifiers (Target/Class/method) for a scheme. \
        Use this to discover the correct filter format before running test_sim or build_and_test. \
        Builds for testing first (does not run tests). \
        Project, scheme, and simulator are auto-detected if omitted.
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
          "simulator": .object([
            "type": .string("string"),
            "description": .string("Simulator name or UDID. Auto-detected if omitted."),
          ]),
          "filter": .object([
            "type": .string("string"),
            "description": .string(
              "Substring filter on test identifiers. Returns only tests whose Target/Class/method contains this string. Use to verify filter format before running test_sim."
            ),
          ]),
        ]),
      ])
    ),
  ]

  // MARK: - Shared helpers

  /// Generate a unique xcresult path
  static func xcresultPath(prefix: String) -> String {
    let ts = Int(Date().timeIntervalSince1970)
    return "/tmp/xcf-\(prefix)-\(ts).xcresult"
  }

  /// Find the most recent xcresult bundle in /tmp that has coverage data.
  /// Returns the path if one is found and contains valid coverage, nil otherwise.
  private static func findRecentCoverageXcresult(env: Environment) async -> String? {
    do {
      // List xcresult bundles created by xcforge (test or cov prefixed)
      let result = try await env.shell.run(
        "/bin/ls",
        arguments: ["-1t", "/tmp/"],
        timeout: 5
      )
      guard result.succeeded else { return nil }
      let candidates = result.stdout.split(separator: "\n")
        .map(String.init)
        .filter { $0.hasPrefix("xcf-") && $0.hasSuffix(".xcresult") }

      // Try each candidate (sorted newest-first by ls -t) for valid coverage
      for candidate in candidates.prefix(5) {
        let path = "/tmp/\(candidate)"
        if let _ = await parseCoverage(path, env: env) {
          return path
        }
      }
    } catch {
      // Ignore — fallback to running tests
    }
    return nil
  }

  /// Resolve a partial test filter into the full `-only-testing` format.
  /// Agents often pass `ClassName/testMethod` or just `testMethod` without the test target prefix.
  /// This discovers the test target(s) and prepends when missing.
  static func resolveFilter(
    _ filter: String, project: String, env: Environment
  ) async -> String {
    let trimmedFilter = filter.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedFilter.isEmpty else { return filter }

    let componentCount = slashComponentCount(trimmedFilter)

    // 2+ unbracketed slashes means Target/Class/method — assume already complete
    if componentCount >= 3 {
      // Swift Testing workaround: xcodebuild strips a trailing "()" from the last
      // component of -only-testing identifiers. Swift Testing methods are internally
      // identified with "()", so we must append "()" again to survive the stripping.
      // e.g. "Target/Suite/testFoo()" → "Target/Suite/testFoo()()" so xcodebuild
      // strips the outer "()" and the inner "()" matches the Swift Testing identifier.
      if trimmedFilter.hasSuffix("()") && !trimmedFilter.hasSuffix("()()") {
        return trimmedFilter + "()"
      }
      return trimmedFilter
    }

    // Check if the first component already matches a known test target.
    // This prevents double-prepending (e.g. "Target/Suite" → "Target/Target/Suite").
    let firstComponent = extractFirstComponent(trimmedFilter)

    // 0 or 1 unbracketed slash — may need target prefix
    guard let targets = try? await AutoDetect.testTargets(project: project, env: env),
      !targets.isEmpty
    else {
      return trimmedFilter
    }

    // If the first component already IS a known test target, don't prepend
    if let firstComponent, targets.contains(firstComponent) {
      return trimmedFilter
    }

    if targets.count == 1 {
      return "\(targets[0])/\(trimmedFilter)"
    }

    // Ambiguous — log available targets for diagnostics
    Log.warn(
      "Multiple test targets found: \(targets.joined(separator: ", ")). Cannot auto-resolve filter '\(trimmedFilter)'. Prefix with target name, e.g. '\(targets[0])/\(trimmedFilter)'"
    )
    return trimmedFilter
  }

  /// Count slash-separated components, ignoring slashes inside `[...]` brackets.
  /// e.g. "Class/test[a/b/c]" → 2 components, "Target/Class/method" → 3 components.
  static func slashComponentCount(_ filter: String) -> Int {
    var count = 1
    var bracketDepth = 0
    for char in filter {
      if char == "[" {
        bracketDepth += 1
      } else if char == "]", bracketDepth > 0 {
        bracketDepth -= 1
      } else if char == "/", bracketDepth == 0 {
        count += 1
      }
    }
    return count
  }

  /// Extract the first slash-separated component (before the first unbracketed slash).
  private static func extractFirstComponent(_ filter: String) -> String? {
    var result = ""
    var bracketDepth = 0
    for char in filter {
      if char == "[" {
        bracketDepth += 1
        result.append(char)
      } else if char == "]", bracketDepth > 0 {
        bracketDepth -= 1
        result.append(char)
      } else if char == "/", bracketDepth == 0 {
        return result.isEmpty ? nil : result
      } else {
        result.append(char)
      }
    }
    return result.isEmpty ? nil : result
  }

  /// Discover test targets for error messages when filter resolution fails.
  static func availableTestTargets(project: String, env: Environment) async -> [String] {
    (try? await AutoDetect.testTargets(project: project, env: env)) ?? []
  }

  /// Generate diagnostic hint when a filter matched 0 tests.
  /// Attempts to enumerate available tests and suggest close matches.
  static func zeroMatchHint(
    filter: String, project: String?, scheme: String?, simulator: String?, testplan: String? = nil,
    env: Environment
  ) async -> String {
    var hint = "\n\n⚠️  0 tests matched filter \"\(filter)\""

    // Swift Testing hint: testplan is required for -only-testing to discover Swift Testing suites
    if testplan == nil {
      hint +=
        "\nHint: Swift Testing @Test suites require a testplan to be discoverable by -only-testing."
      hint +=
        "\nTry adding testplan, e.g.: test_sim(testplan: \"<YourTestPlan>\", filter: \"\(filter)\")"
    }

    guard
      let listResult = try? await executeListTests(
        project: project, scheme: scheme, simulator: simulator, env: env
      )
    else {
      hint += "\nCould not enumerate tests to suggest alternatives."
      return hint
    }
    hint += "\n(found \(listResult.testCount) XCTest identifiers in bundle via -enumerate-tests)"
    if listResult.testCount == 0 {
      hint +=
        "\nThe test bundle appears to be empty. Note: -enumerate-tests only discovers XCTest methods, not Swift Testing @Test suites."
      return hint
    }
    let lowered = filter.lowercased()
    let matches = listResult.tests.filter { $0.fullIdentifier.lowercased().contains(lowered) }
    if !matches.isEmpty {
      hint += "\nDid you mean:"
      for m in matches.prefix(10) {
        hint += "\n  \(m.fullIdentifier)"
      }
    } else {
      // Try fuzzy: check class names containing any word from the filter
      let classNames = Set(listResult.tests.map { $0.className })
      let suggestions = classNames.filter { $0.lowercased().contains(lowered) }
        .sorted().prefix(5)
      if !suggestions.isEmpty {
        hint += "\nSimilar classes: \(suggestions.joined(separator: ", "))"
      } else {
        hint += "\nNo similar identifiers found. Use list_tests to see all available test names."
      }
    }
    return hint
  }

  /// Build xcodebuild arguments common to build/test.
  /// Handles simulator names and UDIDs via AutoDetect.buildDestination.
  private static func xcodebuildBaseArgs(
    project: String, scheme: String, destination: String, configuration: String
  ) -> [String] {
    let isWorkspace = project.hasSuffix(".xcworkspace")
    let projectFlag = isWorkspace ? "-workspace" : "-project"
    return [
      projectFlag, project,
      "-scheme", scheme,
      "-configuration", configuration,
      "-destination", destination,
      "-skipMacroValidation",
    ]
  }

  /// Run xcodebuild test and return the xcresult path
  private static func runTests(
    project: String, scheme: String, destination: String,
    configuration: String, testplan: String?, filter: String?,
    coverage: Bool, resultPath: String,
    env: Environment
  ) async throws -> (ShellResult, String) {
    // Remove old xcresult if exists
    _ = try? await env.shell.run("/bin/rm", arguments: ["-rf", resultPath], timeout: 5)

    var args = xcodebuildBaseArgs(
      project: project, scheme: scheme,
      destination: destination, configuration: configuration
    )
    args += ["-resultBundlePath", resultPath]

    if coverage {
      args += ["-enableCodeCoverage", "YES"]
    }

    if let plan = testplan {
      args += ["-testPlan", plan]
    }

    if let f = filter {
      args += ["-only-testing", f]
    }

    args += ["test"]

    let result = try await env.shell.run(
      "/usr/bin/xcodebuild", arguments: args, timeout: 1800
    )
    return (result, resultPath)
  }

  /// Run xcodebuild build and return the xcresult path
  private static func runBuild(
    project: String, scheme: String, destination: String,
    configuration: String, resultPath: String,
    env: Environment
  ) async throws -> (ShellResult, String) {
    _ = try? await env.shell.run("/bin/rm", arguments: ["-rf", resultPath], timeout: 5)

    var args = xcodebuildBaseArgs(
      project: project, scheme: scheme,
      destination: destination, configuration: configuration
    )
    args += [
      "-parallelizeTargets",
      "-resultBundlePath", resultPath,
      "build",
    ]
    args += ["COMPILATION_CACHE_ENABLE_CACHING=YES"]

    let result = try await env.shell.run(
      "/usr/bin/xcodebuild", arguments: args, timeout: 1800
    )
    return (result, resultPath)
  }

  /// Parse xcresult test summary JSON
  private static func parseTestSummary(_ path: String, env: Environment) async -> String? {
    do {
      let result = try await env.shell.run(
        "/usr/bin/xcrun",
        arguments: ["xcresulttool", "get", "test-results", "summary", "--path", path, "--compact"],
        timeout: 30
      )
      guard result.succeeded else {
        Log.warn("parseTestSummary failed: \(result.stderr)")
        return nil
      }
      return result.stdout
    } catch {
      Log.warn("parseTestSummary error: \(error)")
      return nil
    }
  }

  /// Parse xcresult test details JSON
  private static func parseTestDetails(_ path: String, env: Environment) async -> String? {
    do {
      let result = try await env.shell.run(
        "/usr/bin/xcrun",
        arguments: ["xcresulttool", "get", "test-results", "tests", "--path", path, "--compact"],
        timeout: 30
      )
      guard result.succeeded else {
        Log.warn("parseTestDetails failed: \(result.stderr)")
        return nil
      }
      return result.stdout
    } catch {
      Log.warn("parseTestDetails error: \(error)")
      return nil
    }
  }

  /// Parse xcresult build results JSON
  static func parseBuildResults(_ path: String, env: Environment) async -> String? {
    do {
      let result = try await env.shell.run(
        "/usr/bin/xcrun",
        arguments: ["xcresulttool", "get", "build-results", "--path", path, "--compact"],
        timeout: 30
      )
      guard result.succeeded else {
        Log.warn("parseBuildResults failed: \(result.stderr)")
        return nil
      }
      return result.stdout
    } catch {
      Log.warn("parseBuildResults error: \(error)")
      return nil
    }
  }

  public static func executeBuildDiagnosis(
    project: String,
    scheme: String,
    simulator: String,
    configuration: String,
    env: Environment = .live
  ) async throws -> BuildDiagnosisExecution {
    let resultPath = xcresultPath(prefix: "build")
    let destination = await AutoDetect.buildDestination(simulator)

    let start = CFAbsoluteTimeGetCurrent()
    let (buildResult, path) = try await runBuild(
      project: project,
      scheme: scheme,
      destination: destination,
      configuration: configuration,
      resultPath: resultPath,
      env: env
    )
    let elapsed = String(format: "%.1f", CFAbsoluteTimeGetCurrent() - start)

    var issues: [BuildIssueObservation] = []
    var errorCount = 0
    var warningCount = 0
    var analyzerWarningCount = 0
    var destinationDeviceName: String?
    var destinationOSVersion: String?
    var stderrEvidencePath: String?

    if let buildJSON = await parseBuildResults(path, env: env),
      let data = buildJSON.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    {
      let parsed = parseBuildIssues(json)
      issues = parsed.issues
      errorCount = parsed.errorCount
      warningCount = parsed.warningCount
      analyzerWarningCount = parsed.analyzerWarningCount
      destinationDeviceName = parsed.destinationDeviceName
      destinationOSVersion = parsed.destinationOSVersion
    }

    if !buildResult.succeeded && issues.isEmpty {
      issues = fallbackBuildIssues(stderr: buildResult.stderr)
      errorCount = issues.filter { $0.severity == .error }.count
      warningCount = issues.filter { $0.severity == .warning }.count
      analyzerWarningCount = issues.filter { $0.severity == .analyzerWarning }.count
      if !buildResult.stderr.isEmpty {
        stderrEvidencePath = persistCommandStderr(buildResult.stderr, path: path, label: "stderr")
      }
    }

    return BuildDiagnosisExecution(
      succeeded: buildResult.succeeded,
      elapsed: elapsed,
      xcresultPath: path,
      stderrEvidencePath: stderrEvidencePath,
      issues: issues,
      errorCount: errorCount,
      warningCount: warningCount,
      analyzerWarningCount: analyzerWarningCount,
      destinationDeviceName: destinationDeviceName,
      destinationOSVersion: destinationOSVersion
    )
  }

  static func executeTestDiagnosis(
    project: String,
    scheme: String,
    simulator: String,
    configuration: String,
    env: Environment
  ) async throws -> TestDiagnosisExecution {
    let resultPath = xcresultPath(prefix: "test")
    let destination = await AutoDetect.buildDestination(simulator)

    let start = CFAbsoluteTimeGetCurrent()
    let (testResult, path) = try await runTests(
      project: project,
      scheme: scheme,
      destination: destination,
      configuration: configuration,
      testplan: nil,
      filter: nil,
      coverage: false,
      resultPath: resultPath,
      env: env
    )
    let elapsed = String(format: "%.1f", CFAbsoluteTimeGetCurrent() - start)

    let parsedSummary: ParsedTestSummary?
    if let summaryJSON = await parseTestSummary(path, env: env),
      let data = summaryJSON.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    {
      parsedSummary = parseTestSummary(json)
    } else {
      parsedSummary = nil
    }

    var failures: [TestFailureObservation] = []
    var executionFailureMessage: String?
    if let detailsJSON = await parseTestDetails(path, env: env),
      let data = detailsJSON.data(using: .utf8)
    {
      if let parsedFailures = parseTestFailures(data) {
        failures = parsedFailures
      } else {
        executionFailureMessage = "Failed to parse test details from \(path)."
      }
    }
    if failures.isEmpty {
      failures = parsedSummary?.failures ?? []
    }

    var stderrEvidencePath: String?
    if !testResult.succeeded && !testResult.stderr.isEmpty {
      stderrEvidencePath = persistCommandStderr(testResult.stderr, path: path, label: "stderr")
      if failures.isEmpty {
        executionFailureMessage =
          executionFailureMessage
          ?? extractExecutionFailureMessage(stderr: testResult.stderr)
      }
    }

    let totalTestCount = parsedSummary?.totalTestCount ?? failures.count
    let failedTestCount = parsedSummary?.failedTestCount ?? failures.count
    let passedTestCount = parsedSummary?.passedTestCount ?? 0
    let skippedTestCount = parsedSummary?.skippedTestCount ?? 0
    let expectedFailureCount = parsedSummary?.expectedFailureCount ?? 0

    return TestDiagnosisExecution(
      succeeded: testResult.succeeded && failedTestCount == 0,
      elapsed: elapsed,
      xcresultPath: path,
      stderrEvidencePath: stderrEvidencePath,
      failures: failures,
      totalTestCount: totalTestCount,
      failedTestCount: failedTestCount,
      passedTestCount: passedTestCount,
      skippedTestCount: skippedTestCount,
      expectedFailureCount: expectedFailureCount,
      destinationDeviceName: parsedSummary?.destinationDeviceName,
      destinationOSVersion: parsedSummary?.destinationOSVersion,
      executionFailureMessage: executionFailureMessage,
      hasStructuredSummary: parsedSummary != nil
    )
  }

  /// Export failure attachments (screenshots) from xcresult
  /// Returns array of (testId, filePath) tuples for exported images
  private static func exportFailureAttachments(_ xcresultPath: String, env: Environment) async -> [(
    test: String, path: String
  )] {
    let outputDir = "/tmp/xcf-attachments-\(Int(Date().timeIntervalSince1970))"
    do {
      _ = try await env.shell.run("/bin/mkdir", arguments: ["-p", outputDir], timeout: 5)
    } catch {
      Log.warn("exportFailureAttachments mkdir failed: \(error)")
      return []
    }
    let exportResult: ShellResult
    do {
      exportResult = try await env.shell.run(
        "/usr/bin/xcrun",
        arguments: [
          "xcresulttool", "export", "attachments",
          "--path", xcresultPath,
          "--output-path", outputDir,
          "--only-failures",
        ],
        timeout: 60
      )
    } catch {
      Log.warn("exportFailureAttachments export failed: \(error)")
      return []
    }
    guard exportResult.succeeded else {
      Log.warn("exportFailureAttachments: \(exportResult.stderr)")
      return []
    }

    // Parse manifest.json for exported files
    guard
      let manifestResult = try? await env.shell.run(
        "/bin/cat", arguments: ["\(outputDir)/manifest.json"], timeout: 5),
      let data = manifestResult.stdout.data(using: .utf8),
      let manifest = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
    else {
      return []
    }

    var attachments: [(test: String, path: String)] = []
    for entry in manifest {
      let testName = (entry["testIdentifier"] as? String) ?? (entry["testName"] as? String) ?? "?"
      if let fileName = entry["exportedFileName"] as? String {
        let filePath = "\(outputDir)/\(fileName)"
        attachments.append((test: testName, path: filePath))
      } else if let files = entry["attachments"] as? [[String: Any]] {
        for file in files {
          if let fileName = file["exportedFileName"] as? String {
            let filePath = "\(outputDir)/\(fileName)"
            attachments.append((test: testName, path: filePath))
          }
        }
      }
    }
    return attachments
  }

  /// Extract console output per failed test from xcresult action log
  /// Returns dict: testName → emittedOutput
  private static func extractFailedTestConsole(_ xcresultPath: String, env: Environment) async
    -> [String: String]
  {
    let shellResult: ShellResult
    do {
      shellResult = try await env.shell.run(
        "/usr/bin/xcrun",
        arguments: [
          "xcresulttool", "get", "log", "--path", xcresultPath, "--type", "action", "--compact",
        ],
        timeout: 30
      )
    } catch {
      Log.warn("extractFailedTestConsole error: \(error)")
      return [:]
    }
    guard shellResult.succeeded,
      let data = shellResult.stdout.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      if !shellResult.succeeded {
        Log.warn("extractFailedTestConsole failed: \(shellResult.stderr)")
      }
      return [:]
    }

    var consoleByTest: [String: String] = [:]

    // Recursively find test case subsections with testDetails.emittedOutput
    func findTestOutput(in node: [String: Any]) {
      if let testDetails = node["testDetails"] as? [String: Any],
        let testName = testDetails["testName"] as? String,
        let emitted = testDetails["emittedOutput"] as? String
      {
        // Only keep if it looks like a failure
        if emitted.contains("failed") || emitted.contains("issue") {
          // Trim to just the useful parts (skip "Test started" boilerplate)
          let lines = emitted.split(separator: "\n", omittingEmptySubsequences: false)
          let useful = lines.filter { !$0.hasPrefix("◇ Test") && !$0.isEmpty }
          if !useful.isEmpty {
            consoleByTest[testName] = useful.joined(separator: "\n")
          }
        }
      }

      if let subsections = node["subsections"] as? [[String: Any]] {
        for sub in subsections {
          findTestOutput(in: sub)
        }
      }
    }

    findTestOutput(in: json)
    return consoleByTest
  }

  /// Parse coverage report via xccov
  private static func parseCoverage(_ path: String, env: Environment) async -> String? {
    do {
      let result = try await env.shell.run(
        "/usr/bin/xcrun",
        arguments: ["xccov", "view", "--report", "--json", path],
        timeout: 30,
        outputLimit: 20 * 1024 * 1024  // full coverage reports for large projects can exceed the 2 MB default
      )
      guard result.succeeded else {
        Log.warn("parseCoverage failed: \(result.stderr)")
        return nil
      }
      return result.stdout
    } catch {
      Log.warn("parseCoverage error: \(error)")
      return nil
    }
  }

  // MARK: - Public Execution Methods

  public static func executeTest(
    project: String? = nil,
    scheme: String? = nil,
    simulator: String? = nil,
    configuration: String = "Debug",
    testplan: String? = nil,
    filter: String? = nil,
    coverage: Bool = false,
    env: Environment = .live
  ) async throws -> TestExecution {
    let resolvedProject = try await env.session.resolveProject(project)
    let resolvedScheme = try await env.session.resolveScheme(scheme, project: resolvedProject)
    let resolvedSimulator = try await env.session.resolveSimulator(simulator)
    let resolvedFilter: String?
    if let filter {
      resolvedFilter = await resolveFilter(filter, project: resolvedProject, env: env)
    } else {
      resolvedFilter = nil
    }
    let resultPath = xcresultPath(prefix: "test")
    let destination = await AutoDetect.buildDestination(resolvedSimulator)

    let start = CFAbsoluteTimeGetCurrent()
    let (buildResult, path) = try await runTests(
      project: resolvedProject, scheme: resolvedScheme, destination: destination,
      configuration: configuration, testplan: testplan,
      filter: resolvedFilter, coverage: coverage, resultPath: resultPath,
      env: env
    )
    let elapsed = String(format: "%.1f", CFAbsoluteTimeGetCurrent() - start)

    // Parse xcresult summary
    var parsedSummary: ParsedTestSummary?
    if let summaryJSON = await parseTestSummary(path, env: env),
      let data = summaryJSON.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    {
      parsedSummary = Self.parseTestSummary(json)
    }

    // Parse failures from test details
    var failures: [TestFailureObservation] = []
    if let detailsJSON = await parseTestDetails(path, env: env),
      let data = detailsJSON.data(using: .utf8),
      let parsedFailures = parseTestFailures(data)
    {
      failures = parsedFailures
    }
    if failures.isEmpty {
      failures = parsedSummary?.failures ?? []
    }

    // Export failure screenshots
    let hasFailures = (parsedSummary?.failedTestCount ?? failures.count) > 0
    var screenshots: [ScreenshotAttachment] = []
    if hasFailures {
      let attachments = await exportFailureAttachments(path, env: env)
      screenshots = attachments.map { ScreenshotAttachment(testName: $0.test, path: $0.path) }
    }

    // Parse build diagnostics from xcresult when the build failed
    var buildDiagnostics: [BuildIssueObservation]?
    let buildFailed = !buildResult.succeeded
    if buildFailed {
      if let buildJSON = await parseBuildResults(path, env: env),
        let data = buildJSON.data(using: .utf8),
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
      {
        let parsed = parseBuildIssues(json)
        if !parsed.issues.isEmpty {
          buildDiagnostics = parsed.issues
        }
      }
      // If xcresulttool didn't yield diagnostics, fall back to stderr
      if buildDiagnostics == nil {
        buildDiagnostics = fallbackBuildIssues(stderr: buildResult.stderr)
        if buildDiagnostics?.isEmpty == true { buildDiagnostics = nil }
      }
    }

    // Fallback error extraction for test failures list
    if buildFailed && failures.isEmpty {
      let errorLines = buildResult.stderr.split(separator: "\n")
        .filter { $0.contains(": error:") || $0.contains(" failed") || $0.contains("FAILED") }
        .prefix(20)
      if errorLines.isEmpty {
        // No parseable errors — surface the stderr tail so the user sees something
        let tail = String(buildResult.stderr.suffix(2000)).trimmingCharacters(
          in: .whitespacesAndNewlines)
        if !tail.isEmpty {
          failures = [
            TestFailureObservation(
              testName: "xcodebuild",
              testIdentifier: "xcodebuild",
              message: tail,
              source: "stderr"
            )
          ]
        }
      } else {
        failures = errorLines.map {
          TestFailureObservation(
            testName: "xcodebuild",
            testIdentifier: "xcodebuild",
            message: String($0),
            source: "stderr"
          )
        }
      }
    }

    let totalTestCount =
      parsedSummary?.totalTestCount ?? max(failures.count, buildResult.succeeded ? 0 : 1)
    let failedTestCount = parsedSummary?.failedTestCount ?? failures.count
    let passedTestCount = parsedSummary?.passedTestCount ?? 0
    let skippedTestCount = parsedSummary?.skippedTestCount ?? 0
    let expectedFailureCount = parsedSummary?.expectedFailureCount ?? 0

    // Filter matched nothing → treat as failure so agents don't assume tests passed
    let zeroMatchWithFilter = totalTestCount == 0 && filter != nil

    return TestExecution(
      succeeded: buildResult.succeeded && failedTestCount == 0 && !zeroMatchWithFilter,
      elapsed: elapsed,
      xcresultPath: path,
      scheme: resolvedScheme,
      simulator: resolvedSimulator,
      totalTestCount: totalTestCount,
      passedTestCount: passedTestCount,
      failedTestCount: failedTestCount,
      skippedTestCount: skippedTestCount,
      expectedFailureCount: expectedFailureCount,
      failures: failures,
      deviceName: parsedSummary?.destinationDeviceName,
      osVersion: parsedSummary?.destinationOSVersion,
      screenshotPaths: screenshots,
      hasStructuredSummary: parsedSummary != nil,
      buildFailed: buildFailed,
      buildDiagnostics: buildDiagnostics
    )
  }

  public static func extractFailures(
    xcresultPath: String? = nil,
    project: String? = nil,
    scheme: String? = nil,
    simulator: String? = nil,
    includeConsole: Bool = false,
    env: Environment = .live
  ) async throws -> TestFailuresResult {
    let resolvedPath: String
    if let provided = xcresultPath {
      resolvedPath = provided
    } else {
      let resolvedProject = try await env.session.resolveProject(project)
      let resolvedScheme = try await env.session.resolveScheme(scheme, project: resolvedProject)
      let resolvedSimulator = try await env.session.resolveSimulator(simulator)
      let destination = await AutoDetect.buildDestination(resolvedSimulator)
      let path = Self.xcresultPath(prefix: "fail")
      let (_, p) = try await runTests(
        project: resolvedProject, scheme: resolvedScheme, destination: destination,
        configuration: "Debug", testplan: nil, filter: nil,
        coverage: false, resultPath: path,
        env: env
      )
      resolvedPath = p
    }

    var failures: [TestFailureObservation] = []
    if let detailsJSON = await parseTestDetails(resolvedPath, env: env),
      let data = detailsJSON.data(using: .utf8),
      let parsed = parseTestFailures(data)
    {
      failures = parsed
    }

    let attachments = failures.isEmpty ? [] : await exportFailureAttachments(resolvedPath, env: env)
    let screenshots = attachments.map { ScreenshotAttachment(testName: $0.test, path: $0.path) }
    let consoleByTest =
      (includeConsole && !failures.isEmpty)
      ? await extractFailedTestConsole(resolvedPath, env: env) : [:]

    return TestFailuresResult(
      failures: failures,
      screenshots: screenshots,
      consoleByTest: consoleByTest,
      xcresultPath: resolvedPath
    )
  }

  public static func extractCoverage(
    file: String? = nil,
    xcresultPath: String? = nil,
    project: String? = nil,
    scheme: String? = nil,
    simulator: String? = nil,
    minCoverage: Double = 100.0,
    env: Environment = .live
  ) async throws -> CoverageResult {
    let resolvedPath: String
    if let provided = xcresultPath {
      resolvedPath = provided
    } else if let recent = await findRecentCoverageXcresult(env: env) {
      // Reuse a recent xcresult that already has coverage data
      resolvedPath = recent
    } else {
      // No coverage data available — fail fast instead of silently running the entire test suite
      throw CoverageError(
        "No coverage data available. Run tests with coverage enabled first:\n"
          + "  xcforge test run --coverage\n"
          + "Then run xcforge test coverage to view the report."
      )
    }

    guard let coverageJSON = await parseCoverage(resolvedPath, env: env),
      let data = coverageJSON.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      throw CoverageError(
        "Failed to parse coverage from \(resolvedPath). Was coverage enabled during the test run?")
    }

    let overallCoverage = json["lineCoverage"] as? Double
    var targets: [TargetCoverage] = []

    if let jsonTargets = json["targets"] as? [[String: Any]] {
      for target in jsonTargets {
        let name = (target["name"] as? String) ?? "?"
        let cov = (target["lineCoverage"] as? Double) ?? 0
        var files: [FileCoverage] = []

        if let jsonFiles = target["files"] as? [[String: Any]] {
          for f in jsonFiles {
            let path = (f["path"] as? String) ?? (f["name"] as? String) ?? "?"
            let fileCov = (f["lineCoverage"] as? Double) ?? 0
            if fileCov * 100 < minCoverage {
              let shortPath = (path as NSString).lastPathComponent
              files.append(FileCoverage(name: shortPath, lineCoverage: fileCov))
            }
          }
          files.sort { $0.lineCoverage < $1.lineCoverage }
        }

        targets.append(TargetCoverage(name: name, lineCoverage: cov, files: files))
      }
    }

    return CoverageResult(
      overallCoverage: overallCoverage, targets: targets, xcresultPath: resolvedPath)
  }

  public static func extractFileCoverage(
    file: String,
    xcresultPath: String,
    env: Environment = .live
  ) async throws -> FileCoverageDetail {
    let result: ShellResult
    do {
      result = try await env.shell.run(
        "/usr/bin/xcrun",
        arguments: [
          "xccov", "view", "--report", "--functions-for-file", file, "--json", xcresultPath,
        ],
        timeout: 30
      )
    } catch {
      throw CoverageError("xccov error for '\(file)': \(error)")
    }
    guard result.succeeded, !result.stdout.isEmpty else {
      throw CoverageError(
        "No coverage data for '\(file)'. File not in coverage report or coverage not enabled.\n\(result.stderr)"
      )
    }

    guard let data = result.stdout.data(using: .utf8),
      let raw = try? JSONSerialization.jsonObject(with: data)
    else {
      throw CoverageError("Failed to parse xccov JSON for '\(file)'")
    }

    var fileObjects: [[String: Any]] = []
    if let array = raw as? [[String: Any]] {
      fileObjects = array
    } else if let dict = raw as? [String: Any],
      let targets = dict["targets"] as? [[String: Any]]
    {
      for target in targets {
        if let files = target["files"] as? [[String: Any]] {
          fileObjects += files
        }
      }
    }

    let searchName = (file as NSString).lastPathComponent.lowercased()
    let matched = fileObjects.filter {
      let name = (($0["name"] as? String) ?? ($0["path"] as? String) ?? "").lowercased()
      return name.contains(searchName) || searchName.contains(name)
    }

    guard let fileObj = matched.first else {
      let available = fileObjects.compactMap { $0["name"] as? String }.prefix(10)
      throw CoverageError(
        "'\(file)' not found in coverage. Available: \(available.joined(separator: ", "))")
    }

    let fileName = (fileObj["name"] as? String) ?? file
    let fileCov = (fileObj["lineCoverage"] as? Double) ?? 0
    let covered = (fileObj["coveredLines"] as? Int) ?? 0
    let executable = (fileObj["executableLines"] as? Int) ?? 0

    var functions: [FunctionCoverage] = []
    if let jsonFunctions = fileObj["functions"] as? [[String: Any]] {
      functions =
        jsonFunctions
        .sorted { ($0["lineNumber"] as? Int ?? 0) < ($1["lineNumber"] as? Int ?? 0) }
        .map { fn in
          FunctionCoverage(
            name: (fn["name"] as? String) ?? "?",
            lineNumber: (fn["lineNumber"] as? Int) ?? 0,
            lineCoverage: (fn["lineCoverage"] as? Double) ?? 0,
            executionCount: (fn["executionCount"] as? Int) ?? 0,
            executableLines: (fn["executableLines"] as? Int) ?? 0
          )
        }
    }

    return FileCoverageDetail(
      fileName: fileName,
      lineCoverage: fileCov,
      coveredLines: covered,
      executableLines: executable,
      functions: functions,
      xcresultPath: xcresultPath
    )
  }

  // MARK: - build_and_test Execution

  public static func executeBuildAndTest(
    project: String? = nil,
    scheme: String? = nil,
    simulator: String? = nil,
    configuration: String = "Debug",
    testplan: String? = nil,
    filter: String? = nil,
    coverage: Bool = false,
    env: Environment = .live
  ) async throws -> BuildAndTestResult {
    let resolvedProject = try await env.session.resolveProject(project)
    let resolvedScheme = try await env.session.resolveScheme(scheme, project: resolvedProject)
    let resolvedSimulator = try await env.session.resolveSimulator(simulator)

    // Phase 1: Build with diagnostics
    let buildExecution = try await executeBuildDiagnosis(
      project: resolvedProject,
      scheme: resolvedScheme,
      simulator: resolvedSimulator,
      configuration: configuration,
      env: env
    )

    if !buildExecution.succeeded {
      return BuildAndTestResult(
        phase: "build",
        buildSucceeded: false,
        buildElapsed: buildExecution.elapsed,
        buildDiagnostics: buildExecution.issues,
        testResult: nil
      )
    }

    // Phase 2: Run tests
    let resolvedFilter: String?
    if let filter {
      resolvedFilter = await resolveFilter(filter, project: resolvedProject, env: env)
    } else {
      resolvedFilter = nil
    }

    do {
      let testExecution = try await executeTest(
        project: resolvedProject,
        scheme: resolvedScheme,
        simulator: resolvedSimulator,
        configuration: configuration,
        testplan: testplan,
        filter: resolvedFilter,
        coverage: coverage,
        env: env
      )

      return BuildAndTestResult(
        phase: "test",
        buildSucceeded: true,
        buildElapsed: buildExecution.elapsed,
        buildDiagnostics: nil,
        testResult: testExecution
      )
    } catch {
      // Test infrastructure failure (simulator crash, timeout, xcresult parse error).
      // Preserve the build success signal rather than losing it in a thrown error.
      return BuildAndTestResult(
        phase: "test",
        buildSucceeded: true,
        buildElapsed: buildExecution.elapsed,
        buildDiagnostics: nil,
        testResult: TestExecution(
          succeeded: false,
          elapsed: "0.0",
          xcresultPath: "",
          scheme: resolvedScheme,
          simulator: resolvedSimulator,
          totalTestCount: 0,
          passedTestCount: 0,
          failedTestCount: 0,
          skippedTestCount: 0,
          expectedFailureCount: 0,
          failures: [
            TestFailureObservation(
              testName: "test_infrastructure",
              testIdentifier: "test_infrastructure",
              message: "Test execution failed: \(error)",
              source: "xcforge"
            )
          ],
          deviceName: nil,
          osVersion: nil,
          screenshotPaths: [],
          hasStructuredSummary: false,
          buildFailed: false,
          buildDiagnostics: nil
        )
      )
    }
  }

  // MARK: - list_tests Execution

  public static func executeListTests(
    project: String? = nil,
    scheme: String? = nil,
    simulator: String? = nil,
    env: Environment = .live
  ) async throws -> ListTestsResult {
    let resolvedProject = try await env.session.resolveProject(project)
    let resolvedScheme = try await env.session.resolveScheme(scheme, project: resolvedProject)
    let resolvedSimulator = try await env.session.resolveSimulator(simulator)
    let destination = await AutoDetect.buildDestination(resolvedSimulator)

    let isWorkspace = resolvedProject.hasSuffix(".xcworkspace")
    let projectFlag = isWorkspace ? "-workspace" : "-project"

    // Verify Xcode 16+ is available (required for -enumerate-tests)
    let xcodeVersionResult = try await env.shell.run(
      "/usr/bin/xcodebuild", arguments: ["-version"], timeout: 10
    )
    if let versionLine = xcodeVersionResult.stdout.split(separator: "\n").first,
      let versionString = versionLine.split(separator: " ").last,
      let majorVersion = Int(versionString.split(separator: ".").first ?? "")
    {
      guard majorVersion >= 16 else {
        throw TestDiscoveryError(
          "-enumerate-tests requires Xcode 16 or later (found Xcode \(majorVersion))")
      }
    } else {
      Log.warn("Could not parse Xcode version from: \(xcodeVersionResult.stdout.prefix(100))")
    }

    // xcodebuild test -enumerate-tests builds for testing then lists tests without running them
    let enumerateResult = try await env.shell.run(
      "/usr/bin/xcodebuild",
      arguments: [
        projectFlag, resolvedProject,
        "-scheme", resolvedScheme,
        "-destination", destination,
        "-skipMacroValidation",
        "-enumerate-tests",
        "test",
      ], timeout: 1800
    )

    guard enumerateResult.succeeded || !enumerateResult.stdout.isEmpty else {
      let errorLines = enumerateResult.stderr.split(separator: "\n")
        .filter { $0.contains(": error:") || $0.contains("FAILED") }
        .prefix(10)
        .map(String.init)
      let detail =
        errorLines.isEmpty
        ? String(enumerateResult.stderr.suffix(1000)) : errorLines.joined(separator: "\n")
      throw TestDiscoveryError("enumerate-tests failed:\n\(detail)")
    }

    var tests: [TestIdentifier] = []
    var targets = Set<String>()
    var classes = Set<String>()

    // Parse the enumerate-tests output.
    // xcodebuild format (indented): "Target X" / "\tClass Y" / "\t\tTest z()"
    // swift test list format: "Target.Class/method()"
    //
    // IMPORTANT: xcodebuild stdout includes build log before the test listing.
    // We must skip the build phase to avoid matching noise (SPM URLs, command fragments).
    let lines = enumerateResult.stdout.split(separator: "\n").map(String.init)

    // Find the start of the test listing section.
    // xcodebuild emits "Listing tests:" or the first "Target " line after build output.
    // We skip everything before "** BUILD SUCCEEDED **" or "Listing tests" if present.
    var startIndex = 0
    for (i, line) in lines.enumerated() {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.contains("** BUILD SUCCEEDED **") || trimmed.hasPrefix("Listing tests") {
        startIndex = i + 1
      }
    }

    // Known test targets — used to validate the swift test list format parser
    let knownTestTargets =
      (try? await AutoDetect.testTargets(project: resolvedProject, env: env)) ?? []
    let knownTargetSet = Set(knownTestTargets)

    var currentTarget = ""
    var currentClass = ""

    for line in lines[startIndex...] {
      let trimmed = line.trimmingCharacters(in: .whitespaces)

      // xcodebuild indented format
      if trimmed.hasPrefix("Target ") {
        currentTarget = String(trimmed.dropFirst("Target ".count))
        continue
      }
      if trimmed.hasPrefix("Class ") {
        currentClass = String(trimmed.dropFirst("Class ".count))
        continue
      }
      if trimmed.hasPrefix("Test "), !currentTarget.isEmpty, !currentClass.isEmpty {
        var methodName = String(trimmed.dropFirst("Test ".count))
        if methodName.hasSuffix("()") {
          methodName = String(methodName.dropLast(2))
        }
        let fullId = "\(currentTarget)/\(currentClass)/\(methodName)"
        tests.append(
          TestIdentifier(
            target: currentTarget, className: currentClass,
            methodName: methodName, fullIdentifier: fullId
          ))
        targets.insert(currentTarget)
        classes.insert("\(currentTarget)/\(currentClass)")
        continue
      }

      // swift test list format: "Target.Class/method()"
      // Guard against URLs, xcodebuild commands, and other noise lines:
      // - Must not contain spaces (test identifiers are single tokens)
      // - Must not contain "://" (URLs)
      // - Must not start with "-" (flags) or "/" (absolute paths)
      // - Must not contain "=" (build settings), ":" (log lines), or "#" (comments)
      // - Target part (before ".") must be a known test target OR valid Swift identifier
      guard
        trimmed.contains(".") && trimmed.contains("/")
          && !trimmed.contains(" ") && !trimmed.contains("://")
          && !trimmed.hasPrefix("-") && !trimmed.hasPrefix("/")
          && !trimmed.contains("=") && !trimmed.contains(":")
          && !trimmed.contains("#")
      else { continue }

      let dotParts = trimmed.split(separator: ".", maxSplits: 1).map(String.init)
      guard dotParts.count == 2 else { continue }
      let target = dotParts[0]
      // Target must look like a Swift identifier (alphanumeric + underscore)
      guard target.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { continue }
      // If we know the test targets, reject unknown ones to filter noise
      if !knownTargetSet.isEmpty && !knownTargetSet.contains(target) { continue }
      let rest = dotParts[1].split(separator: "/", maxSplits: 1).map(String.init)
      guard rest.count == 2 else { continue }
      let className = rest[0]
      // Class must also look like a Swift identifier
      guard className.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { continue }
      var methodName = rest[1]
      if methodName.hasSuffix("()") {
        methodName = String(methodName.dropLast(2))
      }
      // Method must not contain "/" (would indicate URL path segments)
      guard !methodName.contains("/") else { continue }
      // Method must also look like a Swift identifier
      guard methodName.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { continue }
      let fullId = "\(target)/\(className)/\(methodName)"
      tests.append(
        TestIdentifier(
          target: target, className: className,
          methodName: methodName, fullIdentifier: fullId
        ))
      targets.insert(target)
      classes.insert("\(target)/\(className)")
    }

    // Fallback: if -enumerate-tests didn't produce parseable output,
    // try discovering from test target names + source files
    if tests.isEmpty {
      let testTargets = try await AutoDetect.testTargets(project: resolvedProject, env: env)
      if !testTargets.isEmpty {
        throw TestDiscoveryError(
          "No XCTest methods found, but found test targets: \(testTargets.joined(separator: ", ")). "
            + "Note: -enumerate-tests only discovers XCTest methods. Swift Testing @Test suites are not "
            + "discoverable this way — use test_sim with a testplan to run them. "
            + "Use these as filter prefixes, e.g. filter: \"\(testTargets[0])/YourTestClass/testMethodName\""
        )
      }
      throw TestDiscoveryError(
        "No tests found for scheme '\(resolvedScheme)'. "
          + "Note: Swift Testing @Test suites are not discoverable by -enumerate-tests. "
          + "Use test_sim with a testplan to run Swift Testing suites."
      )
    }

    return ListTestsResult(
      tests: tests,
      targetCount: targets.count,
      classCount: classes.count,
      testCount: tests.count
    )
  }

  // MARK: - Tool Implementations

  static func testSim(_ args: [String: Value]?, env: Environment) async -> CallTool.Result {
    switch ToolInput.decode(TestSimInput.self, from: args) {
    case .failure(let err): return err
    case .success(let input):
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
      let testplan = input.testplan
      let filter: String?
      if let rawFilter = input.filter {
        filter = await resolveFilter(rawFilter, project: project, env: env)
      } else {
        filter = nil
      }
      let coverage = input.coverage ?? false
      let resultPath = xcresultPath(prefix: "test")
      let destination = await AutoDetect.buildDestination(simulator)

      // Build preamble: testplan visibility + filter/testplan conflict warning
      var preamble = ""
      if let tp = testplan {
        preamble += "Testplan: \(tp)\n"
      } else {
        preamble += "Testplan: (none — all tests)\n"
      }
      if testplan != nil && input.filter != nil {
        preamble +=
          "Note: filter and testplan are both set. -only-testing overrides the testplan's test selection. Tests not matching the filter will be skipped regardless of testplan.\n"
      }

      let start = CFAbsoluteTimeGetCurrent()
      do {
        let (buildResult, path) = try await runTests(
          project: project, scheme: scheme, destination: destination,
          configuration: configuration, testplan: testplan,
          filter: filter, coverage: coverage, resultPath: resultPath,
          env: env
        )
        let elapsed = String(format: "%.1f", CFAbsoluteTimeGetCurrent() - start)

        // Parse xcresult summary
        if let summaryJSON = await parseTestSummary(path, env: env),
          let data = summaryJSON.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
          // Check for test-target build failure: xcodebuild failed but xcresult has a summary
          let totalTests = json["totalTestCount"] as? Int ?? 0
          if !buildResult.succeeded && totalTests == 0 {
            // Build failed with zero tests — surface build diagnostics
            var buildDiagOutput = ""
            if let buildJSON = await parseBuildResults(path, env: env),
              let bData = buildJSON.data(using: .utf8),
              let bJson = try? JSONSerialization.jsonObject(with: bData) as? [String: Any]
            {
              let parsed = parseBuildIssues(bJson)
              let errors = parsed.issues.filter { $0.severity == .error }
              if !errors.isEmpty {
                buildDiagOutput =
                  "\nBuild errors (\(errors.count)):\n"
                  + errors.map { issue in
                    if let loc = issue.location {
                      return "  \(loc.filePath):\(loc.line ?? 0): \(issue.message)"
                    }
                    return "  \(issue.message)"
                  }.joined(separator: "\n")
              }
            }
            if buildDiagOutput.isEmpty {
              let errorLines = buildResult.stderr.split(separator: "\n")
                .filter {
                  $0.contains(": error:") || $0.contains(" failed") || $0.contains("FAILED")
                }
                .prefix(20)
              if !errorLines.isEmpty {
                buildDiagOutput = "\n" + errorLines.joined(separator: "\n")
              }
            }
            return .fail(
              preamble + "TEST TARGET BUILD FAILED in \(elapsed)s"
                + buildDiagOutput + "\nxcresult: \(path)")
          }

          var summary = preamble + formatTestSummary(json, elapsed: elapsed, xcresultPath: path)

          // If tests failed, export failure screenshots
          let result = (json["result"] as? String) ?? ""
          if result == "Failed" {
            let attachments = await exportFailureAttachments(path, env: env)
            if !attachments.isEmpty {
              summary += "\n\nFailure screenshots (\(attachments.count)):"
              for att in attachments {
                summary += "\n  \(att.path)"
              }
            }
          }

          // Zero-match diagnostic: if filter was set and 0 tests ran
          if totalTests == 0, let f = input.filter {
            summary += await zeroMatchHint(
              filter: f, project: input.project, scheme: input.scheme,
              simulator: input.simulator, testplan: testplan, env: env
            )
          }

          let hasFailures = (json["failedTests"] as? Int ?? 0) > 0
          // Filter matched nothing → treat as failure so agents don't assume tests passed
          let zeroMatchWithFilter = totalTests == 0 && input.filter != nil
          return (hasFailures || zeroMatchWithFilter) ? .fail(summary) : .ok(summary)
        }

        // Fallback: no xcresult test summary parseable
        if buildResult.succeeded {
          var msg =
            preamble + "Tests passed in \(elapsed)s (xcresult parse failed)\nxcresult: \(path)"
          if let f = input.filter {
            msg += await zeroMatchHint(
              filter: f, project: input.project, scheme: input.scheme,
              simulator: input.simulator, testplan: testplan, env: env
            )
          }
          return .ok(msg)
        } else {
          // Build failed — try structured build diagnostics first
          var diagnosticOutput = ""
          if let buildJSON = await parseBuildResults(path, env: env),
            let data = buildJSON.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
          {
            let parsed = parseBuildIssues(json)
            let errors = parsed.issues.filter { $0.severity == .error }
            if !errors.isEmpty {
              diagnosticOutput =
                "Build errors (\(errors.count)):\n"
                + errors.map { issue in
                  if let loc = issue.location {
                    return "  \(loc.filePath):\(loc.line ?? 0): \(issue.message)"
                  }
                  return "  \(issue.message)"
                }.joined(separator: "\n")
            }
          }
          if diagnosticOutput.isEmpty {
            let errorLines = buildResult.stderr.split(separator: "\n")
              .filter {
                $0.contains(": error:") || $0.contains(" failed") || $0.contains("FAILED")
              }
              .prefix(20)
              .joined(separator: "\n")
            diagnosticOutput = errorLines
          }
          return .fail(
            preamble
              + "TEST TARGET BUILD FAILED in \(elapsed)s\n\(diagnosticOutput)\nxcresult: \(path)")
        }
      } catch {
        return .fail("Test error: \(error)")
      }
    }
  }

  static func testFailures(_ args: [String: Value]?, env: Environment) async -> CallTool.Result {
    switch ToolInput.decode(TestFailuresInput.self, from: args) {
    case .failure(let err): return err
    case .success(let input):
      let xcresultPath: String

      if let provided = input.xcresult_path {
        xcresultPath = provided
      } else {
        do {
          let project = try await env.session.resolveProject(input.project)
          let scheme = try await env.session.resolveScheme(input.scheme, project: project)
          let simulator = try await env.session.resolveSimulator(input.simulator)
          let destination = await AutoDetect.buildDestination(simulator)
          let path = Self.xcresultPath(prefix: "fail")
          let (_, p) = try await runTests(
            project: project, scheme: scheme, destination: destination,
            configuration: "Debug", testplan: nil, filter: nil,
            coverage: false, resultPath: path,
            env: env
          )
          xcresultPath = p
        } catch {
          return .fail("\(error)")
        }
      }

      let includeConsole = input.include_console ?? false

      // Parse test details and extract failures
      guard let detailsJSON = await parseTestDetails(xcresultPath, env: env),
        let data = detailsJSON.data(using: .utf8)
      else {
        return .fail("Failed to parse xcresult at \(xcresultPath)")
      }

      // Export failure screenshots if available
      let attachments = await exportFailureAttachments(xcresultPath, env: env)

      // Extract console output per failed test if requested
      let consoleByTest =
        includeConsole ? await extractFailedTestConsole(xcresultPath, env: env) : [:]

      return formatTestFailures(
        data, xcresultPath: xcresultPath, attachments: attachments, consoleByTest: consoleByTest)
    }
  }

  static func testCoverage(_ args: [String: Value]?, env: Environment) async -> CallTool.Result {
    switch ToolInput.decode(TestCoverageInput.self, from: args) {
    case .failure(let err): return err
    case .success(let input):
      let xcresultPath: String

      if let provided = input.xcresult_path {
        xcresultPath = provided
      } else if let recent = await findRecentCoverageXcresult(env: env) {
        // Reuse a recent xcresult that already has coverage data
        xcresultPath = recent
      } else {
        // No coverage data available — fail fast instead of silently running the entire test suite
        return .fail(
          "No coverage data available. Run tests with coverage enabled first:\n"
            + "  test_sim(coverage: true)  — or —  xcforge test run --coverage\n"
            + "Then call test_coverage again to view the report."
        )
      }

      // File drill-down: per-function coverage for a specific file
      if let file = input.file {
        return await fileCoverage(file: file, xcresultPath: xcresultPath, env: env)
      }

      let minCoverage = input.min_coverage ?? 100.0

      guard let coverageJSON = await parseCoverage(xcresultPath, env: env),
        let data = coverageJSON.data(using: .utf8),
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
      else {
        return .fail(
          "Failed to parse coverage from \(xcresultPath). Was coverage enabled during the test run?"
        )
      }

      return formatCoverageReport(json, minCoverage: minCoverage, xcresultPath: xcresultPath)
    }
  }

  /// Per-function coverage for a specific file via `xccov --functions-for-file`.
  private static func fileCoverage(file: String, xcresultPath: String, env: Environment) async
    -> CallTool.Result
  {
    // xccov accepts partial filenames — it fuzzy-matches against the coverage archive
    let result: ShellResult
    do {
      result = try await env.shell.run(
        "/usr/bin/xcrun",
        arguments: [
          "xccov", "view", "--report", "--functions-for-file", file, "--json", xcresultPath,
        ],
        timeout: 30
      )
    } catch {
      return .fail("xccov error: \(error)")
    }
    guard result.succeeded, !result.stdout.isEmpty else {
      return .fail(
        "No coverage data for '\(file)'. File not in coverage report or coverage not enabled.\n\(result.stderr)"
      )
    }

    // Parse JSON — can be an array of file objects or a single object
    guard let data = result.stdout.data(using: .utf8),
      let raw = try? JSONSerialization.jsonObject(with: data)
    else {
      return .fail("Failed to parse xccov JSON for '\(file)'")
    }

    // Normalize: xccov returns either [FileObj] or {targets: [{files: [FileObj]}]}
    var fileObjects: [[String: Any]] = []
    if let array = raw as? [[String: Any]] {
      fileObjects = array
    } else if let dict = raw as? [String: Any],
      let targets = dict["targets"] as? [[String: Any]]
    {
      for target in targets {
        if let files = target["files"] as? [[String: Any]] {
          fileObjects += files
        }
      }
    }

    // Find matching file (fuzzy: filename contains the search term)
    let searchName = (file as NSString).lastPathComponent.lowercased()
    let matched = fileObjects.filter {
      let name = (($0["name"] as? String) ?? ($0["path"] as? String) ?? "").lowercased()
      return name.contains(searchName) || searchName.contains(name)
    }

    guard let fileObj = matched.first else {
      let available = fileObjects.compactMap { $0["name"] as? String }.prefix(10)
      return .fail(
        "'\(file)' not found in coverage. Available: \(available.joined(separator: ", "))")
    }

    // Format output
    let fileName = (fileObj["name"] as? String) ?? file
    let fileCov = (fileObj["lineCoverage"] as? Double) ?? 0
    let covered = (fileObj["coveredLines"] as? Int) ?? 0
    let executable = (fileObj["executableLines"] as? Int) ?? 0

    var lines: [String] = []
    lines.append(
      String(format: "%@ — %.1f%% (%d/%d lines)", fileName, fileCov * 100, covered, executable))

    if let functions = fileObj["functions"] as? [[String: Any]] {
      // Sort by line number
      let sorted = functions.sorted {
        ($0["lineNumber"] as? Int ?? 0) < ($1["lineNumber"] as? Int ?? 0)
      }

      var untested: [String] = []
      lines.append("")
      for fn in sorted {
        let name = (fn["name"] as? String) ?? "?"
        let lineNum = (fn["lineNumber"] as? Int) ?? 0
        let cov = (fn["lineCoverage"] as? Double) ?? 0
        let execCount = (fn["executionCount"] as? Int) ?? 0
        let fnLines = (fn["executableLines"] as? Int) ?? 0

        if execCount == 0 {
          lines.append(
            String(format: "  L%-4d %-40s   0%%  UNTESTED  (%d lines)", lineNum, name, fnLines))
          untested.append("\(name) (L\(lineNum), \(fnLines) lines)")
        } else {
          lines.append(
            String(
              format: "  L%-4d %-40s %3.0f%%  (%dx called)", lineNum, name, cov * 100, execCount))
        }
      }

      if !untested.isEmpty {
        lines.append("")
        lines.append("Untested functions (\(untested.count)): \(untested.joined(separator: ", "))")
      }
    }

    lines.append("\nxcresult: \(xcresultPath)")
    return .ok(lines.joined(separator: "\n"))
  }

  static func buildAndDiagnose(_ args: [String: Value]?, env: Environment) async -> CallTool.Result {
    switch ToolInput.decode(BuildAndDiagnoseInput.self, from: args) {
    case .failure(let err): return err
    case .success(let input):
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
      do {
        let execution = try await executeBuildDiagnosis(
          project: project,
          scheme: scheme,
          simulator: simulator,
          configuration: configuration,
          env: env
        )
        return formatBuildDiagnosis(execution)
      } catch {
        return .fail("Build error: \(error)")
      }
    }
  }

  static func buildAndTest(_ args: [String: Value]?, env: Environment) async -> CallTool.Result {
    switch ToolInput.decode(BuildAndTestInput.self, from: args) {
    case .failure(let err): return err
    case .success(let input):
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
      do {
        let result = try await executeBuildAndTest(
          project: project,
          scheme: scheme,
          simulator: simulator,
          configuration: configuration,
          testplan: input.testplan,
          filter: input.filter,
          coverage: input.coverage ?? false,
          env: env
        )
        // Generate zero-match hint before formatting (avoids Content extraction)
        var zeroHint = ""
        if let testResult = result.testResult,
          testResult.totalTestCount == 0,
          let f = input.filter
        {
          zeroHint = await zeroMatchHint(
            filter: f, project: input.project, scheme: input.scheme,
            simulator: input.simulator, testplan: input.testplan, env: env
          )
        }

        return formatBuildAndTest(
          result, testplan: input.testplan, filter: input.filter, suffix: zeroHint)
      } catch {
        return .fail("build_and_test error: \(error)")
      }
    }
  }

  static func listTests(_ args: [String: Value]?, env: Environment) async -> CallTool.Result {
    switch ToolInput.decode(ListTestsInput.self, from: args) {
    case .failure(let err): return err
    case .success(let input):
      do {
        let result = try await executeListTests(
          project: input.project,
          scheme: input.scheme,
          simulator: input.simulator,
          env: env
        )
        return formatListTests(result, filter: input.filter)
      } catch {
        return .fail("list_tests error: \(error)")
      }
    }
  }

  static func formatBuildAndTest(
    _ result: BuildAndTestResult,
    testplan: String? = nil,
    filter: String? = nil,
    suffix: String = ""
  ) -> CallTool.Result {
    var lines: [String] = []

    // Testplan + filter/testplan warning preamble (only when tests were actually run)
    if result.buildSucceeded && result.testResult != nil {
      if let tp = testplan {
        lines.append("Testplan: \(tp)")
      } else {
        lines.append("Testplan: (none — all tests)")
      }
      if testplan != nil && filter != nil {
        lines.append(
          "Note: filter and testplan are both set. -only-testing overrides the testplan's test selection."
        )
      }
    }

    if !result.buildSucceeded {
      lines.append("BUILD FAILED in \(result.buildElapsed)s")
      lines.append("Phase: build (tests were NOT run)")
      lines.append("")
      if let diagnostics = result.buildDiagnostics, !diagnostics.isEmpty {
        let errors = diagnostics.filter { $0.severity == .error }
        let warnings = diagnostics.filter { $0.severity == .warning }
        if !errors.isEmpty {
          lines.append("Errors (\(errors.count)):")
          for issue in errors {
            if let loc = issue.location {
              lines.append("  \(loc.filePath):\(loc.line ?? 0): \(issue.message)")
            } else {
              lines.append("  \(issue.message)")
            }
          }
        }
        if !warnings.isEmpty {
          lines.append("Warnings (\(warnings.count)):")
          for issue in warnings.prefix(5) {
            if let loc = issue.location {
              lines.append("  \(loc.filePath):\(loc.line ?? 0): \(issue.message)")
            } else {
              lines.append("  \(issue.message)")
            }
          }
        }
      }
      return .fail(lines.joined(separator: "\n") + suffix)
    }

    // Build succeeded, show test results
    if let test = result.testResult {
      if test.buildFailed {
        lines.append("Build: OK (\(result.buildElapsed)s)")
        lines.append("TEST TARGET BUILD FAILED in \(test.elapsed)s")
        lines.append("Phase: test target compilation (tests were NOT run)")
        if let diagnostics = test.buildDiagnostics, !diagnostics.isEmpty {
          lines.append("")
          let errors = diagnostics.filter { $0.severity == .error }
          let warnings = diagnostics.filter { $0.severity == .warning }
          if !errors.isEmpty {
            lines.append("Errors (\(errors.count)):")
            for issue in errors {
              if let loc = issue.location {
                lines.append("  \(loc.filePath):\(loc.line ?? 0): \(issue.message)")
              } else {
                lines.append("  \(issue.message)")
              }
            }
          }
          if !warnings.isEmpty {
            lines.append("Warnings (\(warnings.count)):")
            for issue in warnings.prefix(5) {
              if let loc = issue.location {
                lines.append("  \(loc.filePath):\(loc.line ?? 0): \(issue.message)")
              } else {
                lines.append("  \(issue.message)")
              }
            }
          }
        }
        if test.buildDiagnostics == nil && !test.failures.isEmpty {
          lines.append("")
          lines.append("Build errors (stderr):")
          for failure in test.failures {
            lines.append("  \(failure.message)")
          }
        }
        lines.append("")
        lines.append("xcresult: \(test.xcresultPath)")
        return .fail(lines.joined(separator: "\n") + suffix)
      }
      lines.append("Build: OK (\(result.buildElapsed)s)")
      if test.totalTestCount == 0 {
        lines.append("No tests matched in \(test.elapsed)s")
      } else {
        let icon = test.succeeded ? "PASSED" : "FAILED"
        lines.append("Tests \(icon) in \(test.elapsed)s")
      }
      lines.append(
        "  Total: \(test.totalTestCount)  Passed: \(test.passedTestCount)  Failed: \(test.failedTestCount)  Skipped: \(test.skippedTestCount)"
      )
      if !test.failures.isEmpty {
        lines.append("")
        lines.append("Failures:")
        for failure in test.failures {
          lines.append("  \(failure.testName): \(failure.message)")
          if !failure.source.isEmpty && failure.source != "stderr" {
            lines.append("    at \(failure.source)")
          }
        }
      }
      lines.append("")
      lines.append("xcresult: \(test.xcresultPath)")
      let text = lines.joined(separator: "\n") + suffix
      // Filter matched nothing → treat as failure so agents don't assume tests passed
      let zeroMatchWithFilter = test.totalTestCount == 0 && filter != nil
      return (test.succeeded && !zeroMatchWithFilter) ? .ok(text) : .fail(text)
    }

    return .ok(
      "Build succeeded in \(result.buildElapsed)s, but test result is unavailable." + suffix)
  }

  static func formatListTests(_ result: ListTestsResult, filter: String? = nil) -> CallTool.Result {
    let tests: [TestIdentifier]
    let filterNote: String?

    let trimmedFilter = filter?.trimmingCharacters(in: .whitespacesAndNewlines)
    if let trimmedFilter, !trimmedFilter.isEmpty {
      let lowered = trimmedFilter.lowercased()
      tests = result.tests.filter { $0.fullIdentifier.lowercased().contains(lowered) }
      if tests.isEmpty {
        // Find close matches at class level for suggestions
        let classNames = Set(result.tests.map { $0.className })
        let suggestions = classNames.filter { $0.lowercased().contains(lowered) }
          .sorted().prefix(5)
        var msg =
          "0 tests matched filter \"\(trimmedFilter)\" (out of \(result.testCount) total tests)"
        if !suggestions.isEmpty {
          msg += "\nDid you mean: \(suggestions.joined(separator: ", "))?"
        } else {
          msg +=
            "\nNo similar class names found. Use list_tests without a filter to see all available identifiers."
        }
        return .fail(msg)
      }
      filterNote =
        "Showing \(tests.count) of \(result.testCount) tests matching \"\(trimmedFilter)\""
    } else {
      tests = result.tests
      filterNote = nil
    }

    var lines: [String] = []
    if let note = filterNote {
      lines.append(note)
    } else {
      lines.append(
        "Found \(result.testCount) tests in \(result.targetCount) target(s), \(result.classCount) class(es)"
      )
    }
    lines.append("")

    // Group by target/class for readability
    var grouped: [String: [String: [String]]] = [:]  // target -> class -> methods
    for test in tests {
      grouped[test.target, default: [:]][test.className, default: []].append(test.methodName)
    }

    for (target, classes) in grouped.sorted(by: { $0.key < $1.key }) {
      lines.append("\(target)/")
      for (className, methods) in classes.sorted(by: { $0.key < $1.key }) {
        lines.append("  \(className)/")
        for method in methods.sorted() {
          lines.append("    \(method)")
        }
      }
    }

    lines.append("")
    lines.append("Use these identifiers with the filter parameter:")
    lines.append("  Full:   filter: \"Target/Class/method\"")
    lines.append("  Class:  filter: \"Class\" (auto-resolves target — XCTest only)")
    lines.append("  Method: filter: \"method\" (auto-resolves target — XCTest only)")
    lines.append("")
    lines.append(
      "Note: Swift Testing @Test suites require the full Target/Suite path and a testplan.")

    return .ok(lines.joined(separator: "\n"))
  }

  // MARK: - Formatting helpers

  private static func formatTestSummary(
    _ json: [String: Any], elapsed: String, xcresultPath: String
  ) -> String {
    var lines: [String] = []

    // Overall result
    let totalTests = json["totalTestCount"] as? Int ?? 0
    let result = (json["result"] as? String) ?? "unknown"
    if totalTests == 0 {
      lines.append("No tests matched in \(elapsed)s")
    } else {
      let icon = result == "Passed" ? "PASSED" : "FAILED"
      lines.append("Tests \(icon) in \(elapsed)s")
    }

    // Statistics — top-level keys in xcresulttool output
    var statParts: [String] = []
    if let total = json["totalTestCount"] as? Int { statParts.append("\(total) total") }
    if let passed = json["passedTests"] as? Int, passed > 0 { statParts.append("\(passed) passed") }
    if let failed = json["failedTests"] as? Int, failed > 0 { statParts.append("\(failed) FAILED") }
    if let skipped = json["skippedTests"] as? Int, skipped > 0 {
      statParts.append("\(skipped) skipped")
    }
    if let expected = json["expectedFailures"] as? Int, expected > 0 {
      statParts.append("\(expected) expected-failure")
    }
    if !statParts.isEmpty {
      lines.append(statParts.joined(separator: ", "))
    }

    // Inline failure summaries
    if let failures = json["testFailures"] as? [[String: Any]] {
      for failure in failures.prefix(20) {
        let testName =
          (failure["testName"] as? String) ?? (failure["testIdentifierString"] as? String) ?? "?"
        let message = (failure["failureText"] as? String) ?? ""
        lines.append("FAIL: \(testName)")
        if !message.isEmpty { lines.append("  \(message)") }
      }
    }

    // Devices
    if let devices = json["devicesAndConfigurations"] as? [[String: Any]] {
      for device in devices {
        if let d = device["device"] as? [String: Any],
          let name = d["deviceName"] as? String,
          let os = d["osVersion"] as? String
        {
          lines.append("Device: \(name) (\(os))")
        }
      }
    }

    // Environment
    if let env = json["environmentDescription"] as? String {
      lines.append("Env: \(env)")
    }

    lines.append("xcresult: \(xcresultPath)")
    return lines.joined(separator: "\n")
  }

  private static func formatTestFailures(
    _ data: Data, xcresultPath: String,
    attachments: [(test: String, path: String)] = [],
    consoleByTest: [String: String] = [:]
  ) -> CallTool.Result {
    guard let observedFailures = parseTestFailures(data) else {
      return .fail("Failed to parse test details JSON")
    }

    if observedFailures.isEmpty {
      return .ok("No test failures found.\nxcresult: \(xcresultPath)")
    }

    let failures = observedFailures.map { failure -> String in
      var failLine = "FAIL: \(failure.testName) [\(failure.testIdentifier)]"
      if !failure.message.isEmpty {
        failLine += "\n  " + failure.message.replacingOccurrences(of: "\n", with: "\n  ")
      }

      let matchingScreenshots = attachments.filter {
        $0.test.contains(failure.testIdentifier) || failure.testIdentifier.contains($0.test)
      }
      for screenshot in matchingScreenshots {
        failLine += "\n  Screenshot: \(screenshot.path)"
      }

      let funcName =
        failure.testIdentifier.split(separator: "/").last.map(String.init) ?? failure.testIdentifier
      if let console = consoleByTest[funcName] ?? consoleByTest[failure.testIdentifier] {
        failLine += "\n  Console:\n    " + console.replacingOccurrences(of: "\n", with: "\n    ")
      }

      return failLine
    }

    var output = "\(failures.count) test failure(s):\n\n" + failures.joined(separator: "\n\n")

    // List all screenshots at the end for easy access
    if !attachments.isEmpty {
      output += "\n\nFailure screenshots (\(attachments.count)):"
      for att in attachments {
        output += "\n  \(att.path)"
      }
    }

    output += "\n\nxcresult: \(xcresultPath)"
    let truncated =
      output.count > 50000 ? String(output.prefix(50000)) + "\n... [truncated]" : output
    return .fail(truncated)
  }

  private static func parseTestSummary(_ json: [String: Any]) -> ParsedTestSummary {
    let failures = ((json["testFailures"] as? [[String: Any]]) ?? []).map { failure in
      TestFailureObservation(
        testName: (failure["testName"] as? String) ?? "?",
        testIdentifier: (failure["testIdentifierString"] as? String)
          ?? (failure["testName"] as? String) ?? "?",
        message: (failure["failureText"] as? String)
          ?? "Test failed without a captured failure message.",
        source: "xcresult.test-summary"
      )
    }

    let devices = json["devicesAndConfigurations"] as? [[String: Any]]
    let device = devices?.first?["device"] as? [String: Any]

    return ParsedTestSummary(
      result: (json["result"] as? String) ?? "unknown",
      totalTestCount: (json["totalTestCount"] as? Int) ?? 0,
      failedTestCount: (json["failedTests"] as? Int) ?? failures.count,
      passedTestCount: (json["passedTests"] as? Int) ?? 0,
      skippedTestCount: (json["skippedTests"] as? Int) ?? 0,
      expectedFailureCount: (json["expectedFailures"] as? Int) ?? 0,
      destinationDeviceName: device?["deviceName"] as? String,
      destinationOSVersion: device?["osVersion"] as? String,
      failures: failures
    )
  }

  private static func parseTestFailures(_ data: Data) -> [TestFailureObservation]? {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return nil
    }
    return parseTestFailures(json)
  }

  private static func parseTestFailures(_ json: [String: Any]) -> [TestFailureObservation] {
    var failures: [TestFailureObservation] = []

    func collectFailure(from node: [String: Any]) {
      let nodeType = (node["nodeType"] as? String) ?? ""
      let result = (node["result"] as? String) ?? ""
      let name = (node["name"] as? String) ?? "?"
      let identifier = (node["nodeIdentifier"] as? String) ?? name

      if nodeType == "Test Case" && result == "Failed" {
        var messages: [String] = []
        if let children = node["children"] as? [[String: Any]] {
          for child in children where (child["nodeType"] as? String) == "Failure Message" {
            let message = (child["name"] as? String) ?? ""
            if !message.isEmpty {
              messages.append(message)
            }
          }
        }

        failures.append(
          TestFailureObservation(
            testName: name,
            testIdentifier: identifier,
            message: messages.isEmpty
              ? "Test failed without a captured failure message."
              : messages.joined(separator: "\n"),
            source: "xcresult.test-details"
          )
        )
        return
      }

      if let children = node["children"] as? [[String: Any]] {
        for child in children {
          collectFailure(from: child)
        }
      }
    }

    if let testNodes = json["testNodes"] as? [[String: Any]] {
      for node in testNodes {
        collectFailure(from: node)
      }
    }

    return failures
  }

  private static func formatCoverageReport(
    _ json: [String: Any], minCoverage: Double, xcresultPath: String
  ) -> CallTool.Result {
    var lines: [String] = []

    // Overall coverage
    if let lineCoverage = json["lineCoverage"] as? Double {
      lines.append(String(format: "Overall coverage: %.1f%%", lineCoverage * 100))
    }

    // Per-target coverage
    if let targets = json["targets"] as? [[String: Any]] {
      for target in targets {
        let name = (target["name"] as? String) ?? "?"
        let cov = (target["lineCoverage"] as? Double) ?? 0
        lines.append(String(format: "\nTarget: %@ (%.1f%%)", name, cov * 100))

        // Per-file coverage
        if let files = target["files"] as? [[String: Any]] {
          var fileEntries: [(String, Double)] = []
          for file in files {
            let path = (file["path"] as? String) ?? (file["name"] as? String) ?? "?"
            let fileCov = (file["lineCoverage"] as? Double) ?? 0
            let pct = fileCov * 100
            if pct < minCoverage {
              // Show just filename, not full path
              let shortPath = (path as NSString).lastPathComponent
              fileEntries.append((shortPath, pct))
            }
          }
          // Sort by coverage ascending
          fileEntries.sort { $0.1 < $1.1 }
          for (path, pct) in fileEntries {
            lines.append(String(format: "  %6.1f%% %@", pct, path))
          }
        }
      }
    }

    lines.append("\nxcresult: \(xcresultPath)")
    let output = lines.joined(separator: "\n")
    let truncated =
      output.count > 50000 ? String(output.prefix(50000)) + "\n... [truncated]" : output
    return .ok(truncated)
  }

  private static func formatBuildDiagnosis(_ execution: BuildDiagnosisExecution) -> CallTool.Result {
    let summary = DiagnosisBuildWorkflow.buildSummary(from: execution)
    var lines: [String] = []
    let status = execution.succeeded ? "SUCCEEDED" : "FAILED"
    lines.append("Build \(status) in \(execution.elapsed)s")

    let observed = summary.observedEvidence
    if observed.errorCount > 0 || observed.warningCount > 0 || observed.analyzerWarningCount > 0 {
      var parts: [String] = []
      if observed.errorCount > 0 { parts.append("\(observed.errorCount) error(s)") }
      if observed.warningCount > 0 { parts.append("\(observed.warningCount) warning(s)") }
      if observed.analyzerWarningCount > 0 {
        parts.append("\(observed.analyzerWarningCount) analyzer warning(s)")
      }
      lines.append(parts.joined(separator: ", "))
    }

    if let primarySignal = observed.primarySignal {
      let prefix: String
      switch primarySignal.severity {
      case .error:
        prefix = "ERROR"
      case .warning:
        prefix = "WARNING"
      case .analyzerWarning:
        prefix = "ANALYZER"
      }
      var location = ""
      if let sourceLocation = primarySignal.location {
        let shortPath = (sourceLocation.filePath as NSString).lastPathComponent
        location = " (\(shortPath)"
        if let line = sourceLocation.line {
          location += ":\(line)"
        }
        location += ")"
      }
      lines.append("\(prefix)\(location): \(primarySignal.message)")
    } else {
      lines.append(observed.summary)
    }

    if let name = execution.destinationDeviceName, !name.isEmpty {
      let os = execution.destinationOSVersion ?? ""
      lines.append("Device: \(name) (\(os))")
    }

    if let inferredConclusion = summary.inferredConclusion {
      lines.append("Summary: \(inferredConclusion.summary)")
    }

    for reference in summary.supportingEvidence {
      lines.append("\(reference.kind): \(reference.path)")
    }
    let output = lines.joined(separator: "\n")
    let truncated =
      output.count > 50000 ? String(output.prefix(50000)) + "\n... [truncated]" : output

    return execution.succeeded ? .ok(truncated) : .fail(truncated)
  }

  static func parseBuildIssues(
    _ json: [String: Any]
  ) -> (
    issues: [BuildIssueObservation],
    errorCount: Int,
    warningCount: Int,
    analyzerWarningCount: Int,
    destinationDeviceName: String?,
    destinationOSVersion: String?
  ) {
    let errorCount = (json["errorCount"] as? Int) ?? 0
    let warningCount = (json["warningCount"] as? Int) ?? 0
    let analyzerWarningCount = (json["analyzerWarningCount"] as? Int) ?? 0

    func location(from issue: [String: Any]) -> SourceLocation? {
      if let sourceURL = issue["sourceURL"] as? String {
        let cleanURL: String
        if let hashIndex = sourceURL.firstIndex(of: "#") {
          cleanURL = String(sourceURL[sourceURL.startIndex..<hashIndex])
        } else {
          cleanURL = sourceURL
        }
        let path = cleanURL.hasPrefix("file://") ? String(cleanURL.dropFirst(7)) : cleanURL

        var line: Int?
        var column: Int?
        if let hashIndex = sourceURL.firstIndex(of: "#") {
          let fragment = String(sourceURL[sourceURL.index(after: hashIndex)...])
          for param in fragment.split(separator: "&") {
            if param.hasPrefix("StartingLineNumber=") {
              line = Int(param.dropFirst("StartingLineNumber=".count))
            } else if param.hasPrefix("StartingColumnNumber=") {
              column = Int(param.dropFirst("StartingColumnNumber=".count))
            }
          }
        }
        return SourceLocation(filePath: path, line: line, column: column)
      }

      if let documentLocation = issue["documentLocation"] as? [String: Any],
        let url = documentLocation["url"] as? String
      {
        let path = url.hasPrefix("file://") ? String(url.dropFirst(7)) : url
        return SourceLocation(filePath: path)
      }

      return nil
    }

    func collectIssues(key: String, severity: BuildIssueSeverity) -> [BuildIssueObservation] {
      guard let issues = json[key] as? [[String: Any]] else { return [] }
      return issues.map { issue in
        BuildIssueObservation(
          severity: severity,
          message: (issue["message"] as? String) ?? "No message",
          location: location(from: issue),
          source: "xcresult.\(key)"
        )
      }
    }

    let issues =
      collectIssues(key: "errors", severity: .error)
      + collectIssues(key: "warnings", severity: .warning)
      + collectIssues(key: "analyzerWarnings", severity: .analyzerWarning)

    let destination = json["destination"] as? [String: Any]
    return (
      issues: issues,
      errorCount: errorCount,
      warningCount: warningCount,
      analyzerWarningCount: analyzerWarningCount,
      destinationDeviceName: destination?["deviceName"] as? String,
      destinationOSVersion: destination?["osVersion"] as? String
    )
  }

  static func fallbackBuildIssues(stderr: String) -> [BuildIssueObservation] {
    stderr
      .split(separator: "\n")
      .compactMap { parseFallbackBuildIssue(String($0)) }
  }

  private static func extractExecutionFailureMessage(stderr: String) -> String? {
    let relevantLine =
      stderr
      .split(separator: "\n")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .first {
        !$0.isEmpty
          && ($0.localizedCaseInsensitiveContains("error")
            || $0.localizedCaseInsensitiveContains("failed")
            || $0.localizedCaseInsensitiveContains("unable")
            || $0.localizedCaseInsensitiveContains("unavailable"))
      }

    guard let relevantLine, !relevantLine.isEmpty else { return nil }
    return relevantLine
  }

  static func parseFallbackBuildIssue(_ line: String) -> BuildIssueObservation? {
    let severity: BuildIssueSeverity
    let marker: String
    if line.contains(": error:") {
      severity = .error
      marker = ": error:"
    } else if line.contains(": warning:") {
      severity = .warning
      marker = ": warning:"
    } else {
      return nil
    }

    let parts = line.components(separatedBy: marker)
    guard parts.count >= 2 else { return nil }
    let prefix = parts[0]
    let message = parts[1].trimmingCharacters(in: .whitespaces)

    let prefixParts = prefix.split(separator: ":")
    if prefixParts.count >= 3 {
      let path = prefixParts.dropLast(2).joined(separator: ":")
      let lineNumber = Int(prefixParts[prefixParts.count - 2])
      let columnNumber = Int(prefixParts[prefixParts.count - 1])
      let location =
        path.isEmpty ? nil : SourceLocation(filePath: path, line: lineNumber, column: columnNumber)
      return BuildIssueObservation(
        severity: severity,
        message: message,
        location: location,
        source: "xcodebuild.stderr"
      )
    }

    if prefixParts.count == 2 {
      let path = String(prefixParts[0])
      let lineNumber = Int(prefixParts[1])
      return BuildIssueObservation(
        severity: severity,
        message: message,
        location: path.isEmpty ? nil : SourceLocation(filePath: path, line: lineNumber),
        source: "xcodebuild.stderr"
      )
    }

    return BuildIssueObservation(
      severity: severity,
      message: message,
      location: nil,
      source: "xcodebuild.stderr"
    )
  }

  private static func persistCommandStderr(_ stderr: String, path: String, label: String) -> String? {
    let url = URL(fileURLWithPath: path + ".\(label).txt")
    do {
      try stderr.write(to: url, atomically: true, encoding: .utf8)
      return url.path
    } catch {
      Log.warn("persistCommandStderr failed: \(error)")
      return nil
    }
  }
}

extension TestTools: ToolProvider {
  public static func dispatch(_ name: String, _ args: [String: Value]?, env: Environment) async
    -> CallTool.Result?
  {
    switch name {
    case "test_sim": return await testSim(args, env: env)
    case "test_failures": return await testFailures(args, env: env)
    case "test_coverage": return await testCoverage(args, env: env)
    case "build_and_diagnose": return await buildAndDiagnose(args, env: env)
    case "build_and_test": return await buildAndTest(args, env: env)
    case "list_tests": return await listTests(args, env: env)
    default: return nil
    }
  }
}

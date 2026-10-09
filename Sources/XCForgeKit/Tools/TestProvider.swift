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
    /// Full ID, `Target/Suite/test()`, the form `list_tests` prints and filters accept.
    public let testIdentifier: String
    /// Every message joined, for display. `messages` has them one by one with location.
    public let message: String
    public let source: String
    /// Each failure message with its file and line, and the argument or repetition it came from.
    public var messages: [FailureMessage]?
    /// Files xcresult attached to this test (failure screenshots).
    public var attachments: [String]?
    /// The last lines the test printed, when console output was requested.
    public var console: String?
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
    public let hangDiagnosticPath: String?
    public let hangDiagnosticSummary: String?

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
      destinationOSVersion: String?,
      hangDiagnosticPath: String? = nil,
      hangDiagnosticSummary: String? = nil
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
      self.hangDiagnosticPath = hangDiagnosticPath
      self.hangDiagnosticSummary = hangDiagnosticSummary
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
    public let hangDiagnosticPath: String?
    public let hangDiagnosticSummary: String?
    /// Non-nil when xcresulttool failed to parse the result bundle (e.g. finalization race).
    /// Includes the xcodebuild exit code so callers can distinguish a parse failure from a real test failure.
    public let xcresultParseError: String?
    /// `true` when xcforge's watchdog killed xcodebuild (exit code -1).
    public let xcforgeTimedOut: Bool
    /// Up to 10 slowest tests by elapsed time, sorted descending. Empty when timing data is unavailable.
    public let slowestTests: [SlowTest]
    /// Test IDs the run treated as known-failing via `.xcforge/known-failures.yaml`.
    /// Non-nil only when the gate was requested for this run.
    public let knownFailures: [String]?
    /// Tests that failed at least once and then passed on a retry or repetition.
    public let flakyTests: [String]
    /// Which limit killed the run and how to raise it, when `xcforgeTimedOut`.
    public let timeoutDetail: String?

    init(
      succeeded: Bool,
      elapsed: String,
      xcresultPath: String,
      scheme: String,
      simulator: String,
      totalTestCount: Int,
      passedTestCount: Int,
      failedTestCount: Int,
      skippedTestCount: Int,
      expectedFailureCount: Int,
      failures: [TestFailureObservation],
      deviceName: String?,
      osVersion: String?,
      screenshotPaths: [ScreenshotAttachment],
      hasStructuredSummary: Bool,
      buildFailed: Bool,
      buildDiagnostics: [BuildIssueObservation]?,
      hangDiagnosticPath: String? = nil,
      hangDiagnosticSummary: String? = nil,
      xcresultParseError: String? = nil,
      xcforgeTimedOut: Bool = false,
      slowestTests: [SlowTest] = [],
      knownFailures: [String]? = nil,
      flakyTests: [String] = [],
      timeoutDetail: String? = nil
    ) {
      self.succeeded = succeeded
      self.elapsed = elapsed
      self.xcresultPath = xcresultPath
      self.scheme = scheme
      self.simulator = simulator
      self.totalTestCount = totalTestCount
      self.passedTestCount = passedTestCount
      self.failedTestCount = failedTestCount
      self.skippedTestCount = skippedTestCount
      self.expectedFailureCount = expectedFailureCount
      self.failures = failures
      self.deviceName = deviceName
      self.osVersion = osVersion
      self.screenshotPaths = screenshotPaths
      self.hasStructuredSummary = hasStructuredSummary
      self.buildFailed = buildFailed
      self.buildDiagnostics = buildDiagnostics
      self.hangDiagnosticPath = hangDiagnosticPath
      self.hangDiagnosticSummary = hangDiagnosticSummary
      self.xcresultParseError = xcresultParseError
      self.xcforgeTimedOut = xcforgeTimedOut
      self.slowestTests = slowestTests
      self.knownFailures = knownFailures
      self.flakyTests = flakyTests
      self.timeoutDetail = timeoutDetail
    }
  }

  public struct SlowTest: Codable, Sendable {
    public let testName: String
    public let elapsedSeconds: Double
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
    /// The bundle is a test build that failed: `failures` are its compile errors.
    public var buildFailed = false
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
    var long: Bool?
    var diagnose: Bool?
    var simRecovery: String?
    var `for`: String?
    var gate: Bool?
    var isolatedSimulator: Bool?
    var timeoutSeconds: Int?
    var env: [String]?
    var skipBuild: Bool?
    var retries: Int?
    var iterations: Int?
    var untilFailure: Bool?
    var parallel: Bool?
    var testTimeoutSeconds: Int?
    var includeConsole: Bool?
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
    var long: Bool?
    var diagnose: Bool?
    var simRecovery: String?
    var timeoutSeconds: Int?
    // Each entry is KEY=VALUE; KEY is auto-prefixed with TEST_RUNNER_ before reaching xcodebuild.
    var env: [String]?
    var `for`: String?
    var gate: Bool?
    var isolatedSimulator: Bool?
    var skipBuild: Bool?
    var retries: Int?
    var iterations: Int?
    var untilFailure: Bool?
    var parallel: Bool?
    var testTimeoutSeconds: Int?
    var includeConsole: Bool?
  }

  /// Error for malformed --env / env: entries.
  public struct TestRunnerEnvError: Error, CustomStringConvertible {
    public let description: String
    init(_ message: String) { self.description = message }
  }

  /// Validate, auto-prefix, and inject defaults for the `--env` / `env:` test-runner channel.
  ///
  /// Each `userEntry` is `KEY=VALUE` (first `=` only); the resulting child-process env contains
  /// `TEST_RUNNER_<KEY>=<VALUE>`. Duplicate keys: last wins. `TEST_RUNNER_XCFORGE_REPO_ROOT` is
  /// injected from `repoRoot` only if the user did not already supply `XCFORGE_REPO_ROOT`.
  static func buildTestRunnerEnvironment(
    userEntries: [String],
    repoRoot: String
  ) throws -> [String: String] {
    var out: [String: String] = [:]
    for raw in userEntries {
      guard let eq = raw.firstIndex(of: "=") else {
        throw TestRunnerEnvError("invalid --env value \"\(raw)\": expected KEY=VALUE")
      }
      let key = String(raw[..<eq])
      let value = String(raw[raw.index(after: eq)...])
      if key.isEmpty {
        throw TestRunnerEnvError("invalid --env value \"\(raw)\": key must be non-empty")
      }
      if key.rangeOfCharacter(from: .whitespacesAndNewlines) != nil {
        throw TestRunnerEnvError("invalid --env key \"\(key)\": no whitespace allowed")
      }
      out["TEST_RUNNER_\(key)"] = value
    }
    if out["TEST_RUNNER_XCFORGE_REPO_ROOT"] == nil {
      out["TEST_RUNNER_XCFORGE_REPO_ROOT"] = repoRoot
    }
    return out
  }

  struct ListTestsInput: Decodable {
    var project: String?
    var scheme: String?
    var simulator: String?
    var filter: String?
    var testplan: String?
  }

  // MARK: - Public Result Types for build_and_test

  public struct BuildAndTestResult: Codable, Sendable {
    public let phase: String  // "build" or "test"
    public let buildSucceeded: Bool
    public let buildElapsed: String
    public let buildDiagnostics: [BuildIssueObservation]?
    public let testResult: TestExecution?
    public let hangDiagnosticPath: String?
    /// Number of auto-recovery attempts made (0 when no recovery was needed or triggered).
    public let recoveryAttempts: Int
    /// Human-readable reason the last recovery fired (e.g. "sim_unhealthy", "swbbuildservice_deadlock").
    public let recoveryReason: String?
    /// Non-nil when recovery was attempted but ultimately failed.
    public let recoveryFailureReason: String?
    /// What the sim health check found (e.g. "state=Shutdown"). Nil when recovery was off or not needed.
    public let simHealthCheckDetail: String?
    /// `true` when xcforge's watchdog killed xcodebuild during the build phase (exit code -1).
    public let xcforgeTimedOut: Bool
    /// Test IDs gated via `.xcforge/known-failures.yaml`. Non-nil only when gating was requested.
    public let knownFailures: [String]?
    /// What was built and tested.
    public let project: String?
    public let scheme: String?
    public let simulator: String?
    /// True when build-for-testing was skipped and the last build's products were tested.
    public let skippedBuild: Bool
    /// Result bundle of a failed build-for-testing.
    public let buildXcresultPath: String?
    public let hangDiagnosticSummary: String?
    /// Timeout explanation, or the end of xcodebuild's output when no diagnostics were parsed.
    public let buildFailureDetail: String?

    init(
      phase: String,
      buildSucceeded: Bool,
      buildElapsed: String,
      buildDiagnostics: [BuildIssueObservation]?,
      testResult: TestExecution?,
      hangDiagnosticPath: String? = nil,
      recoveryAttempts: Int = 0,
      recoveryReason: String? = nil,
      recoveryFailureReason: String? = nil,
      simHealthCheckDetail: String? = nil,
      xcforgeTimedOut: Bool = false,
      knownFailures: [String]? = nil,
      project: String? = nil,
      scheme: String? = nil,
      simulator: String? = nil,
      skippedBuild: Bool = false,
      buildXcresultPath: String? = nil,
      hangDiagnosticSummary: String? = nil,
      buildFailureDetail: String? = nil
    ) {
      self.phase = phase
      self.buildSucceeded = buildSucceeded
      self.buildElapsed = buildElapsed
      self.buildDiagnostics = buildDiagnostics
      self.testResult = testResult
      self.hangDiagnosticPath = hangDiagnosticPath
      self.recoveryAttempts = recoveryAttempts
      self.recoveryReason = recoveryReason
      self.recoveryFailureReason = recoveryFailureReason
      self.simHealthCheckDetail = simHealthCheckDetail
      self.xcforgeTimedOut = xcforgeTimedOut
      self.knownFailures = knownFailures
      self.project = project
      self.scheme = scheme
      self.simulator = simulator
      self.skippedBuild = skippedBuild
      self.buildXcresultPath = buildXcresultPath
      self.hangDiagnosticSummary = hangDiagnosticSummary
      self.buildFailureDetail = buildFailureDetail
    }
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
    /// Tests the scheme or test plan disables. Nil when xcodebuild did not report them.
    public let disabledTestCount: Int?

    public init(
      tests: [TestIdentifier], targetCount: Int, classCount: Int, testCount: Int,
      disabledTestCount: Int? = nil
    ) {
      self.tests = tests
      self.targetCount = targetCount
      self.classCount = classCount
      self.testCount = testCount
      self.disabledTestCount = disabledTestCount
    }
  }

  /// Options every test-running tool takes, so a rerun can reproduce the run it repeats.
  static let testRunSchemaProperties: [String: Value] = [
    "timeoutSeconds": .object([
      "type": .string("integer"),
      "description": .string(
        "Total time limit in seconds for each xcodebuild step. Takes precedence over 'long'. Default: 1800 (7200 with long)."
      ),
    ]),
    "env": .object([
      "type": .string("array"),
      "items": .object(["type": .string("string")]),
      "description": .string(
        "Environment variables for the test runner, each KEY=VALUE. The key is prefixed with TEST_RUNNER_ for"
          + " xcodebuild, which strips it inside the test process, so 'BLESS_BASELINE=1' reads as"
          + " ProcessInfo.environment[\"BLESS_BASELINE\"]. TEST_RUNNER_XCFORGE_REPO_ROOT is always set."
      ),
    ]),
    "skipBuild": .object([
      "type": .string("boolean"),
      "description": .string(
        "Skip build-for-testing and test the last build's products. Only valid when no source changed since."),
    ]),
    "retries": .object([
      "type": .string("integer"),
      "description": .string(
        "Rerun a failing test up to this many more times. Tests that then pass are listed as flaky."),
    ]),
    "iterations": .object([
      "type": .string("integer"),
      "description": .string("Run every test this many times."),
    ]),
    "untilFailure": .object([
      "type": .string("boolean"),
      "description": .string("Repeat the tests until one fails (capped by iterations when given)."),
    ]),
    "parallel": .object([
      "type": .string("boolean"),
      "description": .string("Turn parallel testing on or off. Default: the scheme's or test plan's setting."),
    ]),
    "testTimeoutSeconds": .object([
      "type": .string("integer"),
      "description": .string(
        "Time allowance per test in seconds (XCTest; Swift Testing uses .timeLimit in code)."),
    ]),
    "includeConsole": .object([
      "type": .string("boolean"),
      "description": .string("Attach the last lines each failing test printed to its failure."),
    ]),
  ]

  public static let tools: [Tool] = [
    Tool(
      name: "test_sim",
      description: """
        Build for testing, then run tests on a simulator and return the result: counts, and \
        each failure with its full test ID, every message with file:line, and attachments. \
        Project, scheme, and simulator are auto-detected if omitted.
        """,
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object(
          testRunSchemaProperties.merging([
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
              "description": .string("Test plan name. Default: .xcforge.yaml testPlan, else the scheme's."),
            ]),
            "filter": .object([
              "type": .string("string"),
              "description": .string(
                "Tests to run, comma-separated. Full IDs as list_tests prints them ('Target/Suite/test()',"
                  + " 'Target/Class/testMethod'), or without the target ('Suite/test()', 'Suite'), which is"
                  + " added from the scheme or test plan."
              ),
            ]),
            "coverage": .object([
              "type": .string("boolean"),
              "description": .string("Enable code coverage collection. Default: false"),
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
            "simRecovery": .object([
              "type": .string("string"),
              "description": .string(
                "Simulator recovery before the run: 'off' (default) leaves the simulator alone; 'auto' reboots it if it isn't Booted;"
                  + " 'erase' also erases it if a reboot didn't help (destroys its apps and data)."
              ),
              "enum": .array([.string("off"), .string("auto"), .string("erase")]),
            ]),
            "isolatedSimulator": .object([
              "type": .string("boolean"),
              "description": .string(
                "Run on a fresh simulator of the same model and OS, created for this run and deleted afterwards."
                  + " Avoids collisions with other sessions on a shared simulator. Costs one cold boot."
              ),
            ]),
            "for": .object([
              "type": .string("string"),
              "description": .string(
                "Output audience. 'human' (default) preserves the full JSON shape; 'agent' returns a slim ≤10-field projection."
              ),
              "enum": .array([.string("human"), .string("agent")]),
            ]),
            "gate": .object([
              "type": .string("boolean"),
              "description": .string(
                "Subtract IDs listed in .xcforge/known-failures.yaml when computing succeeded:. Opt-in; raw failure list is unchanged."
              ),
            ]),
          ]) { current, _ in current }
        ),
      ])
    ),
    Tool(
      name: "test_failures",
      description: """
        Failed tests with their messages from an xcresult bundle: xcresult_path, or else \
        the project's last test run (test_sim, build_and_test). Never runs tests. \
        When that run failed to build, returns its compile errors instead.
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
        tests and returns pass/fail summary. \
        Project, scheme, and simulator are auto-detected if omitted.
        """,
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object(
          testRunSchemaProperties.merging([
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
              "description": .string("Test plan name. Default: .xcforge.yaml testPlan, else the scheme's."),
            ]),
            "filter": .object([
              "type": .string("string"),
              "description": .string(
                "Tests to run, comma-separated. Full IDs as list_tests prints them ('Target/Suite/test()',"
                  + " 'Target/Class/testMethod'), or without the target ('Suite/test()', 'Suite'), which is"
                  + " added from the scheme or test plan."
              ),
            ]),
            "coverage": .object([
              "type": .string("boolean"),
              "description": .string("Enable code coverage collection. Default: false"),
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
            "simRecovery": .object([
              "type": .string("string"),
              "description": .string(
                "Simulator recovery before the run: 'off' (default) leaves the simulator alone; 'auto' reboots it if it isn't Booted;"
                  + " 'erase' also erases it if a reboot didn't help (destroys its apps and data)."
              ),
              "enum": .array([.string("off"), .string("auto"), .string("erase")]),
            ]),
            "isolatedSimulator": .object([
              "type": .string("boolean"),
              "description": .string(
                "Run on a fresh simulator of the same model and OS, created for this run and deleted afterwards."
                  + " Avoids collisions with other sessions on a shared simulator. Costs one cold boot."
              ),
            ]),
            "for": .object([
              "type": .string("string"),
              "description": .string(
                "Output audience. 'human' (default) preserves the full JSON shape; 'agent' returns a slim ≤10-field projection."
              ),
              "enum": .array([.string("human"), .string("agent")]),
            ]),
            "gate": .object([
              "type": .string("boolean"),
              "description": .string(
                "Subtract IDs listed in .xcforge/known-failures.yaml when computing succeeded:. Opt-in; raw failure list is unchanged."
              ),
            ]),
          ]) { current, _ in current }
        ),
      ])
    ),
    Tool(
      name: "list_tests",
      description: """
        List test identifiers (Target/Class/method) for a scheme or test plan, XCTest and Swift Testing. \
        Identifiers are in the exact form test_sim and build_and_test accept as filter. \
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
          "testplan": .object([
            "type": .string("string"),
            "description": .string(
              "List the tests this test plan runs (its tags and skips applied). Default: .xcforge.yaml testPlan, else the scheme's."
            ),
          ]),
        ]),
      ])
    ),
    Tool(
      name: "test_plan_inspect",
      description: """
        Parse and summarise a .xctestplan file without running tests. \
        Returns configurations, defaultOptions, and test targets with skipped-test counts. \
        Project path is auto-detected if omitted.
        """,
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "plan": .object([
            "type": .string("string"),
            "description": .string(
              "Test plan name, with or without the .xctestplan extension."
            ),
          ]),
          "project": .object([
            "type": .string("string"),
            "description": .string("Path to .xcodeproj or .xcworkspace. Auto-detected if omitted."),
          ]),
        ]),
        "required": .array([.string("plan")]),
      ])
    ),
  ]

  // MARK: - Shared helpers

  /// Generate a unique xcresult path (or the caller's fixed `resultBundlePath`).
  static func xcresultPath(prefix: String) -> String {
    XcodebuildOptions.resultBundlePath(prefix: prefix)
  }

  /// Resolve the test watchdog timeout via the session actor.
  /// Precedence: explicit `timeoutSeconds` > `.xcforge.yaml` `testTimeout`
  /// > `long ? 7200 : 1800`. Centralized so every test/build path picks up
  /// the same configurable default.
  static func resolveTestTimeout(
    explicit: Int? = nil, long: Bool, env: Environment
  ) async -> TimeInterval {
    await env.session.resolveTestTimeout(explicit: explicit, long: long)
  }

  static func diagnosticSnapshotPath() -> String {
    XcodebuildOptions.uniqueArtifactPath(prefix: "diag", extension: "txt")
  }

  private static func resolvedDiagResult(
    result: ShellResult, diagnose: Bool, watchdog: HangWatchdog,
    udid: String?, snapshotPath: String, processMatch: String? = nil, env: Environment
  ) async -> DiagnosticSnapshot.Result? {
    let watchdogCapture = await watchdog.latestResult
    // A sample of a healthy build is noise: report one only for a timeout or when asked.
    guard result.exitCode == -1 || diagnose else { return nil }
    if let captured = watchdogCapture { return captured }
    return await DiagnosticSnapshot.capture(
      udid: udid, snapshotPath: snapshotPath, processMatch: processMatch, env: env)
  }

  private static func formatDiagnosticSuffix(_ result: DiagnosticSnapshot.Result?) -> String {
    guard let result else { return "" }
    return "\nDiagnostic snapshot: \(result.filePath)\nSummary: \(result.summaryLine)"
  }

  /// Find this project's most recent test bundle that has coverage data.
  /// Uses the bundle recorded for the project's last test run; when the project can't be
  /// resolved, falls back to the newest xcforge bundles in the artifact directory.
  private static func findRecentCoverageXcresult(project: String? = nil, env: Environment) async
    -> String?
  {
    if let resolved = try? await env.session.resolveProject(project) {
      guard let recorded = LastResultStore.latest(project: resolved, kind: .test) else {
        return nil
      }
      return await parseCoverage(recorded, onlyTargets: true, env: env) != nil ? recorded : nil
    }
    let dir = XcodebuildOptions.artifactDirectory()
    do {
      let result = try await env.shell.run("/bin/ls", arguments: ["-1t", dir], timeout: 5)
      guard result.succeeded else { return nil }
      let candidates = result.stdout.split(separator: "\n")
        .map(String.init)
        .filter { $0.hasPrefix("xcf-test-") && $0.hasSuffix(".xcresult") }
      for candidate in candidates.prefix(3) {
        let path = (dir as NSString).appendingPathComponent(candidate)
        if await parseCoverage(path, onlyTargets: true, env: env) != nil {
          return path
        }
      }
    } catch {
      // Ignore — caller reports that no coverage is available.
    }
    return nil
  }

  /// Split a comma-separated filter list into individual `-only-testing` identifiers.
  /// Single-identifier filters (the common case) pass through unchanged. Commas that
  /// appear inside `[...]` parameterized-test brackets or `(...)` argument groups are
  /// preserved — Swift Testing identifiers like `Suite/test(arg1,arg2)` must not be
  /// split.
  static func splitFilterList(_ filter: String) -> [String] {
    var out: [String] = []
    var current = ""
    var bracketDepth = 0
    var parenDepth = 0
    for ch in filter {
      if ch == "[" { bracketDepth += 1 }
      if ch == "]" && bracketDepth > 0 { bracketDepth -= 1 }
      if ch == "(" { parenDepth += 1 }
      if ch == ")" && parenDepth > 0 { parenDepth -= 1 }
      if ch == "," && bracketDepth == 0 && parenDepth == 0 {
        let t = current.trimmingCharacters(in: .whitespaces)
        if !t.isEmpty { out.append(t) }
        current = ""
        continue
      }
      current.append(ch)
    }
    let last = current.trimmingCharacters(in: .whitespaces)
    if !last.isEmpty { out.append(last) }
    return out
  }

  /// Resolve a partial test filter into the full `-only-testing` format.
  /// Agents often pass `ClassName/testMethod` or just `testMethod` without the test target prefix.
  /// This discovers the test target(s) and prepends when missing.
  static func resolveFilter(
    _ filter: String, project: String, scheme: String? = nil, testplan: String? = nil, env: Environment
  ) async -> String {
    let trimmedFilter = filter.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedFilter.isEmpty else { return filter }
    let resolved = await resolveFilters(
      splitFilterList(trimmedFilter), project: project, scheme: scheme, testplan: testplan, env: env)
    return resolved.joined(separator: ",")
  }

  /// Resolve each ID to `Target/Suite/test()` and its `-only-testing` spelling. Test targets
  /// are looked up once, and only when an ID needs one.
  static func resolveFilters(
    _ ids: [String], project: String, scheme: String? = nil, testplan: String? = nil, env: Environment
  ) async -> [String] {
    var targets: AutoDetect.TestTargets?
    var resolved: [String] = []
    for raw in ids {
      let id = TestIDs.collapseDoubleParens(raw.trimmingCharacters(in: .whitespacesAndNewlines))
      guard !id.isEmpty else { continue }
      if targets == nil {
        targets = await AutoDetect.testTargetNames(
          project: project, scheme: scheme, testplan: testplan, env: env)
      }
      let known = targets ?? AutoDetect.TestTargets(names: [], exact: false)
      resolved.append(TestIDs.onlyTestingArgument(qualify(id, targets: known.names, exact: known.exact)))
    }
    return resolved
  }

  /// Prefix `id` with its test target when it lacks one and the target is known. `exact` says
  /// the target list came from the scheme or test plan rather than a naming guess; only then
  /// is a three-part ID such as `Outer/Inner/test()` taken to be missing its target.
  static func qualify(_ id: String, targets: [String], exact: Bool = true) -> String {
    let components = TestIDs.components(id)
    // Already starts with a known target (also prevents "Target/Suite" → "Target/Target/Suite").
    if let first = components.first, targets.contains(first) { return id }
    if !exact && components.count >= 3 { return id }
    if targets.count == 1 { return "\(targets[0])/\(id)" }
    if targets.count > 1 && components.count < 3 {
      Log.warn(
        "Multiple test targets found: \(targets.joined(separator: ", ")). Cannot auto-resolve filter '\(id)'."
          + " Prefix with target name, e.g. '\(targets[0])/\(id)'")
    }
    // Unknown targets: three or more components is taken to be complete already.
    return id
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

    guard
      let listResult = try? await executeListTests(
        project: project, scheme: scheme, simulator: simulator, testplan: testplan, withoutBuilding: true, env: env
      )
    else {
      hint += "\nCould not enumerate tests to suggest alternatives."
      return hint
    }
    hint += "\n(found \(listResult.testCount) test identifiers via -enumerate-tests)"
    if listResult.testCount == 0 {
      hint += "\nThe test bundle appears to be empty."
      return hint
    }
    let lowered = TestIDs.key(filter).lowercased()
    let matches = listResult.tests.filter {
      TestIDs.same($0.fullIdentifier, filter) || $0.fullIdentifier.lowercased().contains(lowered)
    }
    if !matches.isEmpty {
      hint += "\nDid you mean:"
      for m in matches.prefix(10) {
        hint += "\n  \(m.fullIdentifier)"
      }
    } else {
      let ids = listResult.tests.map { $0.fullIdentifier }
      let fuzzyResults = FuzzyMatch.fuzzyRank(needle: filter, candidates: ids)
      if !fuzzyResults.isEmpty {
        hint +=
          "\nDid you mean: \(fuzzyResults.map(\.candidate).joined(separator: ", "))?"
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

  /// Flags every compiling call passes, so `build compile`, build-for-testing and `test`
  /// share one set of build settings and don't rebuild each other's products.
  static let compileFlags = ["-parallelizeTargets"]
  static let compileSettings = ["COMPILATION_CACHE_ENABLE_CACHING=YES"]

  /// Run xcodebuild test and return the xcresult path plus any diagnostic snapshot.
  private static func runTests(
    project: String, scheme: String, destination: String,
    configuration: String, testplan: String?, filter: String?,
    coverage: Bool, resultPath: String,
    long: Bool = false, diagnose: Bool = false, udid: String? = nil,
    childEnvironment: [String: String]? = nil,
    env: Environment
  ) async throws -> (ShellResult, String, DiagnosticSnapshot.Result?) {
    // Remove old xcresult if exists
    _ = try? await env.shell.run("/bin/rm", arguments: ["-rf", resultPath], timeout: 5)

    var args = xcodebuildBaseArgs(
      project: project, scheme: scheme,
      destination: destination, configuration: configuration
    )
    args += compileFlags
    args += ["-resultBundlePath", resultPath]

    if coverage {
      args += ["-enableCodeCoverage", "YES"]
    }

    if let plan = testplan {
      args += ["-testPlan", plan]
    }

    if let f = filter {
      for id in splitFilterList(f) {
        args += ["-only-testing", id]
      }
    }

    args += ["test"] + compileSettings

    let timeout = await resolveTestTimeout(long: long, env: env)
    let snapshotPath = diagnosticSnapshotPath()
    let watchdog = HangWatchdog(
      udid: udid, snapshotPath: snapshotPath, sampleAt: HangWatchdog.defaultSampleAt, processMatch: resultPath,
      env: env)
    let result = try await Xcodebuild.run(
      args, environment: childEnvironment, timeout: timeout, env: env)
    watchdog.cancel()
    let diagResult = await resolvedDiagResult(
      result: result, diagnose: diagnose, watchdog: watchdog,
      udid: udid, snapshotPath: snapshotPath, processMatch: resultPath, env: env)
    return (result, resultPath, diagResult)
  }

  /// Run xcodebuild build and return the xcresult path plus any diagnostic snapshot.
  private static func runBuild(
    project: String, scheme: String, destination: String,
    configuration: String, resultPath: String,
    long: Bool = false, diagnose: Bool = false, udid: String? = nil,
    env: Environment
  ) async throws -> (ShellResult, String, DiagnosticSnapshot.Result?) {
    _ = try? await env.shell.run("/bin/rm", arguments: ["-rf", resultPath], timeout: 5)

    var args = xcodebuildBaseArgs(
      project: project, scheme: scheme,
      destination: destination, configuration: configuration
    )
    args += compileFlags
    args += ["-resultBundlePath", resultPath, "build"] + compileSettings

    let timeout = await resolveTestTimeout(long: long, env: env)
    let snapshotPath = diagnosticSnapshotPath()
    let watchdog = HangWatchdog(
      udid: udid, snapshotPath: snapshotPath, sampleAt: HangWatchdog.defaultSampleAt, processMatch: resultPath,
      env: env)
    let result = try await Xcodebuild.run(args, timeout: timeout, env: env)
    watchdog.cancel()
    let diagResult = await resolvedDiagResult(
      result: result, diagnose: diagnose, watchdog: watchdog,
      udid: udid, snapshotPath: snapshotPath, processMatch: resultPath, env: env)
    return (result, resultPath, diagResult)
  }

  /// Run `xcodebuild build-for-testing` and return the xcresult path plus any diagnostic snapshot.
  ///
  /// `testplan` and `targets` limit the build to the test targets the run needs; nil
  /// `targets` builds every test target in the scheme or plan.
  static func runBuildForTesting(
    project: String, scheme: String, destination: String,
    configuration: String, coverage: Bool, resultPath: String,
    testplan: String? = nil, targets: [String]? = nil,
    long: Bool = false, diagnose: Bool = false, udid: String? = nil,
    timeoutOverride: TimeInterval? = nil,
    childEnvironment: [String: String]? = nil,
    env: Environment
  ) async throws -> (ShellResult, String, DiagnosticSnapshot.Result?) {
    _ = try? await env.shell.run("/bin/rm", arguments: ["-rf", resultPath], timeout: 5)

    var args = xcodebuildBaseArgs(
      project: project, scheme: scheme,
      destination: destination, configuration: configuration
    )
    args += compileFlags
    args += ["-resultBundlePath", resultPath]
    if coverage {
      args += ["-enableCodeCoverage", "YES"]
    }
    if let testplan {
      args += ["-testPlan", testplan]
    }
    for target in targets ?? [] {
      args += ["-only-testing", target]
    }
    args += ["build-for-testing"] + compileSettings

    let timeout: TimeInterval
    if let override = timeoutOverride {
      timeout = override
    } else {
      timeout = await resolveTestTimeout(long: long, env: env)
    }
    let snapshotPath = diagnosticSnapshotPath()
    let watchdog = HangWatchdog(
      udid: udid, snapshotPath: snapshotPath, sampleAt: HangWatchdog.defaultSampleAt, processMatch: resultPath,
      env: env)
    let result = try await Xcodebuild.run(
      args, environment: childEnvironment, timeout: timeout, env: env)
    watchdog.cancel()
    let diagResult = await resolvedDiagResult(
      result: result, diagnose: diagnose, watchdog: watchdog,
      udid: udid, snapshotPath: snapshotPath, processMatch: resultPath, env: env)
    return (result, resultPath, diagResult)
  }

  /// Run `xcodebuild test-without-building` and return the xcresult path plus any diagnostic snapshot.
  static func runTestWithoutBuilding(
    project: String, scheme: String, destination: String,
    configuration: String, testplan: String?, filter: String?,
    coverage: Bool, resultPath: String,
    long: Bool = false, diagnose: Bool = false, udid: String? = nil,
    timeoutOverride: TimeInterval? = nil,
    childEnvironment: [String: String]? = nil,
    extraTestArguments: [String] = [],
    env: Environment
  ) async throws -> (ShellResult, String, DiagnosticSnapshot.Result?) {
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
      for id in splitFilterList(f) {
        args += ["-only-testing", id]
      }
    }
    args += extraTestArguments
    args += ["test-without-building"]

    let timeout: TimeInterval
    if let override = timeoutOverride {
      timeout = override
    } else {
      timeout = await resolveTestTimeout(long: long, env: env)
    }
    let snapshotPath = diagnosticSnapshotPath()
    let watchdog = HangWatchdog(
      udid: udid, snapshotPath: snapshotPath, sampleAt: HangWatchdog.defaultSampleAt, processMatch: resultPath,
      env: env)
    var result = try await Xcodebuild.run(
      args, environment: childEnvironment, timeout: timeout, env: env)
    // The test runner sometimes fails to launch or connect on a busy Mac. The build is
    // already done, so one immediate retry is cheap and usually succeeds.
    if !result.succeeded, Xcodebuild.timeoutKind(result) == nil,
      let symptom = runnerLaunchFailure(Xcodebuild.combinedOutput(result))
    {
      Log.warn("Test runner failed to start (\(symptom)); retrying test-without-building once")
      _ = try? await env.shell.run("/bin/rm", arguments: ["-rf", resultPath], timeout: 5)
      result = try await Xcodebuild.run(
        args, environment: childEnvironment, timeout: timeout, env: env)
    }
    watchdog.cancel()
    let diagResult = await resolvedDiagResult(
      result: result, diagnose: diagnose, watchdog: watchdog,
      udid: udid, snapshotPath: snapshotPath, processMatch: resultPath, env: env)
    return (result, resultPath, diagResult)
  }

  /// Messages xcodebuild prints when the test runner never started, as opposed to tests
  /// failing. Matched case-insensitively.
  static let runnerLaunchFailureMarkers = [
    "test runner hung before establishing connection",
    "early unexpected exit, operation never finished bootstrapping",
    "failed to establish communication with the test runner",
    "failed to launch",
  ]

  /// The runner-launch symptom found in `output`, or nil. Output that shows any test
  /// starting never counts, so a crash mid-suite is not re-run.
  static func runnerLaunchFailure(_ output: String) -> String? {
    let lower = output.lowercased()
    if lower.contains("test case '") || lower.contains("◇ test ") { return nil }
    return runnerLaunchFailureMarkers.first { lower.contains($0) }
  }

  /// Polls for `<bundle>/Info.plist` existence up to `timeout` seconds in 500 ms increments.
  /// Returns `true` as soon as the file exists; `false` if timeout is reached.
  /// Handles the xcodebuild finalization race where the process exits before writing Info.plist.
  private static func waitForXCResultReady(_ path: String, timeout: TimeInterval = 5) async -> Bool {
    let infoPlist = "\(path)/Info.plist"
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if FileManager.default.fileExists(atPath: infoPlist) { return true }
      try? await Task.sleep(nanoseconds: 500_000_000)
    }
    return FileManager.default.fileExists(atPath: infoPlist)
  }

  /// Invoke xcresulttool with a single retry on transient failure (Info.plist present but not yet fully committed).
  private static func runXCResultTool(
    arguments: [String], path: String, label: String, env: Environment
  ) async -> String? {
    do {
      var result = try await env.shell.run("/usr/bin/xcrun", arguments: arguments, timeout: 30)
      if result.succeeded { return result.stdout }
      // One 500ms retry in case xcresulttool caught the bundle mid-write
      try? await Task.sleep(nanoseconds: 500_000_000)
      result = try await env.shell.run("/usr/bin/xcrun", arguments: arguments, timeout: 30)
      if result.succeeded { return result.stdout }
      Log.warn("\(label) failed: \(result.stderr)")
      return nil
    } catch {
      Log.warn("\(label) error: \(error)")
      return nil
    }
  }

  /// Parse xcresult test summary JSON
  private static func parseTestSummary(_ path: String, env: Environment) async -> String? {
    guard await waitForXCResultReady(path) else {
      Log.warn("parseTestSummary skipped: Info.plist not present in \(path) after 5s")
      return nil
    }
    return await runXCResultTool(
      arguments: ["xcresulttool", "get", "test-results", "summary", "--path", path, "--compact"],
      path: path, label: "parseTestSummary", env: env)
  }

  /// Parse xcresult test details JSON
  private static func parseTestDetails(_ path: String, env: Environment) async -> String? {
    guard await waitForXCResultReady(path) else {
      Log.warn("parseTestDetails skipped: Info.plist not present in \(path) after 5s")
      return nil
    }
    return await runXCResultTool(
      arguments: ["xcresulttool", "get", "test-results", "tests", "--path", path, "--compact"],
      path: path, label: "parseTestDetails", env: env)
  }

  /// Parse xcresult build results JSON
  static func parseBuildResults(_ path: String, env: Environment) async -> String? {
    guard await waitForXCResultReady(path) else {
      Log.warn("parseBuildResults skipped: Info.plist not present in \(path) after 5s")
      return nil
    }
    return await runXCResultTool(
      arguments: ["xcresulttool", "get", "build-results", "--path", path, "--compact"],
      path: path, label: "parseBuildResults", env: env)
  }

  public static func executeBuildDiagnosis(
    project: String,
    scheme: String,
    simulator: String,
    configuration: String,
    long: Bool = false,
    diagnose: Bool = false,
    env: Environment = .live
  ) async throws -> BuildDiagnosisExecution {
    let resultPath = xcresultPath(prefix: "build")
    let destination = await AutoDetect.buildDestination(simulator)

    let start = CFAbsoluteTimeGetCurrent()
    let (buildResult, path, diagResult) = try await runBuild(
      project: project,
      scheme: scheme,
      destination: destination,
      configuration: configuration,
      resultPath: resultPath,
      long: long,
      diagnose: diagnose,
      udid: simulator,
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
      issues = fallbackBuildIssues(stderr: Xcodebuild.combinedOutput(buildResult))
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
      destinationOSVersion: destinationOSVersion,
      hangDiagnosticPath: diagResult?.filePath,
      hangDiagnosticSummary: diagResult?.summaryLine
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
    let (testResult, path, _) = try await runTests(
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
    let outputDir = XcodebuildOptions.uniqueArtifactPath(prefix: "attachments", extension: "d")
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

  /// Lines of console output kept per test: the end of the output, where a failure is.
  static let consoleTailLines = 40

  /// Console output per test from the xcresult action log, keyed by the test's identifier
  /// when the log gives one and by its name otherwise. Only the last lines are kept.
  static func extractTestConsole(_ xcresultPath: String, env: Environment) async -> [String: String] {
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
      Log.warn("extractTestConsole error: \(error)")
      return [:]
    }
    guard shellResult.succeeded, let data = shellResult.stdout.data(using: .utf8) else {
      if !shellResult.succeeded {
        Log.warn("extractTestConsole failed: \(shellResult.stderr)")
      }
      return [:]
    }
    return parseTestConsole(data)
  }

  static func parseTestConsole(_ data: Data) -> [String: String] {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
    var consoleByTest: [String: String] = [:]

    func findTestOutput(in node: [String: Any]) {
      if let testDetails = node["testDetails"] as? [String: Any],
        let emitted = testDetails["emittedOutput"] as? String
      {
        let key =
          (testDetails["testIdentifier"] as? String) ?? (testDetails["testIdentifierString"] as? String)
          ?? (testDetails["testName"] as? String)
        // Drop Swift Testing's own progress lines; keep everything the test printed.
        let useful = emitted.split(separator: "\n", omittingEmptySubsequences: true)
          .filter { !$0.hasPrefix("◇ Test") && !$0.hasPrefix("↳") }
        if let key, !useful.isEmpty {
          consoleByTest[key] = useful.suffix(consoleTailLines).joined(separator: "\n")
        }
      }
      if let subsections = node["subsections"] as? [[String: Any]] {
        for sub in subsections { findTestOutput(in: sub) }
      }
    }

    findTestOutput(in: json)
    return consoleByTest
  }

  /// The console entry for `testIdentifier`: by ID first, then by bare test name.
  static func console(for testIdentifier: String, in consoleByTest: [String: String]) -> String? {
    if let exact = consoleByTest[testIdentifier] { return exact }
    if let match = consoleByTest.first(where: { TestIDs.same($0.key, testIdentifier) }) {
      return match.value
    }
    let name = TestIDs.components(testIdentifier).last ?? testIdentifier
    return consoleByTest.first { TestIDs.key($0.key) == TestIDs.key(name) }?.value
  }

  /// Put each exported attachment and console tail on the failure it belongs to.
  static func attach(
    attachments: [(test: String, path: String)], console consoleByTest: [String: String],
    to failures: [TestFailureObservation]
  ) -> [TestFailureObservation] {
    failures.map { failure in
      var updated = failure
      let paths = attachments.filter { TestIDs.same($0.test, failure.testIdentifier) }.map(\.path)
      if !paths.isEmpty { updated.attachments = paths }
      if !consoleByTest.isEmpty {
        updated.console = console(for: failure.testIdentifier, in: consoleByTest)
      }
      return updated
    }
  }

  /// Parse coverage report via xccov
  /// Coverage report JSON. `onlyTargets` skips per-file data, which is fast and small; use
  /// it when only a yes/no or per-target numbers are needed. A full report too large to
  /// hold falls back to the per-target report rather than returning truncated JSON.
  private static func parseCoverage(_ path: String, onlyTargets: Bool = false, env: Environment)
    async -> String?
  {
    let limit = 64 * 1024 * 1024
    var arguments = ["xccov", "view", "--report", "--json"]
    if onlyTargets { arguments.append("--only-targets") }
    arguments.append(path)
    do {
      let result = try await env.shell.run(
        "/usr/bin/xcrun", arguments: arguments, timeout: onlyTargets ? 60 : 180, outputLimit: limit)
      guard result.succeeded else {
        Log.warn("parseCoverage failed: \(result.stderr)")
        return nil
      }
      if !onlyTargets, result.stdout.utf8.count >= limit - 8 {
        Log.warn("Coverage report exceeds \(limit / 1024 / 1024) MB; reporting per target only")
        return await parseCoverage(path, onlyTargets: true, env: env)
      }
      // --only-targets prints a bare array of targets; wrap it so callers see one shape.
      let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.hasPrefix("[") { return "{\"targets\": \(trimmed)}" }
      return result.stdout
    } catch {
      Log.warn("parseCoverage error: \(error)")
      return nil
    }
  }

  // MARK: - Public Execution Methods

  /// Options that change how the test step runs. They are passed to
  /// `test-without-building` only, never to `build-for-testing`.
  public struct TestRunOptions: Sendable, Equatable {
    /// Rerun a failing test up to this many more times; one that then passes is reported as flaky.
    public var retries: Int?
    /// Run every test this many times.
    public var iterations: Int?
    /// Repeat until a test fails (capped by `iterations` when given).
    public var untilFailure: Bool
    /// Force parallel testing on or off. Nil keeps the scheme's or test plan's setting.
    public var parallel: Bool?
    /// Per-test time allowance in seconds (XCTest; Swift Testing uses `.timeLimit`).
    public var testTimeoutSeconds: Int?

    public init(
      retries: Int? = nil, iterations: Int? = nil, untilFailure: Bool = false, parallel: Bool? = nil,
      testTimeoutSeconds: Int? = nil
    ) {
      self.retries = retries
      self.iterations = iterations
      self.untilFailure = untilFailure
      self.parallel = parallel
      self.testTimeoutSeconds = testTimeoutSeconds
    }

    public struct InvalidError: Error, CustomStringConvertible {
      public let description: String
    }

    /// The xcodebuild arguments for these options.
    public func arguments() throws -> [String] {
      var args: [String] = []
      if let retries, retries > 0 {
        if iterations != nil || untilFailure {
          throw InvalidError(description: "retries can't be combined with iterations or untilFailure")
        }
        args += ["-retry-tests-on-failure", "-test-iterations", String(retries + 1)]
      }
      if untilFailure { args.append("-run-tests-until-failure") }
      if let iterations {
        guard iterations > 0 else { throw InvalidError(description: "iterations must be at least 1") }
        if iterations > 1 { args += ["-test-iterations", String(iterations)] }
      }
      if let parallel { args += ["-parallel-testing-enabled", parallel ? "YES" : "NO"] }
      if let testTimeoutSeconds {
        guard testTimeoutSeconds > 0 else {
          throw InvalidError(description: "testTimeoutSeconds must be positive")
        }
        args += [
          "-test-timeouts-enabled", "YES",
          "-default-test-execution-time-allowance", String(testTimeoutSeconds),
          "-maximum-test-execution-time-allowance", String(testTimeoutSeconds),
        ]
      }
      return args
    }
  }

  /// Build for testing, then run the tests: the one pipeline behind `test_sim`, `test run`,
  /// `test rerun-failed` and `build_and_test`. A build failure comes back as a failed run with
  /// `buildFailed` set.
  public static func executeTest(
    project: String? = nil,
    scheme: String? = nil,
    simulator: String? = nil,
    configuration: String = "Debug",
    testplan: String? = nil,
    filter: String? = nil,
    filterIDs: [String]? = nil,
    coverage: Bool = false,
    long: Bool = false,
    diagnose: Bool = false,
    simRecovery: SimRecoveryMode = .off,
    timeoutSeconds: TimeInterval? = nil,
    envEntries: [String] = [],
    gate: Bool = false,
    forMode: OutputAudience = .human,
    isolatedSimulator: Bool = false,
    skipBuild: Bool = false,
    testOptions: TestRunOptions = TestRunOptions(),
    includeConsole: Bool = false,
    env: Environment = .live
  ) async throws -> TestExecution {
    let result = try await executeBuildAndTest(
      project: project, scheme: scheme, simulator: simulator, configuration: configuration,
      testplan: testplan, filter: filter, filterIDs: filterIDs, coverage: coverage, long: long,
      diagnose: diagnose, simRecovery: simRecovery, timeoutSeconds: timeoutSeconds,
      envEntries: envEntries, gate: gate, forMode: forMode, isolatedSimulator: isolatedSimulator,
      skipBuild: skipBuild, testOptions: testOptions, includeConsole: includeConsole, env: env)
    if let test = result.testResult { return test }
    return testExecution(fromBuildFailure: result)
  }

  /// True when the last build-for-testing of this project used the same scheme, configuration
  /// and platform and no file in its repo changed since, so its products can be tested as they are.
  public static func lastTestBuildIsCurrent(
    project: String?, scheme: String?, simulator: String?, configuration: String, coverage: Bool = false,
    testplan: String? = nil, testIDs: [String] = [], env: Environment = .live
  ) async -> Bool {
    guard let resolvedProject = try? await env.session.resolveProject(project),
      let resolvedScheme = try? await env.session.resolveScheme(scheme, project: resolvedProject)
    else { return false }
    var destination = (try? await env.session.resolveSimulator(simulator)) ?? simulator ?? ""
    if let resolved = try? await AutoDetect.resolveSimulatorNameAndUDID(destination) {
      destination = resolved.udid
    }
    let key = LastResultStore.testBuildKey(
      scheme: resolvedScheme, configuration: configuration, coverage: coverage,
      physicalDevice: AutoDetect.isPhysicalDeviceUDID(destination), testPlan: testplan)
    let projectDirectory = (resolvedProject as NSString).deletingLastPathComponent
    let root = RepoRoot.discover(from: projectDirectory) ?? projectDirectory
    var targets: [String]?
    if !testIDs.isEmpty {
      let resolved = await resolveFilters(
        testIDs, project: resolvedProject, scheme: resolvedScheme, testplan: testplan, env: env)
      targets = await buildTargets(
        forFilter: resolved, project: resolvedProject, scheme: resolvedScheme, testplan: testplan, env: env)
    }
    return LastResultStore.testBuildIsCurrent(
      project: resolvedProject, key: key, targets: targets, sourceRoot: root)
  }

  /// The test targets a filter needs built, or nil (build them all) when an ID doesn't
  /// start with one of the scheme's or plan's `known` test targets.
  static func buildTargetsForFilter(_ ids: [String], known: [String]) -> [String]? {
    var targets: [String] = []
    for id in ids {
      guard let target = TestIDs.components(id).first, known.contains(target) else { return nil }
      if !targets.contains(target) { targets.append(target) }
    }
    return targets.isEmpty ? nil : targets
  }

  /// `buildTargetsForFilter` with the known targets read from the scheme or test plan.
  static func buildTargets(
    forFilter ids: [String], project: String, scheme: String, testplan: String?, env: Environment
  ) async -> [String]? {
    guard !ids.isEmpty else { return nil }
    let known = await AutoDetect.testTargetNames(project: project, scheme: scheme, testplan: testplan, env: env)
    guard known.exact else { return nil }
    return buildTargetsForFilter(ids, known: known.names)
  }

  /// Compile errors as "xcodebuild" failures, each with its file and line.
  static func buildErrorFailures(_ issues: [BuildIssueObservation]) -> [TestFailureObservation] {
    issues.filter { $0.severity == .error }.map { issue in
      TestFailureObservation(
        testName: "xcodebuild",
        testIdentifier: "xcodebuild",
        message: issue.message,
        source: "build-for-testing",
        messages: [
          FailureMessage(text: issue.message, file: issue.location?.filePath, line: issue.location?.line)
        ]
      )
    }
  }

  /// A failed `TestExecution` describing a build-for-testing failure.
  static func testExecution(fromBuildFailure result: BuildAndTestResult) -> TestExecution {
    var failures = buildErrorFailures(result.buildDiagnostics ?? [])
    if let detail = result.buildFailureDetail, !detail.isEmpty {
      if result.xcforgeTimedOut {
        failures.insert(
          TestFailureObservation(
            testName: "xcodebuild", testIdentifier: "xcodebuild", message: detail,
            source: "build-for-testing.timeout"),
          at: 0)
      } else if failures.isEmpty {
        failures.append(
          TestFailureObservation(
            testName: "xcodebuild", testIdentifier: "xcodebuild", message: detail,
            source: "build-for-testing.stderr"))
      }
    }
    return TestExecution(
      succeeded: false,
      elapsed: result.buildElapsed,
      xcresultPath: result.buildXcresultPath ?? "",
      scheme: result.scheme ?? "",
      simulator: result.simulator ?? "",
      totalTestCount: max(failures.count, 1),
      passedTestCount: 0,
      failedTestCount: failures.count,
      skippedTestCount: 0,
      expectedFailureCount: 0,
      failures: failures,
      deviceName: nil,
      osVersion: nil,
      screenshotPaths: [],
      hasStructuredSummary: false,
      buildFailed: true,
      buildDiagnostics: result.buildDiagnostics,
      hangDiagnosticPath: result.hangDiagnosticPath,
      hangDiagnosticSummary: result.hangDiagnosticSummary,
      xcforgeTimedOut: result.xcforgeTimedOut,
      timeoutDetail: result.xcforgeTimedOut ? result.buildFailureDetail : nil
    )
  }

  /// Result of applying the known-failures gate. `allKnown` is true when every
  /// real test failure (excluding xcodebuild infra failures) is listed in the
  /// registry. `matchedIDs` is the sorted list of registry hits.
  struct GatingOutcome {
    let matchedIDs: [String]
    let allKnown: Bool
    let warning: String?
  }

  static func applyGating(
    gate: Bool, failures: [TestFailureObservation], failedTestCount: Int = -1,
    repoRoot: String
  ) -> GatingOutcome {
    guard gate else { return GatingOutcome(matchedIDs: [], allKnown: false, warning: nil) }
    let loaded = KnownFailuresStore.load(repoRoot: repoRoot)
    let testFailures = failures.filter { $0.testIdentifier != "xcodebuild" }
    // Registry entries may be written with or without the target; compare by test, not by string.
    func known(_ id: String) -> Bool { loaded.ids.contains { TestIDs.same($0, id) } }
    let matched = testFailures.map { $0.testIdentifier }.filter(known)
    let unmatched = testFailures.contains { !known($0.testIdentifier) }
    // `allKnown` requires: every observed test-level failure is in the registry AND
    // the parsed failure list covers the reported failure count. The second clause
    // prevents falsely rescuing a run whose xcresult parse dropped some failures
    // (failedTestCount > matched.count): we never gate what we couldn't see.
    let coversAll = failedTestCount < 0 || matched.count == failedTestCount
    let allKnown = !testFailures.isEmpty && !unmatched && coversAll
    return GatingOutcome(
      matchedIDs: matched.sorted(),
      allKnown: allKnown,
      warning: loaded.warning
    )
  }

  static func persistLastFailures(
    failures: [TestFailureObservation],
    succeeded: Bool,
    scheme: String,
    simulator: String,
    repoRoot: String,
    gateAllKnown: Bool = false,
    forMode: OutputAudience = .human,
    run: LastFailuresStore.RunSettings? = nil
  ) {
    let testFailureIDs =
      failures
      .filter { $0.testIdentifier != "xcodebuild" && $0.testIdentifier != "test_infrastructure" }
      .map { $0.testIdentifier }
    // When gate is on and every observed failure is in the registry, treat the
    // run as green for persistence purposes — otherwise `rerun-failed` would
    // replay gated tests every cycle.
    if testFailureIDs.isEmpty && succeeded {
      LastFailuresStore.clear(at: repoRoot)
      return
    }
    if gateAllKnown {
      LastFailuresStore.clear(at: repoRoot)
      return
    }
    var wrote = true
    if !testFailureIDs.isEmpty {
      wrote = LastFailuresStore.write(
        failures: testFailureIDs, scheme: scheme, simulator: simulator, run: run, at: repoRoot)
    } else {
      // The run failed before any test reported (build error, runner crash, timeout). Record
      // that, so `rerun-failed` refuses instead of replaying an older run's failures.
      let reason =
        failures.first.map { AgentResultProjection.firstLine($0.message) }
        ?? "the run failed before any test reported a result"
      wrote = LastFailuresStore.write(
        failures: [], scheme: scheme, simulator: simulator, run: run, infraFailure: reason, at: repoRoot)
    }
    if !wrote && forMode == .human {
      FileHandle.standardError.write(
        Data("xcforge: failed to write .xcforge/last-failures.json\n".utf8))
    }
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
      // This project's last test run (or failed test build). Never runs the tests itself.
      let resolvedProject = try await env.session.resolveProject(project)
      guard let recorded = LastResultStore.latest(project: resolvedProject, kind: .test) else {
        throw TestDiscoveryError(
          "No test run recorded for \(resolvedProject). Run the tests first (test_sim or `xcforge test run`),"
            + " or pass xcresultPath.")
      }
      resolvedPath = recorded
    }

    var failures: [TestFailureObservation] = []
    if let detailsJSON = await parseTestDetails(resolvedPath, env: env),
      let data = detailsJSON.data(using: .utf8),
      let parsed = parseTestFailures(data)
    {
      failures = parsed
    }

    // A bundle without test failures may be a test build that failed: report its errors.
    var buildFailed = false
    if failures.isEmpty, let buildJSON = await parseBuildResults(resolvedPath, env: env),
      let data = buildJSON.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    {
      let errors = buildErrorFailures(parseBuildIssues(json).issues)
      if !errors.isEmpty {
        buildFailed = true
        failures = errors
      }
    }

    let attachments = failures.isEmpty ? [] : await exportFailureAttachments(resolvedPath, env: env)
    let screenshots = attachments.map { ScreenshotAttachment(testName: $0.test, path: $0.path) }
    let consoleByTest =
      (includeConsole && !failures.isEmpty)
      ? await extractTestConsole(resolvedPath, env: env) : [:]
    failures = attach(attachments: attachments, console: consoleByTest, to: failures)

    return TestFailuresResult(
      failures: failures,
      screenshots: screenshots,
      consoleByTest: consoleByTest,
      xcresultPath: resolvedPath,
      buildFailed: buildFailed
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
    } else if let recent = await findRecentCoverageXcresult(project: project, env: env) {
      // Reuse this project's last test run when it has coverage data
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
    filterIDs: [String]? = nil,
    coverage: Bool = false,
    long: Bool = false,
    diagnose: Bool = false,
    simRecovery: SimRecoveryMode = .off,
    timeoutSeconds: TimeInterval? = nil,
    envEntries: [String] = [],
    gate: Bool = false,
    forMode: OutputAudience = .human,
    isolatedSimulator: Bool = false,
    skipBuild: Bool = false,
    testOptions: TestRunOptions = TestRunOptions(),
    includeConsole: Bool = false,
    env: Environment = .live
  ) async throws -> BuildAndTestResult {
    if isolatedSimulator {
      let source = try await env.session.resolveSimulator(simulator)
      return try await IsolatedSimulator.with(source: source, env: env) { udid in
        try await executeBuildAndTest(
          project: project, scheme: scheme, simulator: udid, configuration: configuration,
          testplan: testplan, filter: filter, filterIDs: filterIDs, coverage: coverage, long: long,
          diagnose: diagnose, simRecovery: simRecovery, timeoutSeconds: timeoutSeconds,
          envEntries: envEntries, gate: gate, forMode: forMode, isolatedSimulator: false,
          skipBuild: skipBuild, testOptions: testOptions, includeConsole: includeConsole, env: env)
      }
    }
    let testArguments = try testOptions.arguments()
    let resolvedProject = try await env.session.resolveProject(project)
    let resolvedScheme = try await env.session.resolveScheme(scheme, project: resolvedProject)
    let resolvedSimulator = try await env.session.resolveSimulator(simulator)
    // Last failures and the known-failures registry live in the repo of the project under
    // test, which is not necessarily the one the server was started in.
    let cwd = env.currentDirectoryPath()
    let projectDirectory = (resolvedProject as NSString).deletingLastPathComponent
    let repoRoot =
      RepoRoot.discover(from: projectDirectory) ?? AutoDetect.repoRoot(from: cwd) ?? cwd
    let childEnvironment = try buildTestRunnerEnvironment(
      userEntries: envEntries, repoRoot: repoRoot)
    let runSettings = LastFailuresStore.RunSettings(
      project: resolvedProject, testPlan: testplan, configuration: configuration,
      env: envEntries.isEmpty ? nil : envEntries)

    // Resolve simulator to UDID for precise id= destination
    let udidForDest: String
    if let resolved = try? await AutoDetect.resolveSimulatorNameAndUDID(resolvedSimulator) {
      udidForDest = resolved.udid
    } else {
      udidForDest = resolvedSimulator
    }

    var recoveryAttempts = 0
    var recoveryReason: String?
    var recoveryFailureReason: String?
    var simHealthCheckDetail: String?

    // Pre-build simulator health probe (only when auto)
    if simRecovery != .off {
      let outcome = await SimulatorRecovery.probeAndRecover(
        udid: udidForDest, mode: simRecovery, env: env)
      simHealthCheckDetail = outcome.healthCheckDetail
      if outcome.fired {
        recoveryAttempts += 1
        recoveryReason = outcome.reason
        recoveryFailureReason = outcome.failureReason
        Log.warn("Pre-build sim recovery fired: \(outcome.reason ?? "unknown")")
        if let failure = outcome.failureReason {
          Log.warn("Sim recovery failed: \(failure)")
        }
      }
    }

    // A pre-split list (rerun-failed) is kept as is, so IDs with commas inside their
    // arguments are never re-split.
    var requestedIDs = filterIDs ?? []
    if requestedIDs.isEmpty, let filter { requestedIDs = splitFilterList(filter) }
    let resolvedFilter: String?
    if !requestedIDs.isEmpty {
      let resolved = await resolveFilters(
        requestedIDs, project: resolvedProject, scheme: resolvedScheme, testplan: testplan, env: env)
      resolvedFilter = resolved.joined(separator: ",")
    } else {
      resolvedFilter = nil
    }

    let destination = await AutoDetect.buildDestination(udidForDest)
    let testBuildKey = LastResultStore.testBuildKey(
      scheme: resolvedScheme, configuration: configuration, coverage: coverage,
      physicalDevice: AutoDetect.isPhysicalDeviceUDID(udidForDest), testPlan: testplan)
    // A filtered run builds only the test targets it needs.
    var filterTargets: [String]?
    if let resolvedFilter {
      filterTargets = await buildTargets(
        forFilter: splitFilterList(resolvedFilter), project: resolvedProject, scheme: resolvedScheme,
        testplan: testplan, env: env)
    }
    let targetsToBuild = filterTargets

    // --- Inner helper: run the build-for-testing phase ---
    func runBuildPhase(diagnose: Bool) async throws -> (
      ShellResult, String, DiagnosticSnapshot.Result?
    ) {
      let resultPath = xcresultPath(prefix: "build-for-testing")
      return try await runBuildForTesting(
        project: resolvedProject, scheme: resolvedScheme, destination: destination,
        configuration: configuration, coverage: coverage, resultPath: resultPath,
        testplan: testplan, targets: targetsToBuild,
        long: long, diagnose: diagnose, udid: udidForDest, timeoutOverride: timeoutSeconds,
        childEnvironment: childEnvironment,
        env: env
      )
    }

    // --- Inner helper: run the test-without-building phase ---
    func runTestPhase(diagnose: Bool) async throws -> (
      ShellResult, String, DiagnosticSnapshot.Result?
    ) {
      let resultPath = xcresultPath(prefix: "test")
      return try await runTestWithoutBuilding(
        project: resolvedProject, scheme: resolvedScheme, destination: destination,
        configuration: configuration, testplan: testplan, filter: resolvedFilter,
        coverage: coverage, resultPath: resultPath,
        long: long, diagnose: diagnose, udid: udidForDest, timeoutOverride: timeoutSeconds,
        childEnvironment: childEnvironment, extraTestArguments: testArguments,
        env: env
      )
    }

    // --- Build phase ---
    var buildElapsed = "0.0"
    if !skipBuild {
      var buildStart = CFAbsoluteTimeGetCurrent()
      var (buildShellResult, buildResultPath, buildDiagResult) = try await runBuildPhase(
        diagnose: diagnose)
      buildElapsed = String(format: "%.1f", CFAbsoluteTimeGetCurrent() - buildStart)

      // Auto-retry on deadlock: only when watchdog fired (diagResult != nil) AND shell timeout (-1)
      if buildDiagResult != nil && buildShellResult.exitCode == -1 && recoveryAttempts < 1 {
        let buildVerdict = buildDiagResult.map {
          DiagnosticSnapshot.classifyVerdict(snapshotPath: $0.filePath)
        }
        let verdict = buildVerdict == .timeout ? nil : buildVerdict
        if verdict != nil {
          // Kill the stuck xcodebuild tree by PID before retrying
          let xcodebuildPid = extractXcodebuildPid(from: buildDiagResult)
          await killXcodebuildTree(pid: xcodebuildPid, env: env)

          // Run sim recovery before retry
          let retryOutcome = await SimulatorRecovery.probeAndRecover(
            udid: udidForDest, mode: simRecovery, env: env)
          recoveryAttempts += 1
          recoveryReason = verdict?.rawValue ?? retryOutcome.reason
          recoveryFailureReason = retryOutcome.failureReason
          if simHealthCheckDetail == nil { simHealthCheckDetail = retryOutcome.healthCheckDetail }

          buildStart = CFAbsoluteTimeGetCurrent()
          let retried = try await runBuildPhase(diagnose: true)
          buildShellResult = retried.0
          buildResultPath = retried.1
          buildDiagResult = retried.2
          buildElapsed = String(format: "%.1f", CFAbsoluteTimeGetCurrent() - buildStart)
        }
      }

      // Build failure (real, not a timeout hang)
      if !buildShellResult.succeeded {
        var issues: [BuildIssueObservation] = []

        if let buildJSON = await parseBuildResults(buildResultPath, env: env),
          let data = buildJSON.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
          let parsed = parseBuildIssues(json)
          issues = parsed.issues
        }

        if issues.isEmpty {
          issues = fallbackBuildIssues(stderr: Xcodebuild.combinedOutput(buildShellResult))
        }

        let tail = String(buildShellResult.stderr.suffix(2000)).trimmingCharacters(
          in: .whitespacesAndNewlines)
        let detail = Xcodebuild.timeoutExplanation(buildShellResult) ?? (tail.isEmpty ? nil : tail)
        persistLastFailures(
          failures: [], succeeded: false, scheme: resolvedScheme, simulator: resolvedSimulator,
          repoRoot: repoRoot, forMode: forMode, run: runSettings)

        return BuildAndTestResult(
          phase: "build",
          buildSucceeded: false,
          buildElapsed: buildElapsed,
          buildDiagnostics: issues.isEmpty ? nil : issues,
          testResult: nil,
          hangDiagnosticPath: buildDiagResult?.filePath,
          recoveryAttempts: recoveryAttempts,
          recoveryReason: recoveryReason,
          recoveryFailureReason: recoveryFailureReason,
          simHealthCheckDetail: simHealthCheckDetail,
          xcforgeTimedOut: buildShellResult.exitCode == -1,
          project: resolvedProject,
          scheme: resolvedScheme,
          simulator: resolvedSimulator,
          buildXcresultPath: buildResultPath,
          hangDiagnosticSummary: buildDiagResult?.summaryLine,
          buildFailureDetail: detail
        )
      }
      LastResultStore.recordTestBuild(project: resolvedProject, key: testBuildKey, targets: targetsToBuild)
    }

    // --- Test phase ---
    var testStart = CFAbsoluteTimeGetCurrent()
    var (testShellResult, testResultPath, testDiagResult):
      (
        ShellResult, String, DiagnosticSnapshot.Result?
      )
    do {
      let result = try await runTestPhase(diagnose: diagnose)
      testShellResult = result.0
      testResultPath = result.1
      testDiagResult = result.2
    } catch {
      let failure = TestFailureObservation(
        testName: "test_infrastructure",
        testIdentifier: "test_infrastructure",
        message: "Test execution failed: \(error)",
        source: "xcforge"
      )
      persistLastFailures(
        failures: [failure], succeeded: false, scheme: resolvedScheme, simulator: resolvedSimulator,
        repoRoot: repoRoot, forMode: forMode, run: runSettings)
      return BuildAndTestResult(
        phase: "test",
        buildSucceeded: true,
        buildElapsed: buildElapsed,
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
          failures: [failure],
          deviceName: nil,
          osVersion: nil,
          screenshotPaths: [],
          hasStructuredSummary: false,
          buildFailed: false,
          buildDiagnostics: nil
        ),
        hangDiagnosticPath: nil,
        recoveryAttempts: recoveryAttempts,
        recoveryReason: recoveryReason,
        recoveryFailureReason: recoveryFailureReason,
        simHealthCheckDetail: simHealthCheckDetail,
        project: resolvedProject,
        scheme: resolvedScheme,
        simulator: resolvedSimulator
      )
    }

    // Auto-retry on test-phase deadlock: only when watchdog fired AND shell timeout (-1) AND no prior retry
    if testDiagResult != nil && testShellResult.exitCode == -1 && recoveryAttempts < 1 {
      let testVerdict = testDiagResult.map {
        DiagnosticSnapshot.classifyVerdict(snapshotPath: $0.filePath)
      }
      let verdict = testVerdict == .timeout ? nil : testVerdict
      if verdict != nil {
        let xcodebuildPid = extractXcodebuildPid(from: testDiagResult)
        await killXcodebuildTree(pid: xcodebuildPid, env: env)

        let retryOutcome = await SimulatorRecovery.probeAndRecover(
          udid: udidForDest, mode: simRecovery, env: env)
        if recoveryReason == nil { recoveryReason = verdict?.rawValue ?? retryOutcome.reason }
        if recoveryFailureReason == nil { recoveryFailureReason = retryOutcome.failureReason }
        if simHealthCheckDetail == nil { simHealthCheckDetail = retryOutcome.healthCheckDetail }
        recoveryAttempts += 1

        testStart = CFAbsoluteTimeGetCurrent()
        if let retried = try? await runTestPhase(diagnose: true) {
          testShellResult = retried.0
          testResultPath = retried.1
          testDiagResult = retried.2
        }
      }
    }

    let testElapsed = String(format: "%.1f", CFAbsoluteTimeGetCurrent() - testStart)

    let testExecution = await buildTestExecutionResult(
      shellResult: testShellResult,
      resultPath: testResultPath,
      diagResult: testDiagResult,
      resolvedScheme: resolvedScheme,
      resolvedSimulator: resolvedSimulator,
      elapsed: testElapsed,
      filterRequested: resolvedFilter != nil,
      gate: gate,
      forMode: forMode,
      repoRoot: repoRoot,
      runSettings: runSettings,
      skippedBuild: skipBuild,
      includeConsole: includeConsole,
      env: env
    )
    return BuildAndTestResult(
      phase: "test",
      buildSucceeded: true,
      buildElapsed: buildElapsed,
      buildDiagnostics: nil,
      testResult: testExecution,
      hangDiagnosticPath: testExecution.hangDiagnosticPath,
      recoveryAttempts: recoveryAttempts,
      recoveryReason: recoveryReason,
      recoveryFailureReason: recoveryFailureReason,
      simHealthCheckDetail: simHealthCheckDetail,
      knownFailures: testExecution.knownFailures,
      project: resolvedProject,
      scheme: resolvedScheme,
      simulator: resolvedSimulator,
      skippedBuild: skipBuild
    )
  }

  /// Extract the xcodebuild PID from a diagnostic snapshot result (reads the snapshot file).
  private static func extractXcodebuildPid(from diagResult: DiagnosticSnapshot.Result?) -> String? {
    guard let diagResult else { return nil }
    let content = (try? String(contentsOfFile: diagResult.filePath, encoding: .utf8)) ?? ""
    for line in content.split(separator: "\n") {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.hasPrefix("xcodebuild PID: ") {
        let pid = trimmed.dropFirst("xcodebuild PID: ".count)
        return pid == "not found" ? nil : String(pid)
      }
    }
    return nil
  }

  /// Kill the xcodebuild process tree by PID.
  private static func killXcodebuildTree(pid: String?, env: Environment) async {
    // The PID comes from a snapshot matched on this run's own result bundle path, so it is
    // never another session's xcodebuild. Without one there is nothing safe to kill.
    guard let pid else { return }
    _ = try? await env.shell.run("/usr/bin/pkill", arguments: ["-9", "-P", pid], timeout: 5)
    _ = try? await env.shell.run("/bin/kill", arguments: ["-9", pid], timeout: 5)
  }

  /// Extract up to 10 slowest test cases from test-results JSON, sorted by duration descending.
  private static func parseSlowTests(_ json: [String: Any]) -> [SlowTest] {
    var entries: [(name: String, duration: Double)] = []

    func collectDurations(from node: [String: Any]) {
      let nodeType = (node["nodeType"] as? String) ?? ""
      if nodeType == "Test Case" {
        if let duration = node["duration"] as? Double,
          let name = node["name"] as? String
        {
          entries.append((name: name, duration: duration))
        }
      }
      if let children = node["children"] as? [[String: Any]] {
        for child in children { collectDurations(from: child) }
      }
    }

    if let testNodes = json["testNodes"] as? [[String: Any]] {
      for node in testNodes { collectDurations(from: node) }
    }

    return
      entries
      .sorted { $0.duration > $1.duration }
      .prefix(10)
      .map { SlowTest(testName: $0.name, elapsedSeconds: $0.duration) }
  }

  // MARK: - TestExecution builder

  /// Parse xcresult and build a `TestExecution` from shell result + parsed data.
  private static func buildTestExecutionResult(
    shellResult: ShellResult,
    resultPath: String,
    diagResult: DiagnosticSnapshot.Result?,
    resolvedScheme: String,
    resolvedSimulator: String,
    elapsed: String,
    filterRequested: Bool,
    gate: Bool = false,
    forMode: OutputAudience = .human,
    repoRoot: String,
    runSettings: LastFailuresStore.RunSettings? = nil,
    skippedBuild: Bool = false,
    includeConsole: Bool = false,
    env: Environment
  ) async -> TestExecution {
    let xcforgeTimedOut = shellResult.exitCode == -1

    var parsedSummary: ParsedTestSummary?
    var xcresultParseError: String?
    if let summaryJSON = await parseTestSummary(resultPath, env: env),
      let data = summaryJSON.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    {
      parsedSummary = Self.parseTestSummary(json)
    } else if !xcforgeTimedOut {
      // Parse failed and this wasn't a timeout kill — surface the exit code for caller diagnosis
      xcresultParseError =
        "xcresulttool failed to parse \(resultPath) (xcodebuild exit: \(shellResult.exitCode))"
    }

    var failures: [TestFailureObservation] = []
    var slowestTests: [SlowTest] = []
    var flakyTests: [String] = []
    if let detailsJSON = await parseTestDetails(resultPath, env: env),
      let data = detailsJSON.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    {
      failures = parseTestFailures(json)
      slowestTests = parseSlowTests(json)
      flakyTests = parseFlakyTests(json)
    }
    if failures.isEmpty {
      failures = parsedSummary?.failures ?? []
    }

    let hasFailures = (parsedSummary?.failedTestCount ?? failures.count) > 0
    var screenshots: [ScreenshotAttachment] = []
    if hasFailures {
      let attachments = await exportFailureAttachments(resultPath, env: env)
      screenshots = attachments.map { ScreenshotAttachment(testName: $0.test, path: $0.path) }
      let consoleByTest = includeConsole ? await extractTestConsole(resultPath, env: env) : [:]
      failures = attach(attachments: attachments, console: consoleByTest, to: failures)
    }

    // Failing tests also exit non-zero; only a run that produced no test results and
    // reports build errors failed to build.
    var buildDiagnostics: [BuildIssueObservation]?
    if !shellResult.succeeded && parsedSummary == nil {
      if let buildJSON = await parseBuildResults(resultPath, env: env),
        let data = buildJSON.data(using: .utf8),
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
      {
        let parsed = parseBuildIssues(json)
        if !parsed.issues.isEmpty { buildDiagnostics = parsed.issues }
      }
      if buildDiagnostics == nil {
        buildDiagnostics = fallbackBuildIssues(stderr: Xcodebuild.combinedOutput(shellResult))
        if buildDiagnostics?.isEmpty == true { buildDiagnostics = nil }
      }
    }
    let buildFailed = buildDiagnostics?.contains { $0.severity == .error } ?? false
    if buildFailed { failures = buildErrorFailures(buildDiagnostics ?? []) }

    if !shellResult.succeeded && failures.isEmpty {
      let errorLines = shellResult.stderr.split(separator: "\n")
        .filter { $0.contains(": error:") || $0.contains(" failed") || $0.contains("FAILED") }
        .prefix(20)
      if errorLines.isEmpty {
        let tail = String(shellResult.stderr.suffix(2000)).trimmingCharacters(
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
      if skippedBuild && parsedSummary == nil {
        failures.insert(
          TestFailureObservation(
            testName: "xcodebuild", testIdentifier: "xcodebuild",
            message:
              "The build was skipped and the tests didn't run; the last build's products may be missing."
              + " Run again with the build.",
            source: "xcforge"),
          at: 0)
      }
    }

    let totalTestCount =
      parsedSummary?.totalTestCount ?? max(failures.count, shellResult.succeeded ? 0 : 1)
    let failedTestCount = parsedSummary?.failedTestCount ?? failures.count
    let passedTestCount = parsedSummary?.passedTestCount ?? 0
    let skippedTestCount = parsedSummary?.skippedTestCount ?? 0
    let expectedFailureCount = parsedSummary?.expectedFailureCount ?? 0
    // Zero tests ran (filter or test plan selected nothing) → failure, so a run that tested
    // nothing never reads as a pass. Without a parsed summary the count is unknown, not zero.
    let zeroMatchWithFilter = totalTestCount == 0 && (filterRequested || parsedSummary != nil)

    let gating = applyGating(
      gate: gate, failures: failures, failedTestCount: failedTestCount, repoRoot: repoRoot)
    let rawSucceeded = shellResult.succeeded && failedTestCount == 0 && !zeroMatchWithFilter
    let gatedSucceeded = gate ? (rawSucceeded || gating.allKnown) : rawSucceeded

    if gate, let warning = gating.warning, forMode == .human {
      FileHandle.standardError.write(Data("xcforge: \(warning)\n".utf8))
    }

    persistLastFailures(
      failures: failures,
      succeeded: rawSucceeded,
      scheme: resolvedScheme,
      simulator: resolvedSimulator,
      repoRoot: repoRoot,
      gateAllKnown: gate && gating.allKnown,
      forMode: forMode,
      run: runSettings)

    return TestExecution(
      succeeded: gatedSucceeded,
      elapsed: elapsed,
      xcresultPath: resultPath,
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
      buildDiagnostics: buildDiagnostics,
      hangDiagnosticPath: diagResult?.filePath,
      hangDiagnosticSummary: diagResult?.summaryLine,
      xcresultParseError: xcresultParseError,
      xcforgeTimedOut: xcforgeTimedOut,
      slowestTests: slowestTests,
      knownFailures: (gate && !gating.matchedIDs.isEmpty) ? gating.matchedIDs : nil,
      flakyTests: flakyTests,
      timeoutDetail: Xcodebuild.timeoutExplanation(shellResult)
    )
  }

  // MARK: - list_tests Execution

  public static func executeListTests(
    project: String? = nil,
    scheme: String? = nil,
    simulator: String? = nil,
    testplan: String? = nil,
    withoutBuilding: Bool = false,
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

    // xcodebuild test -enumerate-tests builds for testing then lists tests without running
    // them. The JSON output covers XCTest and Swift Testing alike; the text output below is
    // only a fallback for Xcode versions that ignore the format flags.
    let jsonPath = XcodebuildOptions.uniqueArtifactPath(prefix: "tests", extension: "json")
    defer { try? FileManager.default.removeItem(atPath: jsonPath) }
    var enumerateArgs = [
      projectFlag, resolvedProject,
      "-scheme", resolvedScheme,
      "-destination", destination,
      "-skipMacroValidation",
    ]
    if let plan = await env.session.resolveTestPlan(testplan) {
      enumerateArgs += ["-testPlan", plan]
    }
    // `withoutBuilding` lists from the products of the last build-for-testing instead of
    // building again. Building uses the same flags as every other build, so it doesn't
    // invalidate them.
    if !withoutBuilding { enumerateArgs += compileFlags }
    enumerateArgs += [
      "-enumerate-tests",
      "-test-enumeration-style", "flat",
      "-test-enumeration-format", "json",
      "-test-enumeration-output-path", jsonPath,
    ]
    enumerateArgs += withoutBuilding ? ["test-without-building"] : ["test"] + compileSettings
    let enumerateResult = try await Xcodebuild.run(
      enumerateArgs, timeout: await resolveTestTimeout(long: true, env: env), env: env)

    if let data = FileManager.default.contents(atPath: jsonPath),
      let parsed = parseTestEnumerationJSON(data), !parsed.enabled.isEmpty || !parsed.disabled.isEmpty
    {
      let tests = parsed.enabled.compactMap(testIdentifier(from:))
      return ListTestsResult(
        tests: tests,
        targetCount: Set(tests.map(\.target)).count,
        classCount: Set(tests.map { "\($0.target)/\($0.className)" }).count,
        testCount: tests.count,
        disabledTestCount: parsed.disabled.count
      )
    }

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
          "xcodebuild listed no tests, but the project has test targets: \(testTargets.joined(separator: ", ")). "
            + "Check that the scheme's test action or test plan includes them."
        )
      }
      throw TestDiscoveryError("No tests found for scheme '\(resolvedScheme)'.")
    }

    return ListTestsResult(
      tests: tests,
      targetCount: targets.count,
      classCount: classes.count,
      testCount: tests.count
    )
  }

  /// Collect test identifiers from `-test-enumeration-format json` output. Tolerant of the
  /// exact layout: any object with an `identifier` string counts, and it is disabled when
  /// it sits under a key containing "disabled".
  static func parseTestEnumerationJSON(_ data: Data) -> (enabled: [String], disabled: [String])? {
    guard let root = try? JSONSerialization.jsonObject(with: data) else { return nil }
    var enabled: [String] = []
    var disabled: [String] = []
    var seen = Set<String>()
    func walk(_ node: Any, disabledBranch: Bool) {
      if let dict = node as? [String: Any] {
        if let id = dict["identifier"] as? String, seen.insert(id + "|\(disabledBranch)").inserted {
          if disabledBranch { disabled.append(id) } else { enabled.append(id) }
        }
        for (key, value) in dict where key != "identifier" {
          walk(value, disabledBranch: disabledBranch || key.lowercased().contains("disabled"))
        }
      } else if let array = node as? [Any] {
        for item in array { walk(item, disabledBranch: disabledBranch) }
      }
    }
    walk(root, disabledBranch: false)
    return (enabled, disabled)
  }

  /// Split `Target/Suite[/Nested]/test()` into its parts. The full identifier is kept exactly
  /// as xcodebuild printed it, which is the form `-only-testing` accepts.
  static func testIdentifier(from id: String) -> TestIdentifier? {
    let parts = id.split(separator: "/").map(String.init)
    guard parts.count >= 2 else { return nil }
    var method = parts.count >= 3 ? parts[parts.count - 1] : ""
    if method.hasSuffix("()") { method = String(method.dropLast(2)) }
    let className = parts.count >= 3 ? parts[1..<(parts.count - 1)].joined(separator: "/") : parts[1]
    return TestIdentifier(
      target: parts[0], className: className, methodName: method, fullIdentifier: id)
  }

  // MARK: - Tool Implementations

  static func testSim(_ args: [String: Value]?, env: Environment) async -> CallTool.Result {
    switch ToolInput.decode(TestSimInput.self, from: args) {
    case .failure(let err): return err
    case .success(let input):
      // Resolve simRecovery mode (default: off for test_sim)
      let recoveryMode: SimRecoveryMode
      do {
        recoveryMode = try SimRecoveryMode.parse(input.simRecovery)
      } catch {
        return .fail("\(error)")
      }

      // Build preamble: testplan visibility + filter/testplan conflict warning
      let testplan = await env.session.resolveTestPlan(input.testplan)
      var preamble = ""
      if let tp = testplan {
        preamble += "Testplan: \(tp)\n"
      } else {
        preamble += "Testplan: (none — all tests)\n"
      }
      if testplan != nil && input.filter != nil {
        preamble +=
          "Note: filter and testplan are both set. -only-testing overrides the testplan's test selection."
          + " Tests not matching the filter will be skipped regardless of testplan.\n"
      }

      let forMode: OutputAudience =
        (input.for?.lowercased() == "agent") ? .agent : .human
      do {
        let execution = try await executeTest(
          project: input.project,
          scheme: input.scheme,
          simulator: input.simulator,
          configuration: await env.session.resolveConfiguration(input.configuration),
          testplan: testplan,
          filter: input.filter,
          coverage: input.coverage ?? false,
          long: input.long ?? false,
          diagnose: input.diagnose ?? false,
          simRecovery: recoveryMode,
          timeoutSeconds: input.timeoutSeconds.map { TimeInterval($0) },
          envEntries: input.env ?? [],
          gate: input.gate ?? false,
          forMode: forMode,
          isolatedSimulator: input.isolatedSimulator ?? false,
          skipBuild: input.skipBuild ?? false,
          testOptions: TestRunOptions(
            retries: input.retries, iterations: input.iterations, untilFailure: input.untilFailure ?? false,
            parallel: input.parallel, testTimeoutSeconds: input.testTimeoutSeconds),
          includeConsole: input.includeConsole ?? false,
          env: env
        )

        if forMode == .agent {
          let json = (try? WorkflowJSONRenderer.renderTestJSON(execution, forAgent: true)) ?? "{}"
          return execution.succeeded ? .ok(json) : .fail(json)
        }

        // Format result
        var lines = [preamble.trimmingCharacters(in: .newlines)]

        if execution.buildFailed {
          lines.append("TEST TARGET BUILD FAILED in \(execution.elapsed)s")
          if !execution.failures.isEmpty {
            lines.append("Build errors:")
            lines += TestFailureText.buildErrorLines(execution.failures)
          }
          lines.append("xcresult: \(execution.xcresultPath)")
          if let diagPath = execution.hangDiagnosticPath {
            lines.append("Diagnostic snapshot: \(diagPath)")
            if let summary = execution.hangDiagnosticSummary {
              lines.append("Summary: \(summary)")
            }
          }
          return .fail(lines.joined(separator: "\n"))
        }

        let icon = execution.succeeded ? "PASSED" : "FAILED"
        if execution.totalTestCount == 0 {
          lines.append("No tests ran (\(execution.elapsed)s): the filter, scheme or test plan selected none")
        } else {
          lines.append("Tests \(icon) in \(execution.elapsed)s")
          lines.append(
            "  Total: \(execution.totalTestCount)  Passed: \(execution.passedTestCount)"
              + "  Failed: \(execution.failedTestCount)  Skipped: \(execution.skippedTestCount)"
          )
        }

        if !execution.failures.isEmpty {
          lines.append("\nFailures:")
          lines += TestFailureText.lines(execution.failures)
        }
        if !execution.flakyTests.isEmpty {
          lines.append("Flaky (failed, then passed on retry): \(execution.flakyTests.joined(separator: ", "))")
        }

        if execution.totalTestCount == 0, let f = input.filter {
          let hint = await zeroMatchHint(
            filter: f, project: input.project, scheme: input.scheme,
            simulator: input.simulator, testplan: testplan, env: env
          )
          lines.append(hint)
        }

        if let deviceName = execution.deviceName {
          lines.append("Device: \(deviceName) (\(execution.osVersion ?? ""))")
        }

        lines.append("xcresult: \(execution.xcresultPath)")
        if let diagPath = execution.hangDiagnosticPath {
          lines.append("Diagnostic snapshot: \(diagPath)")
          if let summary = execution.hangDiagnosticSummary {
            lines.append("Summary: \(summary)")
          }
        }

        let zeroMatchWithFilter =
          execution.totalTestCount == 0 && (input.filter != nil || execution.hasStructuredSummary)
        let text = lines.joined(separator: "\n")
        return (execution.succeeded && !zeroMatchWithFilter) ? .ok(text) : .fail(text)
      } catch {
        return .fail("Test error: \(error)")
      }
    }
  }

  static func testFailures(_ args: [String: Value]?, env: Environment) async -> CallTool.Result {
    switch ToolInput.decode(TestFailuresInput.self, from: args) {
    case .failure(let err): return err
    case .success(let input):
      do {
        let result = try await extractFailures(
          xcresultPath: input.xcresult_path, project: input.project, scheme: input.scheme,
          simulator: input.simulator, includeConsole: input.include_console ?? false, env: env)
        return formatTestFailures(result)
      } catch {
        return .fail("\(error)")
      }
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

      let configuration = await env.session.resolveConfiguration(input.configuration)
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

      let configuration = await env.session.resolveConfiguration(input.configuration)
      let testplan = await env.session.resolveTestPlan(input.testplan)
      let recoveryMode: SimRecoveryMode
      do {
        recoveryMode = try SimRecoveryMode.parse(input.simRecovery)
      } catch {
        return .fail("\(error)")
      }
      let forMode: OutputAudience =
        (input.for?.lowercased() == "agent") ? .agent : .human
      do {
        let result = try await executeBuildAndTest(
          project: project,
          scheme: scheme,
          simulator: simulator,
          configuration: configuration,
          testplan: testplan,
          filter: input.filter,
          coverage: input.coverage ?? false,
          long: input.long ?? false,
          diagnose: input.diagnose ?? false,
          simRecovery: recoveryMode,
          timeoutSeconds: input.timeoutSeconds.map { TimeInterval($0) },
          envEntries: input.env ?? [],
          gate: input.gate ?? false,
          forMode: forMode,
          isolatedSimulator: input.isolatedSimulator ?? false,
          skipBuild: input.skipBuild ?? false,
          testOptions: TestRunOptions(
            retries: input.retries, iterations: input.iterations, untilFailure: input.untilFailure ?? false,
            parallel: input.parallel, testTimeoutSeconds: input.testTimeoutSeconds),
          includeConsole: input.includeConsole ?? false,
          env: env
        )
        if forMode == .agent {
          let json = (try? WorkflowJSONRenderer.renderTestJSON(result, forAgent: true)) ?? "{}"
          let ok = result.buildSucceeded && (result.testResult?.succeeded ?? false)
          return ok ? .ok(json) : .fail(json)
        }
        // Generate zero-match hint before formatting (avoids Content extraction)
        var zeroHint = ""
        if let testResult = result.testResult,
          testResult.totalTestCount == 0,
          let f = input.filter
        {
          zeroHint = await zeroMatchHint(
            filter: f, project: input.project, scheme: input.scheme,
            simulator: input.simulator, testplan: testplan, env: env
          )
        }

        return formatBuildAndTest(
          result, testplan: testplan, filter: input.filter, suffix: zeroHint)
      } catch {
        return .fail("build_and_test error: \(error)")
      }
    }
  }

  static func testPlanInspect(_ args: [String: Value]?, env: Environment) async -> CallTool.Result {
    struct Input: Decodable {
      let plan: String
      let project: String?
    }
    switch ToolInput.decode(Input.self, from: args) {
    case .failure(let err): return err
    case .success(let input):
      let resolvedProject: String
      do {
        resolvedProject = try await env.session.resolveProject(input.project)
      } catch {
        return .fail("\(error)")
      }
      do {
        let summary = try await TestPlanInspector.inspectTestPlan(
          name: input.plan, project: resolvedProject, env: env)
        return .ok(summary)
      } catch {
        return .fail("\(error)")
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
          testplan: input.testplan,
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
      if let diagPath = result.hangDiagnosticPath {
        lines.append("Diagnostic snapshot: \(diagPath)")
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
        if let diagPath = result.hangDiagnosticPath {
          lines.append("Diagnostic snapshot: \(diagPath)")
        }
        return .fail(lines.joined(separator: "\n") + suffix)
      }
      lines.append(
        result.skippedBuild ? "Build: skipped (tested the last build)" : "Build: OK (\(result.buildElapsed)s)")
      if test.totalTestCount == 0 {
        lines.append("No tests ran (\(test.elapsed)s): the filter, scheme or test plan selected none")
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
        lines += TestFailureText.lines(test.failures)
      }
      if !test.flakyTests.isEmpty {
        lines.append("Flaky (failed, then passed on retry): \(test.flakyTests.joined(separator: ", "))")
      }
      lines.append("")
      lines.append("xcresult: \(test.xcresultPath)")
      if let diagPath = result.hangDiagnosticPath {
        lines.append("Diagnostic snapshot: \(diagPath)")
        if let summary = test.hangDiagnosticSummary {
          lines.append("Summary: \(summary)")
        }
      }
      let text = lines.joined(separator: "\n") + suffix
      // Filter matched nothing → treat as failure so agents don't assume tests passed
      let zeroMatchWithFilter =
        test.totalTestCount == 0 && (filter != nil || test.hasStructuredSummary)
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
    if let disabled = result.disabledTestCount, disabled > 0 {
      lines.insert("\(disabled) more disabled by the scheme or test plan", at: lines.count - 1)
    }

    // Group by target/class for readability
    var grouped: [String: [String: [String]]] = [:]  // target -> class -> methods
    for test in tests {
      // The last component as xcodebuild names it, `()` included, so it can be pasted back.
      let method = TestIDs.components(test.fullIdentifier).last ?? test.methodName
      grouped[test.target, default: [:]][test.className, default: []].append(method)
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
    lines.append("  Full:   filter: \"Target/Suite/test()\"")
    lines.append("  Suite:  filter: \"Suite\" or \"Suite/test()\" (the target is added)")

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

  static func formatTestFailures(_ result: TestFailuresResult) -> CallTool.Result {
    if result.failures.isEmpty {
      return .ok("No test failures found.\nxcresult: \(result.xcresultPath)")
    }
    if result.buildFailed {
      var lines = ["The last test run failed to build, so no test ran. Build errors:"]
      lines += TestFailureText.buildErrorLines(result.failures)
      lines.append("xcresult: \(result.xcresultPath)")
      return .fail(lines.joined(separator: "\n"))
    }
    var lines = ["\(result.failures.count) test failure(s):", ""]
    lines += TestFailureText.lines(result.failures, indent: "")
    // Attachments that couldn't be tied to a failure are still worth a path.
    let attached = Set(result.failures.flatMap { $0.attachments ?? [] })
    let loose = result.screenshots.map(\.path).filter { !attached.contains($0) }
    if !loose.isEmpty {
      lines.append("")
      lines.append("Other failure attachments (\(loose.count)):")
      lines += loose.prefix(20).map { "  \($0)" }
    }
    lines.append("")
    lines.append("xcresult: \(result.xcresultPath)")
    return .fail(lines.joined(separator: "\n"))
  }

  private static func parseTestSummary(_ json: [String: Any]) -> ParsedTestSummary {
    let failures = ((json["testFailures"] as? [[String: Any]]) ?? []).map { failure in
      let text = failure["failureText"] as? String
      return TestFailureObservation(
        testName: (failure["testName"] as? String) ?? "?",
        testIdentifier: TestIDs.canonical(
          target: failure["targetName"] as? String,
          identifier: (failure["testIdentifierString"] as? String)
            ?? (failure["testName"] as? String) ?? "?"),
        message: text ?? "Test failed without a captured failure message.",
        source: "xcresult.test-summary",
        messages: text.map { [FailureMessage.parse($0)] }
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

  /// Node types that hold one run of a test: a parameterized argument, a repetition or
  /// retry, a device or a test plan configuration. Their names label the messages below them.
  static let runNodeTypes: Set<String> = [
    "Arguments", "Repetition", "Device", "Test Plan Configuration", "Test Case Run",
  ]

  static func parseTestFailures(_ json: [String: Any]) -> [TestFailureObservation] {
    var failures: [TestFailureObservation] = []

    func collectFailure(from node: [String: Any], target: String?) {
      let nodeType = (node["nodeType"] as? String) ?? ""
      let result = (node["result"] as? String) ?? ""
      let name = (node["name"] as? String) ?? "?"
      let identifier = (node["nodeIdentifier"] as? String) ?? name
      var target = target
      if nodeType.hasSuffix("test bundle") { target = name }

      if nodeType == "Test Case" && result == "Failed" {
        let messages = failureMessages(in: node, label: nil)
        failures.append(
          TestFailureObservation(
            testName: name,
            testIdentifier: TestIDs.canonical(target: target, identifier: identifier),
            message: messages.isEmpty
              ? "Test failed without a captured failure message."
              : messages.map(\.display).joined(separator: "\n"),
            source: "xcresult.test-details",
            messages: messages.isEmpty ? nil : messages
          )
        )
        return
      }

      if let children = node["children"] as? [[String: Any]] {
        for child in children {
          collectFailure(from: child, target: target)
        }
      }
    }

    if let testNodes = json["testNodes"] as? [[String: Any]] {
      for node in testNodes {
        collectFailure(from: node, target: nil)
      }
    }

    return failures
  }

  /// Every failure message under a test case, at any depth, labelled with the run it came from.
  static func failureMessages(in node: [String: Any], label: String?) -> [FailureMessage] {
    var out: [FailureMessage] = []
    for child in (node["children"] as? [[String: Any]]) ?? [] {
      let type = (child["nodeType"] as? String) ?? ""
      let name = (child["name"] as? String) ?? ""
      if type == "Failure Message" {
        if !name.isEmpty { out.append(FailureMessage.parse(name, label: label)) }
      } else if runNodeTypes.contains(type), !name.isEmpty {
        // A run that passed has nothing to report; one that failed labels its messages.
        if (child["result"] as? String) == "Passed" { continue }
        out += failureMessages(in: child, label: label.map { "\($0) · \(name)" } ?? name)
      } else {
        out += failureMessages(in: child, label: label)
      }
    }
    return out
  }

  /// Tests that passed in the end but failed in at least one retry or repetition.
  static func parseFlakyTests(_ json: [String: Any]) -> [String] {
    var flaky: [String] = []

    func failedRun(_ node: [String: Any]) -> Bool {
      for child in (node["children"] as? [[String: Any]]) ?? [] {
        let type = (child["nodeType"] as? String) ?? ""
        if runNodeTypes.contains(type), (child["result"] as? String) == "Failed" { return true }
        if failedRun(child) { return true }
      }
      return false
    }

    func walk(_ node: [String: Any], target: String?) {
      let nodeType = (node["nodeType"] as? String) ?? ""
      let name = (node["name"] as? String) ?? "?"
      var target = target
      if nodeType.hasSuffix("test bundle") { target = name }
      if nodeType == "Test Case" {
        let result = (node["result"] as? String) ?? ""
        if result != "Failed" && result != "Skipped" && failedRun(node) {
          let identifier = (node["nodeIdentifier"] as? String) ?? name
          flaky.append(TestIDs.canonical(target: target, identifier: identifier))
        }
        return
      }
      for child in (node["children"] as? [[String: Any]]) ?? [] { walk(child, target: target) }
    }

    for node in (json["testNodes"] as? [[String: Any]]) ?? [] { walk(node, target: nil) }
    return flaky
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

  /// Parse `file:line:col: error: message` lines from xcodebuild output (stdout and/or
  /// stderr). The same diagnostic is often printed several times (once per architecture or
  /// by both the compiler and the build summary), so duplicates are dropped, keeping order.
  static func fallbackBuildIssues(stderr: String) -> [BuildIssueObservation] {
    var seen = Set<String>()
    var issues: [BuildIssueObservation] = []
    for line in stderr.split(separator: "\n") {
      guard let issue = parseFallbackBuildIssue(String(line)) else { continue }
      let loc = issue.location
      let key = [
        issue.severity == .error ? "e" : "w", loc?.filePath ?? "", loc?.line.map(String.init) ?? "",
        loc?.column.map(String.init) ?? "", issue.message,
      ].joined(separator: "|")
      if seen.insert(key).inserted { issues.append(issue) }
    }
    return issues
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
    case "test_plan_inspect": return await testPlanInspect(args, env: env)
    default: return nil
    }
  }
}

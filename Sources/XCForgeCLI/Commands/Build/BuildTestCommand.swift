import ArgumentParser
import Foundation
import XCForgeKit

struct BuildTest: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "build-test",
    abstract:
      "Build then test in one step. Short-circuits on build failure with structured diagnostics."
  )

  @Option(help: "Path to .xcodeproj or .xcworkspace. Auto-detected if omitted.")
  var project: String?

  @Option(help: "Xcode scheme name. Auto-detected if omitted.")
  var scheme: String?

  @Option(help: "Simulator name or UDID. Auto-detected from booted simulator if omitted.")
  var simulator: String?

  @Option(help: "Build configuration (Debug/Release). Default: Debug")
  var configuration: String?

  @Option(help: "Test plan name.")
  var testplan: String?

  @Option(
    help:
      "Test filter. Accepts: 'testMethod', 'TestClass/testMethod', or 'TestTarget/TestClass/testMethod'. Target prefix is auto-resolved."
  )
  var filter: String?

  @Flag(help: "Enable code coverage collection.")
  var coverage = false

  @Flag(help: "Raise the total time limit from 1800s to 7200s. Hangs are caught by --idle-timeout either way.")
  var long = false

  @Option(
    help:
      "Override timeout in seconds. Takes precedence over --long. Default: 1800s (or 7200s with --long)."
  )
  var timeoutSeconds: Int?

  @Flag(help: "Capture a diagnostic snapshot even when the build/test succeeds.")
  var diagnose = false

  @Option(
    name: .long, parsing: .singleValue,
    help: ArgumentHelp(
      "Environment variable for the test runner (repeatable). Format: KEY=VALUE. The key is auto-prefixed with TEST_RUNNER_; Xcode strips the prefix inside the test process, so 'BLESS_BASELINE=1' surfaces as ProcessInfo.environment[\"BLESS_BASELINE\"]. TEST_RUNNER_XCFORGE_REPO_ROOT is always injected (override with --env XCFORGE_REPO_ROOT=...).",
      valueName: "KEY=VALUE"
    )
  )
  var env: [String] = []

  @Option(
    help:
      "Simulator recovery: off (default), auto (reboot if not Booted), erase (also erase if a reboot didn't help)."
  )
  var simRecovery: String = "off"

  @Flag(help: "Run on a fresh simulator of the same model and OS, deleted afterwards.")
  var isolatedSim = false

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  @Option(
    name: [.customLong("for")],
    help: "Output audience: 'human' (default) or 'agent'. 'agent' implies --json with a slim shape."
  )
  var forMode: OutputAudience = .human

  @Flag(
    help:
      "Subtract IDs listed in .xcforge/known-failures.yaml when computing succeeded:. Opt-in; raw failure list is unchanged."
  )
  var gate = false

  @OptionGroup var xcodebuild: XcodebuildOptionGroup

  mutating func run() async throws {
    let command = self
    try await xcodebuild.scoped { try await command.execute() }
  }

  func execute() async throws {
    let useJSON = shouldOutputJSON(flag: json) || forMode == .agent
    let session = Environment.live.session
    let configuration = await session.resolveConfiguration(self.configuration)
    let resolvedTestplan = await session.resolveTestPlan(testplan)
    let resolvedTimeout = timeoutSeconds.map { TimeInterval($0) }

    let result = try await TestTools.executeBuildAndTest(
      project: project,
      scheme: scheme,
      simulator: simulator,
      configuration: configuration,
      testplan: resolvedTestplan,
      filter: filter,
      coverage: coverage,
      long: long,
      diagnose: diagnose,
      simRecovery: try SimRecoveryMode.parse(simRecovery),
      timeoutSeconds: resolvedTimeout,
      envEntries: env,
      gate: gate,
      forMode: forMode,
      isolatedSimulator: isolatedSim
    )

    if useJSON {
      print(try WorkflowJSONRenderer.renderTestJSON(result, forAgent: forMode == .agent))
    } else {
      print(BuildTestRenderer.render(result))
    }

    if !result.buildSucceeded || (result.testResult?.succeeded == false) {
      throw ExitCode.failure
    }
  }
}

enum BuildTestRenderer {
  static func render(_ result: TestTools.BuildAndTestResult) -> String {
    var lines: [String] = []

    if !result.buildSucceeded {
      lines.append("BUILD FAILED (\(result.buildElapsed)s)")
      lines.append("Tests were NOT run.")
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
          lines.append("")
          lines.append("Warnings (\(warnings.count)):")
          for issue in warnings.prefix(10) {
            if let loc = issue.location {
              lines.append("  \(loc.filePath):\(loc.line ?? 0): \(issue.message)")
            } else {
              lines.append("  \(issue.message)")
            }
          }
        }
      }
      return lines.joined(separator: "\n")
    }

    lines.append("Build OK (\(result.buildElapsed)s)")

    if let test = result.testResult {
      let icon = test.succeeded ? "PASSED" : "FAILED"
      lines.append("Tests \(icon) (\(test.elapsed)s)")
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

      if !test.screenshotPaths.isEmpty {
        lines.append("")
        lines.append("Screenshots:")
        for screenshot in test.screenshotPaths {
          lines.append("  \(screenshot.path)")
        }
      }

      lines.append("")
      lines.append("xcresult: \(test.xcresultPath)")
    }

    return lines.joined(separator: "\n")
  }
}

import Foundation
import XCForgeKit

enum TestRenderer {
  static func renderTest(_ execution: TestTools.TestExecution) -> String {
    var lines: [String] = []

    let icon = execution.succeeded ? "PASSED" : "FAILED"
    lines.append("Tests \(icon) in \(execution.elapsed)s")

    // Statistics
    var statParts: [String] = []
    statParts.append("\(execution.totalTestCount) total")
    if execution.passedTestCount > 0 { statParts.append("\(execution.passedTestCount) passed") }
    if execution.failedTestCount > 0 { statParts.append("\(execution.failedTestCount) FAILED") }
    if execution.skippedTestCount > 0 { statParts.append("\(execution.skippedTestCount) skipped") }
    if execution.expectedFailureCount > 0 {
      statParts.append("\(execution.expectedFailureCount) expected-failure")
    }
    lines.append(statParts.joined(separator: ", "))

    // Inline failure summaries
    for failure in execution.failures.prefix(20) {
      lines.append("FAIL: \(failure.testName)")
      if !failure.message.isEmpty {
        lines.append("  \(failure.message)")
      }
    }

    // Device info
    if let name = execution.deviceName {
      let os = execution.osVersion ?? ""
      lines.append("Device: \(name) (\(os))")
    }

    lines.append("Scheme: \(execution.scheme)")
    lines.append("Simulator: \(execution.simulator)")

    // Screenshots
    if !execution.screenshotPaths.isEmpty {
      lines.append("")
      lines.append("Failure screenshots (\(execution.screenshotPaths.count)):")
      for att in execution.screenshotPaths {
        lines.append("  \(att.path)")
      }
    }

    lines.append("xcresult: \(execution.xcresultPath)")
    return lines.joined(separator: "\n")
  }

  static func renderFailures(_ result: TestTools.TestFailuresResult) -> String {
    if result.failures.isEmpty {
      return "No test failures found.\nxcresult: \(result.xcresultPath)"
    }

    var lines: [String] = []
    lines.append("\(result.failures.count) test failure(s):")
    lines.append("")

    for failure in result.failures {
      lines.append("FAIL: \(failure.testName) [\(failure.testIdentifier)]")
      if !failure.message.isEmpty {
        lines.append("  " + failure.message.replacingOccurrences(of: "\n", with: "\n  "))
      }

      // Matching screenshots
      let matchingScreenshots = result.screenshots.filter {
        $0.testName.contains(failure.testIdentifier) || failure.testIdentifier.contains($0.testName)
      }
      for screenshot in matchingScreenshots {
        lines.append("  Screenshot: \(screenshot.path)")
      }

      // Console output
      let funcName =
        failure.testIdentifier.split(separator: "/").last.map(String.init) ?? failure.testIdentifier
      if let console = result.consoleByTest[funcName]
        ?? result.consoleByTest[failure.testIdentifier]
      {
        lines.append("  Console:")
        lines.append("    " + console.replacingOccurrences(of: "\n", with: "\n    "))
      }

      lines.append("")
    }

    // All screenshots at the end
    if !result.screenshots.isEmpty {
      lines.append("Failure screenshots (\(result.screenshots.count)):")
      for att in result.screenshots {
        lines.append("  \(att.path)")
      }
    }

    lines.append("xcresult: \(result.xcresultPath)")
    return lines.joined(separator: "\n")
  }

  static func renderCoverage(_ result: TestTools.CoverageResult) -> String {
    var lines: [String] = []

    if let overall = result.overallCoverage {
      lines.append(String(format: "Overall coverage: %.1f%%", overall * 100))
    }

    for target in result.targets {
      lines.append(String(format: "\nTarget: %@ (%.1f%%)", target.name, target.lineCoverage * 100))
      for file in target.files {
        lines.append(String(format: "  %6.1f%% %@", file.lineCoverage * 100, file.name))
      }
    }

    lines.append("\nxcresult: \(result.xcresultPath)")
    return lines.joined(separator: "\n")
  }

  static func renderListTests(_ result: TestTools.ListTestsResult) -> String {
    var lines: [String] = []
    lines.append(
      "\(result.testCount) tests in \(result.targetCount) target(s), \(result.classCount) class(es)"
    )
    lines.append("")

    // Group by target/class
    var grouped: [String: [String: [String]]] = [:]
    for test in result.tests {
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
    lines.append("Filter examples:")
    lines.append("  xcforge test --filter \"Target/Class/method\"")
    lines.append("  xcforge test --filter \"Class/method\"  (auto-resolves target)")
    lines.append("  xcforge test --filter \"Class\"          (all tests in class)")
    return lines.joined(separator: "\n")
  }

  static func renderFileCoverage(_ detail: TestTools.FileCoverageDetail) -> String {
    var lines: [String] = []

    lines.append(
      String(
        format: "%@ — %.1f%% (%d/%d lines)",
        detail.fileName,
        detail.lineCoverage * 100,
        detail.coveredLines,
        detail.executableLines
      ))
    lines.append("")

    var untested: [String] = []
    for fn in detail.functions {
      if fn.executionCount == 0 {
        lines.append(
          String(
            format: "  L%-4d %-40s   0%%  UNTESTED  (%d lines)", fn.lineNumber, fn.name,
            fn.executableLines))
        untested.append("\(fn.name) (L\(fn.lineNumber), \(fn.executableLines) lines)")
      } else {
        lines.append(
          String(
            format: "  L%-4d %-40s %3.0f%%  (%dx called)", fn.lineNumber, fn.name,
            fn.lineCoverage * 100, fn.executionCount))
      }
    }

    if !untested.isEmpty {
      lines.append("")
      lines.append("Untested functions (\(untested.count)): \(untested.joined(separator: ", "))")
    }

    lines.append("\nxcresult: \(detail.xcresultPath)")
    return lines.joined(separator: "\n")
  }
}

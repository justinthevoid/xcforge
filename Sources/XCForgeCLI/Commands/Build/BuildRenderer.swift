import Foundation
import XCForgeKit

/// JSON-encodable wrapper for the full `build run` pipeline result,
/// including boot/install/launch phase statuses alongside the build execution.
struct BuildRunResult: Codable {
  let build: BuildTools.BuildExecution
  let boot: String?
  let install: String?
  let launch: String?
  let appPid: String?
  let appRunning: Bool?
}

enum BuildRenderer {
  static func renderBuild(_ execution: BuildTools.BuildExecution) -> String {
    var lines: [String] = []

    if execution.succeeded {
      lines.append("Build succeeded in \(execution.elapsed)s")
    } else {
      lines.append("Build FAILED in \(execution.elapsed)s")
    }

    lines.append("Scheme: \(execution.scheme)")
    lines.append("Simulator: \(execution.simulator)")
    lines.append("Configuration: \(execution.configuration)")

    if let bid = execution.bundleId {
      lines.append("Bundle ID: \(bid)")
    }
    if let path = execution.appPath {
      lines.append("App path: \(path)")
    }

    if !execution.succeeded, let reason = execution.failureReason {
      lines.append("Failure reason: \(reason)")
    }

    // Prefer xcresult-parsed issues (most actionable)
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
      if !execution.succeeded {
        lines.append("Tip: run `xcforge build diagnose` to re-inspect without rebuilding")
      }
    }

    return lines.joined(separator: "\n")
  }

  static func renderBuildRun(
    _ execution: BuildTools.BuildExecution,
    bootStatus: String,
    installStatus: String,
    launchStatus: String,
    appPid: String? = nil,
    appRunning: Bool = false
  ) -> String {
    var lines: [String] = []

    lines.append("Scheme: \(execution.scheme) | Simulator: \(execution.simulator)")

    if let bid = execution.bundleId {
      lines.append("Bundle ID: \(bid)")
    }
    if let path = execution.appPath {
      lines.append("App path: \(path)")
    }
    if let pid = appPid {
      lines.append("App PID: \(pid)")
    }
    if appRunning {
      lines.append("App running: true")
    }

    lines.append("")
    lines.append("  Build:   \(execution.elapsed)s")
    lines.append("  Boot:    \(bootStatus)")
    lines.append("  Install: \(installStatus)")
    lines.append("  Launch:  \(launchStatus)")

    return lines.joined(separator: "\n")
  }

  static func renderDiagnose(_ execution: TestTools.BuildDiagnosisExecution) -> String {
    var lines: [String] = []

    let status = execution.succeeded ? "SUCCEEDED" : "FAILED"
    lines.append("Build \(status) in \(execution.elapsed)s")

    if execution.errorCount > 0 || execution.warningCount > 0 || execution.analyzerWarningCount > 0 {
      var parts: [String] = []
      if execution.errorCount > 0 { parts.append("\(execution.errorCount) error(s)") }
      if execution.warningCount > 0 { parts.append("\(execution.warningCount) warning(s)") }
      if execution.analyzerWarningCount > 0 {
        parts.append("\(execution.analyzerWarningCount) analyzer warning(s)")
      }
      lines.append(parts.joined(separator: ", "))
    }

    for issue in execution.issues.prefix(20) {
      let prefix: String
      switch issue.severity {
      case .error: prefix = "ERROR"
      case .warning: prefix = "WARNING"
      case .analyzerWarning: prefix = "ANALYZER"
      }

      var location = ""
      if let loc = issue.location {
        let shortPath = (loc.filePath as NSString).lastPathComponent
        location = " \(shortPath)"
        if let line = loc.line {
          location += ":\(line)"
          if let col = loc.column {
            location += ":\(col)"
          }
        }
      }

      lines.append("  \(prefix)\(location): \(issue.message)")
    }

    if let name = execution.destinationDeviceName, !name.isEmpty {
      let os = execution.destinationOSVersion ?? ""
      lines.append("Device: \(name) (\(os))")
    }

    lines.append("xcresult: \(execution.xcresultPath)")

    return lines.joined(separator: "\n")
  }

  static func renderClean(_ execution: BuildTools.CleanExecution) -> String {
    var lines: [String] = []

    if execution.succeeded {
      lines.append("Clean succeeded")
    } else {
      lines.append("Clean FAILED")
    }

    lines.append("Project: \(execution.project)")
    lines.append("Scheme: \(execution.scheme)")

    if let error = execution.error, !error.isEmpty {
      lines.append("")
      lines.append(error)
    }

    return lines.joined(separator: "\n")
  }

  static func renderDiscover(_ execution: BuildTools.DiscoverExecution) -> String {
    var lines: [String] = []

    if execution.projects.isEmpty {
      lines.append("No projects found in \(execution.path)")
    } else {
      lines.append("Found \(execution.projects.count) project(s) in \(execution.path):")
      for project in execution.projects {
        lines.append("  \(project)")
      }
    }

    return lines.joined(separator: "\n")
  }

  static func renderSchemes(_ execution: BuildTools.SchemesExecution) -> String {
    var lines: [String] = []

    if !execution.succeeded {
      lines.append("Failed to list schemes for \(execution.project)")
      if let error = execution.error, !error.isEmpty {
        lines.append(error)
      }
      return lines.joined(separator: "\n")
    }

    if execution.schemes.isEmpty {
      lines.append("No schemes found for \(execution.project)")
    } else {
      lines.append("Schemes for \(execution.project):")
      for scheme in execution.schemes {
        lines.append("  \(scheme)")
      }
    }

    return lines.joined(separator: "\n")
  }

  static func renderDiagnoseFromXcresult(
    _ result: (
      issues: [TestTools.BuildIssueObservation], errorCount: Int, warningCount: Int,
      analyzerWarningCount: Int, xcresultPath: String
    ),
    errorsOnly: Bool
  ) -> String {
    var lines: [String] = []

    if result.issues.isEmpty {
      lines.append("No issues found in xcresult bundle.")
    } else {
      var parts: [String] = []
      if result.errorCount > 0 { parts.append("\(result.errorCount) error(s)") }
      if !errorsOnly {
        if result.warningCount > 0 { parts.append("\(result.warningCount) warning(s)") }
        if result.analyzerWarningCount > 0 {
          parts.append("\(result.analyzerWarningCount) analyzer warning(s)")
        }
      }
      lines.append(parts.joined(separator: ", "))
      lines.append("")

      for issue in result.issues.prefix(30) {
        let prefix: String
        switch issue.severity {
        case .error: prefix = "ERROR"
        case .warning: prefix = "WARNING"
        case .analyzerWarning: prefix = "ANALYZER"
        }
        lines.append("  \(prefix) \(formatIssue(issue))")
      }
    }

    lines.append("")
    lines.append("xcresult: \(result.xcresultPath)")

    return lines.joined(separator: "\n")
  }

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
}

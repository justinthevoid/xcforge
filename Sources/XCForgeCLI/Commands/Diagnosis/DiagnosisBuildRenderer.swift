import Foundation
import XCForgeKit

enum DiagnosisBuildRenderer {
  static func render(_ result: DiagnosisBuildResult) -> String {
    var lines: [String] = [
      "Workflow: \(result.workflow.rawValue)",
      "Phase: \(result.phase.rawValue)",
      "Status: \(result.status.rawValue)",
    ]

    if let runId = result.runId {
      lines.append("Run ID: \(runId)")
    }
    if let attemptId = result.attemptId {
      lines.append("Attempt ID: \(attemptId)")
    }

    if let context = result.resolvedContext {
      lines.append("Resolved context:")
      lines.append("  project: \(context.project)")
      lines.append("  scheme: \(context.scheme)")
      lines.append("  simulator: \(context.simulator)")
      lines.append("  configuration: \(context.configuration)")
      lines.append("  bundle_id: \(context.app.bundleId)")
      lines.append("  app_path: \(context.app.appPath)")
    }

    if let summary = result.summary {
      lines.append("Observed evidence:")
      lines.append("  summary: \(summary.observedEvidence.summary)")
      if let primarySignal = summary.observedEvidence.primarySignal {
        lines.append("  primary_signal: \(primarySignal.message)")
        lines.append("  severity: \(primarySignal.severity.rawValue)")
        if let location = primarySignal.location {
          var renderedLocation = location.filePath
          if let line = location.line {
            renderedLocation += ":\(line)"
            if let column = location.column {
              renderedLocation += ":\(column)"
            }
          }
          lines.append("  location: \(renderedLocation)")
        }
        lines.append("  source: \(primarySignal.source)")
      }
      lines.append("  additional_issue_count: \(summary.observedEvidence.additionalIssueCount)")
      lines.append(
        "  counts: errors=\(summary.observedEvidence.errorCount), warnings=\(summary.observedEvidence.warningCount), analyzer_warnings=\(summary.observedEvidence.analyzerWarningCount)"
      )

      if let inferredConclusion = summary.inferredConclusion {
        lines.append("Inferred conclusion:")
        lines.append("  summary: \(inferredConclusion.summary)")
      }

      if !summary.supportingEvidence.isEmpty {
        lines.append("Supporting evidence:")
        lines += summary.supportingEvidence.map { "  - \($0.kind): \($0.path) [\($0.source)]" }
      }
    }

    if let persistedRunPath = result.persistedRunPath {
      lines.append("Run record: \(persistedRunPath)")
    }

    if let failure = result.failure {
      lines.append("Failure field: \(failure.field.rawValue)")
      lines.append("Failure class: \(failure.classification.rawValue)")
      lines.append("Reason: \(failure.message)")
    }

    return lines.joined(separator: "\n")
  }
}

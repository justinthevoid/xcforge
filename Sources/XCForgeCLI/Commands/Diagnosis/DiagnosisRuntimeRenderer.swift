import Foundation
import XCForgeKit

enum DiagnosisRuntimeRenderer {
  static func render(_ result: DiagnosisRuntimeResult) -> String {
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
      lines.append(
        "  state: launched=\(summary.observedEvidence.launchedApp), running=\(summary.observedEvidence.appRunning), relaunched=\(summary.observedEvidence.relaunchedApp)"
      )
      if let primarySignal = summary.observedEvidence.primarySignal {
        lines.append("  primary_signal: \(primarySignal.message)")
        lines.append("  stream: \(primarySignal.stream.rawValue)")
        lines.append("  source: \(primarySignal.source)")
      }
      lines.append("  additional_signal_count: \(summary.observedEvidence.additionalSignalCount)")
      lines.append(
        "  counts: stdout=\(summary.observedEvidence.stdoutLineCount), stderr=\(summary.observedEvidence.stderrLineCount)"
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

    if !result.recoveryHistory.isEmpty {
      lines.append("Recovery narrative:")
      lines += result.recoveryHistory.map(renderRecoveryLine)
    }

    let availableArtifacts = result.evidence.filter { $0.availability == .available }
    if !availableArtifacts.isEmpty {
      lines.append("Captured artifacts:")
      lines += availableArtifacts.map { record in
        let reference = record.reference ?? "unavailable"
        return "  - \(record.kind.rawValue): \(reference) [\(record.source)]"
      }
    }

    let unavailableArtifacts = result.evidence.filter { $0.availability == .unavailable }
    if !unavailableArtifacts.isEmpty {
      lines.append("Unavailable artifacts:")
      lines += unavailableArtifacts.map { record in
        var line = "  - \(record.kind.rawValue)"
        if let reason = record.unavailableReasonLabel {
          line += " (\(reason))"
        }
        if let detail = record.detail {
          line += ": \(detail)"
        }
        return line
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

  private static func renderRecoveryLine(_ recovery: WorkflowRecoveryRecord) -> String {
    var line = "  - \(recovery.recoveryId)"
    line += " | issue=\(recovery.issue.label)"
    line += " | action=\(recovery.action.label)"
    line += " | status=\(recovery.status.rawValue)"
    line += " | resumed=\(recovery.resumed ? "yes" : "no")"
    line += " | detected=\(sanitizeInlineField(recovery.detectedIssue))"
    line += " | summary=\(sanitizeInlineField(recovery.summary))"
    if let detail = recovery.detail {
      line += " | detail=\(sanitizeInlineField(detail))"
    }
    return line
  }

  private static func sanitizeInlineField(_ value: String) -> String {
    value
      .replacingOccurrences(of: "\r\n", with: " ")
      .replacingOccurrences(of: "\n", with: " ")
      .replacingOccurrences(of: " | ", with: " / ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

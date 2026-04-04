import Foundation
import XCForgeKit

enum DiagnosisStatusRenderer {
    static func render(_ result: DiagnosisStatusResult) -> String {
        var lines: [String] = [
            "Workflow: \(result.workflow.rawValue)",
        ]

        if let phase = result.phase {
            lines.append("Phase: \(phase.rawValue)")
        }
        if let status = result.status {
            lines.append("Status: \(status.rawValue)")
        }

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
            if let preparation = context.simulatorPreparation {
                lines.append("Prepared simulator:")
                lines.append("  requested: \(preparation.requested)")
                lines.append("  target: \(preparation.selected)")
                lines.append("  name: \(preparation.displayName)")
                lines.append("  runtime: \(preparation.runtime)")
                lines.append("  initial_state: \(preparation.initialState)")
                lines.append("  state: \(preparation.state)")
                lines.append("  action: \(preparation.action.rawValue)")
                lines.append("  summary: \(preparation.summary)")
            }
        }

        if let summary = result.summary {
            lines.append("Summary source: \(summary.source.rawValue)")
            lines.append("Summary: \(summary.headline)")
            if let detail = summary.detail {
                lines.append("Detail: \(detail)")
            }
        }

        if !result.actionHistory.isEmpty {
            lines.append("Action History:")
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            lines += result.actionHistory.map { action in
                var line = "  [\(formatter.string(from: action.timestamp))] \(action.kind.rawValue) (\(action.phase.rawValue))"
                if let detail = action.detail {
                    line += " — \(sanitizeInlineField(detail))"
                }
                return line
            }
        }

        if !result.recoveryHistory.isEmpty {
            lines.append("Recovery narrative:")
            lines += result.recoveryHistory.map { recovery in
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

    private static func sanitizeInlineField(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: " | ", with: " / ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

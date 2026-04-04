import Foundation
import xcforgeCore

enum DiagnosisInspectRenderer {
    static func render(_ result: DiagnosisInspectResult) -> String {
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
        }

        if let provenance = result.contextProvenance {
            appendContextProvenance(&lines, provenance)
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

        if let completeness = result.evidenceCompleteness {
            lines.append("Evidence completeness: \(completeness.rawValue)")
        }

        let available = result.availableEvidence
        if !available.isEmpty {
            lines.append("Available evidence:")
            lines += available.map(renderEvidenceLine)
        }

        let unavailable = result.unavailableEvidence
        if !unavailable.isEmpty {
            lines.append("Unavailable evidence:")
            lines += unavailable.map(renderUnavailableEvidenceLine)
        }

        if result.evidence.isEmpty {
            lines.append("Evidence: none recorded")
        }

        if let failure = result.failure {
            appendFailureDetail(&lines, failure)
        }

        if let followOn = result.followOnAction {
            lines.append("Follow-on action: \(followOn.action)")
            lines.append("  rationale: \(sanitizeInlineField(followOn.rationale))")
            lines.append("  confidence: \(followOn.confidence.rawValue)")
        }

        if let persistedRunPath = result.persistedRunPath {
            lines.append("Run record: \(persistedRunPath)")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Context Provenance

    private static func appendContextProvenance(_ lines: inout [String], _ provenance: WorkflowContextProvenance) {
        lines.append("Context provenance:")
        if let sourceRunId = provenance.sourceRunId {
            lines.append("  source_run_id: \(sourceRunId)")
        }
        if let sourceAttemptId = provenance.sourceAttemptId {
            lines.append("  source_attempt_id: \(sourceAttemptId)")
        }
        for field in provenance.fields {
            var line = "  \(field.field.rawValue): source=\(field.source.rawValue)"
            if let sourceRunId = field.sourceRunId {
                line += " | from_run=\(sourceRunId)"
            }
            if let detail = field.detail {
                line += " | detail=\(sanitizeInlineField(detail))"
            }
            lines.append(line)
        }
    }

    // MARK: - Evidence

    private static func renderEvidenceLine(_ record: WorkflowEvidenceRecord) -> String {
        let reference = record.reference ?? "no reference"
        return "  - \(record.kind.rawValue) | phase=\(record.phase.rawValue) | attempt=\(record.attemptNumber) | source=\(record.source) | reference=\(reference)"
    }

    private static func renderUnavailableEvidenceLine(_ record: WorkflowEvidenceRecord) -> String {
        var line = "  - \(record.kind.rawValue) | phase=\(record.phase.rawValue) | attempt=\(record.attemptNumber)"
        line += " | source=\(record.source)"
        line += " | producing_step=\(record.producingWorkflowStep)"
        if let reason = record.unavailableReasonLabel {
            line += " | reason=\(reason)"
        }
        if let detail = record.detail {
            line += " | detail=\(sanitizeInlineField(detail))"
        }
        return line
    }

    // MARK: - Failure Detail

    private static func appendFailureDetail(_ lines: inout [String], _ failure: WorkflowFailure) {
        lines.append("Terminal classification:")
        lines.append("  field: \(failure.field.rawValue)")
        lines.append("  classification: \(failure.classification.rawValue)")
        lines.append("  message: \(sanitizeInlineField(failure.message))")

        if let observed = failure.observed {
            lines.append("  observed (fact): \(sanitizeInlineField(observed.summary))")
            if let detail = observed.detail {
                lines.append("    detail: \(sanitizeInlineField(detail))")
            }
        }

        if let inferred = failure.inferred {
            lines.append("  inferred (conclusion): \(sanitizeInlineField(inferred.summary))")
        }

        if let refs = failure.evidenceReferences, !refs.isEmpty {
            lines.append("  supporting evidence:")
            lines += refs.map { "    - \($0.kind): \($0.path) [\($0.source)]" }
        }

        if let recoverability = failure.recoverability {
            lines.append("  recoverability: \(recoverability.rawValue)")
        }
    }

    // MARK: - Helpers

    private static func sanitizeInlineField(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: " | ", with: " / ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

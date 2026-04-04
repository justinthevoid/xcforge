import Foundation
import xcforgeCore

enum DiagnosisCompareRenderer {
    static func render(_ result: DiagnosisCompareResult) -> String {
        var lines: [String] = [
            "Workflow: \(result.workflow.rawValue)",
        ]

        if let phase = result.phase {
            lines.append("Phase: \(phase.rawValue)")
        }
        if let status = result.status {
            lines.append("Status: \(status.rawValue)")
        }
        if let outcome = result.outcome {
            lines.append("Comparison outcome: \(outcome.rawValue)")
        }

        if let runId = result.runId {
            lines.append("Run ID: \(runId)")
        }
        if let attemptId = result.attemptId {
            lines.append("Current attempt ID: \(attemptId)")
        }
        if let sourceAttemptId = result.sourceAttemptId {
            lines.append("Source attempt ID: \(sourceAttemptId)")
        }

        if let prior = result.priorAttempt {
            appendAttemptBlock(
                &lines,
                title: "Prior state",
                attempt: prior,
                includeContext: result.currentAttempt?.resolvedContext != prior.resolvedContext
            )
        }

        if let current = result.currentAttempt {
            appendAttemptBlock(
                &lines,
                title: "Current state",
                attempt: current,
                includeContext: result.priorAttempt?.resolvedContext != current.resolvedContext
            )
        }

        lines.append("Changed evidence:")
        if result.changedEvidence.isEmpty {
            lines.append("  - No meaningful summary changes were recorded.")
        } else {
            lines += result.changedEvidence.map { change in
                "  - \(change.field): \(change.priorValue) -> \(change.currentValue)"
            }
        }

        lines.append("Unchanged blockers:")
        if result.unchangedBlockers.isEmpty {
            lines.append("  - None")
        } else {
            lines += result.unchangedBlockers.map { "  - \($0)" }
        }

        if let prior = result.priorAttempt {
            appendEvidenceBundle(&lines, title: "Prior evidence bundle", attempt: prior)
        }
        if let current = result.currentAttempt {
            appendEvidenceBundle(&lines, title: "Current evidence bundle", attempt: current)
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

    private static func appendAttemptBlock(
        _ lines: inout [String],
        title: String,
        attempt: DiagnosisCompareAttemptSnapshot,
        includeContext: Bool
    ) {
        lines.append("\(title):")
        lines.append("  attempt_id: \(attempt.attemptId)")
        lines.append("  attempt_number: \(attempt.attemptNumber)")
        lines.append("  phase: \(attempt.phase.rawValue)")
        lines.append("  status: \(attempt.status.rawValue)")
        lines.append("  summary: \(attempt.summary.headline)")
        if let detail = attempt.summary.detail {
            lines.append("  detail: \(detail)")
        }

        if includeContext {
            lines.append("  resolved_context:")
            lines.append("    project: \(attempt.resolvedContext.project)")
            lines.append("    scheme: \(attempt.resolvedContext.scheme)")
            lines.append("    simulator: \(attempt.resolvedContext.simulator)")
            lines.append("    configuration: \(attempt.resolvedContext.configuration)")
            lines.append("    bundle_id: \(attempt.resolvedContext.app.bundleId)")
            lines.append("    app_path: \(attempt.resolvedContext.app.appPath)")
        }
    }

    private static func appendEvidenceBundle(
        _ lines: inout [String],
        title: String,
        attempt: DiagnosisCompareAttemptSnapshot
    ) {
        lines.append("\(title):")
        lines.append(
            "  counts: \(attempt.availableEvidence.count) available, \(attempt.unavailableEvidence.count) unavailable"
        )

        if !attempt.availableEvidence.isEmpty {
            lines.append("  available:")
            lines += attempt.availableEvidence.map { renderArtifactLine($0, indent: "    ") }
        }
        if !attempt.unavailableEvidence.isEmpty {
            lines.append("  missing:")
            lines += attempt.unavailableEvidence.map { renderMissingArtifactLine($0, indent: "    ") }
        }
    }

    private static func renderArtifactLine(_ record: WorkflowEvidenceRecord, indent: String) -> String {
        let reference = record.reference ?? "unavailable"
        return "\(indent)- \(record.kind.rawValue) | phase=\(record.phase.rawValue) | attempt=\(record.attemptNumber) | state=\(record.availabilityLabel) | source=\(record.source) | reference=\(reference)"
    }

    private static func renderMissingArtifactLine(_ record: WorkflowEvidenceRecord, indent: String) -> String {
        var line = "\(indent)- \(record.kind.rawValue) | phase=\(record.phase.rawValue) | attempt=\(record.attemptNumber) | state=\(record.availabilityLabel)"
        line += " | source=\(record.source)"
        line += " | producing step=\(record.producingWorkflowStep)"
        if let reason = record.unavailableReasonLabel {
            line += " | reason=\(reason)"
        }
        if let detail = record.detail {
            line += " | detail=\(detail)"
        }
        return line
    }
}

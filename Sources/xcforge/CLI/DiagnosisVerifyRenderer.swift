import Foundation
import xcforgeCore

enum DiagnosisVerifyRenderer {
    static func render(_ result: DiagnosisVerifyResult) -> String {
        var lines: [String] = []

        if let outcome = result.outcome {
            lines.append("Verification Outcome: \(outcome.rawValue)")
        }
        if let phase = result.phase {
            lines.append("Validation Phase: \(phase.rawValue)")
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
        if let sourceAttemptId = result.sourceAttemptId {
            lines.append("Source Attempt ID: \(sourceAttemptId)")
        }

        if let context = result.resolvedContext {
            lines.append("Project: \(context.project)")
            lines.append("Scheme: \(context.scheme)")
            lines.append("Simulator: \(context.simulator)")
            lines.append("Configuration: \(context.configuration)")
        }

        if let summary = result.summary {
            lines.append("Summary: \(summary.headline)")
            if let detail = summary.detail {
                lines.append("Detail: \(detail)")
            }
        }

        if !result.evidence.isEmpty {
            let available = result.evidence.filter { $0.availability == .available }.count
            let unavailable = result.evidence.count - available
            lines.append("Evidence: \(available) available, \(unavailable) unavailable")
        }

        if let failure = result.failure {
            lines.append("Failure: [\(failure.field.rawValue):\(failure.classification.rawValue)] \(failure.message)")
        }

        if let persistedRunPath = result.persistedRunPath {
            lines.append("Persisted Run: \(persistedRunPath)")
        }

        return lines.joined(separator: "\n")
    }
}

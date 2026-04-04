import Foundation
import xcforgeCore

enum DiagnosisTestRenderer {
    static func render(_ result: DiagnosisTestResult) -> String {
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
            if let primaryFailure = summary.observedEvidence.primaryFailure {
                lines.append("  primary_test: \(primaryFailure.testName)")
                lines.append("  test_identifier: \(primaryFailure.testIdentifier)")
                lines.append("  failure_message: \(primaryFailure.message)")
                lines.append("  source: \(primaryFailure.source)")
            }
            lines.append("  additional_failure_count: \(summary.observedEvidence.additionalFailureCount)")
            lines.append(
                "  counts: total=\(summary.observedEvidence.totalTestCount), failed=\(summary.observedEvidence.failedTestCount), passed=\(summary.observedEvidence.passedTestCount), skipped=\(summary.observedEvidence.skippedTestCount), expected_failures=\(summary.observedEvidence.expectedFailureCount)"
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

import Foundation
import xcforgeCore

enum DiagnosisEvidenceRenderer {
    static func render(_ result: DiagnosisEvidenceResult) -> String {
        var lines: [String] = [
            "Workflow: \(result.workflow.rawValue)",
        ]

        if let phase = result.phase {
            lines.append("Phase: \(phase.rawValue)")
        }
        if let status = result.status {
            lines.append("Status: \(status.rawValue)")
        }
        if let state = result.evidenceState {
            lines.append("Evidence state: \(state.rawValue)")
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

        if let buildSummary = result.buildSummary {
            appendBuildEvidence(&lines, buildSummary)
        } else if shouldExplainMissingBuildEvidence(for: result) {
            lines.append("Build evidence:")
            lines.append("  missing: no build diagnosis summary is available for this run.")
            lines.append("  producing step: build diagnosis")
        }

        if let testSummary = result.testSummary {
            appendTestEvidence(&lines, testSummary)
        } else if shouldExplainMissingTestEvidence(for: result) {
            lines.append("Test evidence:")
            lines.append("  missing: no test diagnosis summary is available for this run.")
            lines.append("  producing step: test diagnosis")
        }

        if let runtimeSummary = result.runtimeSummary {
            appendRuntimeEvidence(&lines, runtimeSummary)
        } else if shouldExplainMissingRuntimeEvidence(for: result) {
            lines.append("Runtime evidence:")
            lines.append("  missing: no runtime diagnosis summary is available for this run.")
            lines.append("  producing step: runtime diagnosis")
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

        let availableEvidence = result.availableEvidence
        if !availableEvidence.isEmpty {
            lines.append("Available artifacts:")
            lines += availableEvidence.map(renderArtifactLine)
        }

        let unavailableEvidence = result.unavailableEvidence
        if !unavailableEvidence.isEmpty {
            lines.append("Missing evidence:")
            lines += unavailableEvidence.map(renderMissingArtifactLine)
        } else if result.evidenceState == .empty {
            lines.append("Missing evidence:")
            lines.append("  - No evidence has been recorded yet for this run.")
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

    private static func appendBuildEvidence(_ lines: inout [String], _ summary: BuildDiagnosisSummary) {
        lines.append("Build evidence:")
        lines.append("  observed: \(summary.observedEvidence.summary)")
        if let primarySignal = summary.observedEvidence.primarySignal {
            lines.append("  primary_signal: \(primarySignal.message)")
            lines.append("  severity: \(primarySignal.severity.rawValue)")
            if let location = primarySignal.location {
                lines.append("  location: \(renderLocation(location))")
            }
            lines.append("  source: \(primarySignal.source)")
        }
        lines.append("  additional_issue_count: \(summary.observedEvidence.additionalIssueCount)")
        lines.append(
            "  counts: errors=\(summary.observedEvidence.errorCount), warnings=\(summary.observedEvidence.warningCount), analyzer_warnings=\(summary.observedEvidence.analyzerWarningCount)"
        )

        if let inferredConclusion = summary.inferredConclusion {
            lines.append("  inferred: \(inferredConclusion.summary)")
        }

        if !summary.supportingEvidence.isEmpty {
            lines.append("  supporting evidence:")
            lines += summary.supportingEvidence.map { "    - \($0.kind): \($0.path) [\($0.source)]" }
        }
    }

    private static func appendTestEvidence(_ lines: inout [String], _ summary: TestDiagnosisSummary) {
        lines.append("Test evidence:")
        lines.append("  observed: \(summary.observedEvidence.summary)")
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
            lines.append("  inferred: \(inferredConclusion.summary)")
        }

        if !summary.supportingEvidence.isEmpty {
            lines.append("  supporting evidence:")
            lines += summary.supportingEvidence.map { "    - \($0.kind): \($0.path) [\($0.source)]" }
        }
    }

    private static func appendRuntimeEvidence(_ lines: inout [String], _ summary: RuntimeDiagnosisSummary) {
        lines.append("Runtime evidence:")
        lines.append("  observed: \(summary.observedEvidence.summary)")
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
            lines.append("  inferred: \(inferredConclusion.summary)")
        }

        if !summary.supportingEvidence.isEmpty {
            lines.append("  supporting evidence:")
            lines += summary.supportingEvidence.map { "    - \($0.kind): \($0.path) [\($0.source)]" }
        }
    }

    private static func renderArtifactLine(_ record: WorkflowEvidenceRecord) -> String {
        let reference = record.reference ?? "unavailable"
        return "  - \(record.kind.rawValue) | phase=\(record.phase.rawValue) | attempt=\(record.attemptNumber) | state=\(record.availabilityLabel) | source=\(record.source) | reference=\(reference)"
    }

    private static func renderMissingArtifactLine(_ record: WorkflowEvidenceRecord) -> String {
        var line = "  - \(record.kind.rawValue) | phase=\(record.phase.rawValue) | attempt=\(record.attemptNumber) | state=\(record.availabilityLabel)"
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

    private static func renderLocation(_ location: SourceLocation) -> String {
        var rendered = location.filePath
        if let line = location.line {
            rendered += ":\(line)"
            if let column = location.column {
                rendered += ":\(column)"
            }
        }
        return rendered
    }

    private static func sanitizeInlineField(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: " | ", with: " / ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func shouldExplainMissingBuildEvidence(for result: DiagnosisEvidenceResult) -> Bool {
        result.buildSummary == nil && (result.phase == .diagnosisBuild || result.phase == .diagnosisTest || result.evidenceState == .empty)
    }

    private static func shouldExplainMissingTestEvidence(for result: DiagnosisEvidenceResult) -> Bool {
        result.testSummary == nil && (result.phase == .diagnosisTest || result.evidenceState == .empty)
    }

    private static func shouldExplainMissingRuntimeEvidence(for result: DiagnosisEvidenceResult) -> Bool {
        result.runtimeSummary == nil && (result.phase == .diagnosisRuntime || result.evidenceState == .empty)
    }
}

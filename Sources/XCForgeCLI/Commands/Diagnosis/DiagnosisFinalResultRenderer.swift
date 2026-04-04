import Foundation
import XCForgeKit

enum DiagnosisFinalResultRenderer {
    static func render(_ result: DiagnosisFinalResult) -> String {
        render(result, layout: .wide)
    }

    static func render(_ result: DiagnosisFinalResult, layout: TerminalLayout) -> String {
        var lines: [String] = []

        let prefix: String
        switch layout {
        case .narrow, .medium:
            prefix = WorkflowPresentationHelpers.statusPrefix(
                status: result.status,
                failure: result.failure,
                recoveryHistory: result.recoveryHistory
            )
        case .wide:
            prefix = ""
        }

        appendInvestigationSummary(&lines, result: result, layout: layout, statusPrefix: prefix)
        appendRunContext(&lines, result: result)

        if let currentAttempt = result.currentAttempt {
            appendAttemptBlock(&lines, title: "Current State", attempt: currentAttempt, includeContext: true, layout: layout)
            appendDiagnosisDetail(&lines, attempt: currentAttempt, phase: result.phase)
            appendEvidenceBundle(&lines, title: "Current Evidence Bundle", attempt: currentAttempt, layout: layout)
        } else if result.failure == nil {
            appendMissingDiagnosisDetail(&lines, phase: result.phase)
        }

        appendGuidanceBlock(&lines, result: result)

        if !result.recoveryHistory.isEmpty {
            appendRecoveryNarrative(&lines, result.recoveryHistory, layout: layout)
        }

        appendMeaningfulChange(&lines, result: result)

        if let sourceAttempt = result.sourceAttempt {
            appendAttemptBlock(
                &lines,
                title: "Prior State",
                attempt: sourceAttempt,
                includeContext: sourceAttempt.resolvedContext != result.currentAttempt?.resolvedContext,
                layout: layout
            )
            appendDiagnosisDetail(&lines, attempt: sourceAttempt, phase: sourceAttempt.phase)
            appendEvidenceBundle(&lines, title: "Prior Evidence Bundle", attempt: sourceAttempt, layout: layout)
        }

        if let persistedRunPath = result.persistedRunPath {
            lines.append("Run Record")
            lines.append("  path: \(persistedRunPath)")
        }

        if let failure = result.failure {
            lines.append("Failure Details")
            lines.append("  field: \(failure.field.rawValue)")
            lines.append("  class: \(failure.classification.rawValue)")
            lines.append("  reason: \(sanitizeSummaryField(failure.message))")
        }

        return lines.joined(separator: "\n")
    }

    static func renderJSON(_ result: DiagnosisFinalResult) throws -> String {
        try WorkflowJSONRenderer.renderJSON(result)
    }

    private static func appendRecoveryNarrative(
        _ lines: inout [String],
        _ recoveryHistory: [WorkflowRecoveryRecord],
        layout: TerminalLayout
    ) {
        lines.append("Recovery Narrative")
        lines += recoveryHistory.map { recovery in
            WorkflowPresentationHelpers.formatRecoveryRecord(recovery, layout: layout)
        }
    }

    private static func appendAttemptBlock(
        _ lines: inout [String],
        title: String,
        attempt: DiagnosisCompareAttemptSnapshot,
        includeContext: Bool,
        layout: TerminalLayout
    ) {
        lines.append(title)
        lines.append("  attempt_id: \(attempt.attemptId)")
        lines.append("  attempt_number: \(attempt.attemptNumber)")
        lines.append("  phase: \(attempt.phase.rawValue)")
        lines.append("  status: \(attempt.status.rawValue)")
        lines.append("  summary: \(attempt.summary.headline)")
        if let detail = attempt.summary.detail {
            lines.append("  detail: \(detail)")
        }

        if includeContext {
            switch layout {
            case .narrow:
                lines.append("  resolved_context:")
                lines.append("    project:")
                lines.append("      \(attempt.resolvedContext.project)")
                lines.append("    scheme: \(attempt.resolvedContext.scheme)")
                lines.append("    simulator:")
                lines.append("      \(attempt.resolvedContext.simulator)")
                lines.append("    configuration:")
                lines.append("      \(attempt.resolvedContext.configuration)")
                lines.append("    bundle_id:")
                lines.append("      \(attempt.resolvedContext.app.bundleId)")
                lines.append("    app_path:")
                lines.append("      \(attempt.resolvedContext.app.appPath)")
            case .medium, .wide:
                lines.append("  resolved_context:")
                lines.append("    project: \(attempt.resolvedContext.project)")
                lines.append("    scheme: \(attempt.resolvedContext.scheme)")
                lines.append("    simulator: \(attempt.resolvedContext.simulator)")
                lines.append("    configuration: \(attempt.resolvedContext.configuration)")
                lines.append("    bundle_id: \(attempt.resolvedContext.app.bundleId)")
                lines.append("    app_path: \(attempt.resolvedContext.app.appPath)")
            }
        }
    }

    private static func appendEvidenceBundle(
        _ lines: inout [String],
        title: String,
        attempt: DiagnosisCompareAttemptSnapshot,
        layout: TerminalLayout
    ) {
        lines.append(title)
        lines.append(
            "  counts: \(attempt.availableEvidence.count) available, \(attempt.unavailableEvidence.count) unavailable"
        )

        if !attempt.availableEvidence.isEmpty {
            lines.append("  available:")
            lines += attempt.availableEvidence.map {
                WorkflowPresentationHelpers.formatEvidenceRecord($0, layout: layout)
            }
        }
        if !attempt.unavailableEvidence.isEmpty {
            lines.append("  missing:")
            lines += attempt.unavailableEvidence.map {
                WorkflowPresentationHelpers.formatMissingEvidenceRecord($0, layout: layout)
            }
        }
    }

    private static func sanitizeInlineField(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: " | ", with: " / ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func appendInvestigationSummary(
        _ lines: inout [String],
        result: DiagnosisFinalResult,
        layout: TerminalLayout,
        statusPrefix: String
    ) {
        lines.append("\(statusPrefix)Investigation Summary")
        lines.append(
            "  outcome: \(WorkflowPresentationHelpers.statusLabel(status: result.status, failure: result.failure, recoveryHistory: result.recoveryHistory))"
        )
        lines.append("  workflow: \(result.workflow.rawValue)")
        lines.append("  phase: \(WorkflowPresentationHelpers.phaseLabel(result.phase))")

        if let context = result.currentAttempt?.resolvedContext ?? result.sourceAttempt?.resolvedContext {
            lines.append("  target: \(sanitizeSummaryField(context.scheme)) on \(sanitizeSummaryField(context.simulator)) (\(sanitizeSummaryField(context.configuration)))")
            lines.append("  project: \(sanitizeSummaryField(context.project))")
            lines.append("  app: \(sanitizeSummaryField(context.app.bundleId))")
        }

        if let failure = result.failure {
            lines.append("  finding: \(sanitizeSummaryField(failure.message))")
        } else if let summary = result.summary {
            lines.append("  finding: \(sanitizeSummaryField(summary.headline))")
            if let detail = summary.detail {
                lines.append("  detail: \(sanitizeSummaryField(detail))")
            }
        } else {
            lines.append("  finding: No diagnosis summary is available for this result.")
        }

        lines.append("  evidence: \(WorkflowPresentationHelpers.evidenceSummary(for: result.currentAttempt))")
        lines.append("  proof_cue: \(WorkflowPresentationHelpers.primaryProofCue(for: result.currentAttempt))")
        lines.append("  next_review: \(WorkflowPresentationHelpers.nextReviewAction(for: result))")

        let majorActions = buildMajorActions(for: result)
        if !majorActions.isEmpty {
            lines.append("  actions:")
            lines += majorActions.map { "    - \($0)" }
        }
    }

    private static func appendRunContext(
        _ lines: inout [String],
        result: DiagnosisFinalResult
    ) {
        lines.append("Run Context")
        lines.append("  workflow: \(result.workflow.rawValue)")
        if let runId = result.runId {
            lines.append("  run_id: \(runId)")
        }
        if let attemptId = result.attemptId {
            lines.append("  attempt_id: \(attemptId)")
        }
        if let sourceAttemptId = result.sourceAttemptId {
            lines.append("  source_attempt_id: \(sourceAttemptId)")
        }
        if let phase = result.phase {
            lines.append("  canonical_phase: \(phase.rawValue)")
        }
        if let status = result.status {
            lines.append("  canonical_status: \(status.rawValue)")
        }
        if let context = result.currentAttempt?.resolvedContext ?? result.sourceAttempt?.resolvedContext {
            lines.append("  project: \(sanitizeSummaryField(context.project))")
            lines.append("  scheme: \(sanitizeSummaryField(context.scheme))")
            lines.append("  simulator: \(sanitizeSummaryField(context.simulator))")
            lines.append("  configuration: \(sanitizeSummaryField(context.configuration))")
            lines.append("  bundle_id: \(sanitizeSummaryField(context.app.bundleId))")
            lines.append("  app_path: \(sanitizeSummaryField(context.app.appPath))")
        }
    }

    private static func appendMeaningfulChange(
        _ lines: inout [String],
        result: DiagnosisFinalResult
    ) {
        lines.append("Meaningful Change")

        if let comparison = result.comparison {
            lines.append("  outcome: \(comparison.outcome.rawValue)")
            if comparison.changedEvidence.isEmpty {
                lines.append("  changed evidence: none recorded")
            } else {
                lines.append("  changed evidence:")
                lines += comparison.changedEvidence.map { change in
                    "    - \(change.field): \(change.priorValue) -> \(change.currentValue)"
                }
            }

            if comparison.unchangedBlockers.isEmpty {
                lines.append("  unchanged blockers: none")
            } else {
                lines.append("  unchanged blockers:")
                lines += comparison.unchangedBlockers.map { "    - \($0)" }
            }
            return
        }

        if let comparisonNote = result.comparisonNote {
            lines.append("  \(sanitizeSummaryField(comparisonNote))")
        } else if result.sourceAttemptId != nil {
            lines.append("  comparison unavailable for the linked rerun attempt.")
        } else {
            lines.append("  no prior attempt was linked to this terminal result.")
        }
    }

    private static func buildMajorActions(for result: DiagnosisFinalResult) -> [String] {
        var actions: [String] = []

        if let currentAttempt = result.currentAttempt {
            actions.append(
                "Finalized \(WorkflowPresentationHelpers.phaseLabel(currentAttempt.phase)) on attempt \(currentAttempt.attemptNumber)."
            )
        } else if let phase = result.phase {
            actions.append("Finalized \(WorkflowPresentationHelpers.phaseLabel(phase)).")
        }

        if !result.recoveryHistory.isEmpty {
            let count = result.recoveryHistory.count
            let label = count == 1 ? "recovery action" : "recovery actions"
            actions.append("Recorded \(count) \(label) before the terminal result.")
        }

        if let sourceAttemptId = result.sourceAttemptId {
            actions.append("Linked this terminal result to source attempt \(sourceAttemptId) for rerun review.")
        } else if result.comparisonNote != nil {
            actions.append("Preserved the terminal result without a complete rerun comparison.")
        }

        return actions
    }

    private static func appendDiagnosisDetail(
        _ lines: inout [String],
        attempt: DiagnosisCompareAttemptSnapshot,
        phase: WorkflowPhase?
    ) {
        let hasBuild = attempt.diagnosisSummary != nil
        let hasTest = attempt.testDiagnosisSummary != nil
        let hasRuntime = attempt.runtimeSummary != nil

        if !hasBuild && !hasTest && !hasRuntime {
            appendMissingDiagnosisDetail(&lines, phase: phase)
            return
        }

        lines.append("Diagnosis Detail")

        if let buildSummary = attempt.diagnosisSummary {
            appendBuildDiagnosisDetail(&lines, buildSummary)
        }

        if let testSummary = attempt.testDiagnosisSummary {
            appendTestDiagnosisDetail(&lines, testSummary)
        }

        if let runtimeSummary = attempt.runtimeSummary {
            appendRuntimeDiagnosisDetail(&lines, runtimeSummary)
        }
    }

    private static func appendBuildDiagnosisDetail(
        _ lines: inout [String],
        _ summary: BuildDiagnosisSummary
    ) {
        lines.append("  Build Observed Evidence")
        lines.append("    summary: \(sanitizeSummaryField(summary.observedEvidence.summary))")
        if let primarySignal = summary.observedEvidence.primarySignal {
            lines.append("    primary_signal: \(sanitizeSummaryField(primarySignal.message))")
            lines.append("    severity: \(primarySignal.severity.rawValue)")
            if let location = primarySignal.location {
                lines.append("    location: \(renderLocation(location))")
            }
        }
        lines.append(
            "    counts: errors=\(summary.observedEvidence.errorCount), warnings=\(summary.observedEvidence.warningCount), analyzer_warnings=\(summary.observedEvidence.analyzerWarningCount)"
        )

        if let conclusion = summary.inferredConclusion {
            lines.append("  Build Inferred Conclusion")
            lines.append("    summary: \(sanitizeSummaryField(conclusion.summary))")
        }

        if !summary.supportingEvidence.isEmpty {
            lines.append("  build supporting evidence:")
            lines += summary.supportingEvidence.map { "    - \($0.kind): \($0.path) [\($0.source)]" }
        }
    }

    private static func appendTestDiagnosisDetail(
        _ lines: inout [String],
        _ summary: TestDiagnosisSummary
    ) {
        lines.append("  Test Observed Evidence")
        lines.append("    summary: \(sanitizeSummaryField(summary.observedEvidence.summary))")
        if let primaryFailure = summary.observedEvidence.primaryFailure {
            lines.append("    primary_test: \(primaryFailure.testName)")
            lines.append("    test_identifier: \(primaryFailure.testIdentifier)")
            lines.append("    failure_message: \(sanitizeSummaryField(primaryFailure.message))")
        }
        lines.append(
            "    counts: total=\(summary.observedEvidence.totalTestCount), failed=\(summary.observedEvidence.failedTestCount), passed=\(summary.observedEvidence.passedTestCount), skipped=\(summary.observedEvidence.skippedTestCount)"
        )

        if let conclusion = summary.inferredConclusion {
            lines.append("  Test Inferred Conclusion")
            lines.append("    summary: \(sanitizeSummaryField(conclusion.summary))")
        }

        if !summary.supportingEvidence.isEmpty {
            lines.append("  test supporting evidence:")
            lines += summary.supportingEvidence.map { "    - \($0.kind): \($0.path) [\($0.source)]" }
        }
    }

    private static func appendRuntimeDiagnosisDetail(
        _ lines: inout [String],
        _ summary: RuntimeDiagnosisSummary
    ) {
        lines.append("  Runtime Observed Evidence")
        lines.append("    summary: \(sanitizeSummaryField(summary.observedEvidence.summary))")
        if let primarySignal = summary.observedEvidence.primarySignal {
            lines.append("    primary_signal: \(sanitizeSummaryField(primarySignal.message))")
        }
        lines.append(
            "    app_state: launched=\(summary.observedEvidence.launchedApp), running=\(summary.observedEvidence.appRunning), relaunched=\(summary.observedEvidence.relaunchedApp)"
        )
        lines.append(
            "    output: stdout_lines=\(summary.observedEvidence.stdoutLineCount), stderr_lines=\(summary.observedEvidence.stderrLineCount)"
        )

        if let conclusion = summary.inferredConclusion {
            lines.append("  Runtime Inferred Conclusion")
            lines.append("    summary: \(sanitizeSummaryField(conclusion.summary))")
        }

        if !summary.supportingEvidence.isEmpty {
            lines.append("  runtime supporting evidence:")
            lines += summary.supportingEvidence.map { "    - \($0.kind): \($0.path) [\($0.source)]" }
        }
    }

    private static func appendMissingDiagnosisDetail(
        _ lines: inout [String],
        phase: WorkflowPhase?
    ) {
        lines.append("Diagnosis Detail")
        lines.append("  \(WorkflowPresentationHelpers.missingDiagnosisExplanation(phase: phase))")
    }

    private static func appendGuidanceBlock(
        _ lines: inout [String],
        result: DiagnosisFinalResult
    ) {
        lines += WorkflowPresentationHelpers.guidanceBlock(for: result)
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

    private static func sanitizeSummaryField(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

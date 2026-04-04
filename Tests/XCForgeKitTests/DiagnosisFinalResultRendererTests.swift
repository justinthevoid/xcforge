import Foundation
import Testing
@testable import XCForgeCLI
@testable import XCForgeKit

@Suite("DiagnosisFinalResultRenderer", .serialized)
struct DiagnosisFinalResultRendererTests {

    @Test("render presents a summary-first review surface for terminal results")
    func renderPresentsSummaryFirstReviewSurfaceForTerminalResults() {
        let result = DiagnosisFinalResult(
            phase: .diagnosisBuild,
            status: .failed,
            runId: "run-build",
            attemptId: "attempt-1",
            sourceAttemptId: nil,
            summary: DiagnosisStatusSummary(
                source: .build,
                headline: "Build failed with a primary compiler error.",
                detail: "Cannot find 'WidgetView' in scope"
            ),
            recoveryHistory: [],
            currentAttempt: makeAttempt(
                attemptId: "attempt-1",
                attemptNumber: 1,
                phase: .diagnosisBuild,
                status: .failed,
                summary: DiagnosisStatusSummary(
                    source: .build,
                    headline: "Build failed with a primary compiler error.",
                    detail: "Cannot find 'WidgetView' in scope"
                ),
                evidence: [
                    makeEvidence(
                        kind: .buildSummary,
                        phase: .diagnosisBuild,
                        attemptId: "attempt-1",
                        attemptNumber: 1,
                        availability: .available,
                        reference: "run_record.diagnosisSummary",
                        source: "xcforge.diagnosis_build.summary"
                    ),
                    makeEvidence(
                        kind: .xcresult,
                        phase: .diagnosisBuild,
                        attemptId: "attempt-1",
                        attemptNumber: 1,
                        availability: .available,
                        reference: "/tmp/final-build.xcresult",
                        source: "xcodebuild.result_bundle"
                    )
                ]
            ),
            sourceAttempt: nil,
            comparison: nil,
            failure: nil,
            persistedRunPath: "/tmp/run-build.json"
        )

        let rendered = DiagnosisFinalResultRenderer.render(result.withDerivedFollowOnAction())

        #expect(rendered.contains("Investigation Summary"))
        #expect(rendered.contains("  outcome: Failed diagnosis"))
        #expect(rendered.contains("  target: App on iPhone 16 Pro (Debug)"))
        #expect(rendered.contains("  project: /tmp/App.xcodeproj"))
        #expect(rendered.contains("  app: com.example.app"))
        #expect(rendered.contains("  finding: Build failed with a primary compiler error."))
        #expect(rendered.contains("  evidence: 2 available, 0 missing"))
        #expect(rendered.contains("  proof_cue: Best available artifact: xcresult from attempt 1."))
        #expect(rendered.contains("  next_review: Inspect Current Evidence Bundle below."))
        #expect(rendered.contains("Current Evidence Bundle"))
        #expect(rendered.contains("Meaningful Change"))
        assertSectionOrder(
            rendered,
            sections: [
                "Investigation Summary",
                "Run Context",
                "Current State",
                "Diagnosis Detail",
                "Current Evidence Bundle",
                "Next Step",
                "Meaningful Change",
                "Run Record"
            ]
        )
    }

    @Test("render keeps recovery and rerun review details below the summary")
    func renderKeepsRecoveryAndRerunReviewDetailsBelowTheSummary() {
        let recoveryRecord = WorkflowRecoveryRecord(
            recoveryId: "recovery-1",
            sourceAttemptId: "attempt-1",
            sourceAttemptNumber: 1,
            triggeringAttemptId: "attempt-2",
            triggeringAttemptNumber: 2,
            recoveryAttemptId: "attempt-3",
            recoveryAttemptNumber: 3,
            issue: .brokenLaunchContinuity,
            detectedIssue: "App did not stay running through runtime capture.",
            action: .resetLaunchContinuity,
            status: .succeeded,
            resumed: true,
            summary: "Recovered from broken launch continuity and resumed runtime diagnosis.",
            detail: "Reset launch state before retrying.",
            recordedAt: Date(timeIntervalSince1970: 1_743_700_220)
        )

        let priorAttempt = makeAttempt(
            attemptId: "attempt-2",
            attemptNumber: 2,
            phase: .diagnosisRuntime,
            status: .partial,
            summary: DiagnosisStatusSummary(
                source: .runtime,
                headline: "Runtime inspection ended before the app stayed running.",
                detail: "launchctl print stalled"
            ),
            evidence: [
                makeEvidence(
                    kind: .runtimeSummary,
                    phase: .diagnosisRuntime,
                    attemptId: "attempt-2",
                    attemptNumber: 2,
                    availability: .available,
                    reference: "run_record.runtimeSummary",
                    source: "xcforge.diagnosis_runtime.summary"
                )
            ]
        )

        let currentAttempt = makeAttempt(
            attemptId: "attempt-3",
            attemptNumber: 3,
            phase: .diagnosisRuntime,
            status: .succeeded,
            summary: DiagnosisStatusSummary(
                source: .runtime,
                headline: "Runtime inspection reached a running app state.",
                detail: "Application ready"
            ),
            evidence: [
                makeEvidence(
                    kind: .consoleLog,
                    phase: .diagnosisRuntime,
                    attemptId: "attempt-3",
                    attemptNumber: 3,
                    availability: .available,
                    reference: "/tmp/runtime.log",
                    source: "simctl.launch_console"
                )
            ]
        )

        let result = DiagnosisFinalResult(
            phase: .diagnosisRuntime,
            status: .succeeded,
            runId: "run-runtime",
            attemptId: "attempt-3",
            sourceAttemptId: "attempt-2",
            summary: DiagnosisStatusSummary(
                source: .runtime,
                headline: "Runtime inspection reached a running app state.",
                detail: "Application ready"
            ),
            recoveryHistory: [recoveryRecord],
            currentAttempt: currentAttempt,
            sourceAttempt: priorAttempt,
            comparison: DiagnosisFinalComparison(
                outcome: .improved,
                changedEvidence: [
                    DiagnosisComparisonChange(
                        field: "Overall status",
                        priorValue: "partial",
                        currentValue: "succeeded"
                    )
                ],
                unchangedBlockers: []
            ),
            comparisonNote: nil,
            failure: nil,
            persistedRunPath: "/tmp/run-runtime.json"
        )

        let rendered = DiagnosisFinalResultRenderer.render(result.withDerivedFollowOnAction())

        #expect(rendered.contains("  outcome: Verified success"))
        #expect(rendered.contains("  next_review: Review Recovery Narrative below."))
        #expect(rendered.contains("Recorded 1 recovery action before the terminal result."))
        #expect(rendered.contains("Linked this terminal result to source attempt attempt-2 for rerun review."))
        #expect(rendered.contains("Recovery Narrative"))
        #expect(rendered.contains("Meaningful Change"))
        #expect(rendered.contains("  outcome: improved"))
        #expect(rendered.contains("Prior State"))
        assertSectionOrder(
            rendered,
            sections: [
                "Investigation Summary",
                "Run Context",
                "Current State",
                "Diagnosis Detail",
                "Current Evidence Bundle",
                "Next Step",
                "Recovery Narrative",
                "Meaningful Change",
                "Prior State",
                "Prior Evidence Bundle"
            ]
        )
    }

    @Test("render uses explicit textual fallback when proof is missing or the result failed before assembly")
    func renderUsesExplicitTextualFallbackWhenProofIsMissingOrTheResultFailedBeforeAssembly() {
        let missingProofResult = DiagnosisFinalResult(
            phase: .diagnosisRuntime,
            status: .partial,
            runId: "run-partial",
            attemptId: "attempt-4",
            sourceAttemptId: nil,
            summary: DiagnosisStatusSummary(
                source: .runtime,
                headline: "Runtime capture ended without a usable screenshot artifact.",
                detail: "Screenshot capture is unsupported for the active launch path."
            ),
            recoveryHistory: [],
            currentAttempt: makeAttempt(
                attemptId: "attempt-4",
                attemptNumber: 4,
                phase: .diagnosisRuntime,
                status: .partial,
                summary: DiagnosisStatusSummary(
                    source: .runtime,
                    headline: "Runtime capture ended without a usable screenshot artifact.",
                    detail: "Screenshot capture is unsupported for the active launch path."
                ),
                evidence: [
                    makeEvidence(
                        kind: .screenshot,
                        phase: .diagnosisRuntime,
                        attemptId: "attempt-4",
                        attemptNumber: 4,
                        availability: .unavailable,
                        unavailableReason: .unsupported,
                        reference: nil,
                        source: "simctl.io.screenshot",
                        detail: "Screenshot capture requires a supported launch path."
                    )
                ]
            ),
            sourceAttempt: nil,
            comparison: nil,
            comparisonNote: nil,
            failure: nil,
            persistedRunPath: nil
        )

        let failedAssemblyResult = DiagnosisFinalResult(
            phase: nil,
            status: nil,
            runId: "missing-run",
            attemptId: nil,
            sourceAttemptId: nil,
            summary: nil,
            recoveryHistory: [],
            currentAttempt: nil,
            sourceAttempt: nil,
            comparison: nil,
            comparisonNote: nil,
            failure: WorkflowFailure(
                field: .run,
                classification: .notFound,
                message: "No diagnosis run was found for run ID missing-run."
            ),
            persistedRunPath: nil
        )

        let missingProofRendered = DiagnosisFinalResultRenderer.render(missingProofResult)
        let failedAssemblyRendered = DiagnosisFinalResultRenderer.render(failedAssemblyResult)

        #expect(missingProofRendered.contains("  outcome: Partial result"))
        #expect(missingProofRendered.contains("  evidence: 0 available, 1 missing"))
        #expect(missingProofRendered.contains("  proof_cue: Best available artifact is missing: screenshot for attempt 4 (unsupported)."))
        #expect(missingProofRendered.contains("  next_review: Review missing evidence notes in Current Evidence Bundle below."))

        #expect(failedAssemblyRendered.contains("  outcome: Result unavailable"))
        #expect(failedAssemblyRendered.contains("  finding: No diagnosis run was found for run ID missing-run."))
        #expect(failedAssemblyRendered.contains("  next_review: Inspect Failure Details below."))
        #expect(failedAssemblyRendered.contains("Failure Details"))
    }

    @Test("render keeps blocked and unsupported terminal states explicit in text")
    func renderKeepsBlockedAndUnsupportedTerminalStatesExplicitInText() {
        let blockedResult = DiagnosisFinalResult(
            phase: .diagnosisRuntime,
            status: .failed,
            runId: "run-blocked",
            attemptId: "attempt-5",
            sourceAttemptId: nil,
            summary: DiagnosisStatusSummary(
                source: .runtime,
                headline: "Runtime inspection stopped after environment recovery failed."
            ),
            recoveryHistory: [
                WorkflowRecoveryRecord(
                    recoveryId: "recovery-2",
                    sourceAttemptId: "attempt-4",
                    sourceAttemptNumber: 4,
                    triggeringAttemptId: "attempt-5",
                    triggeringAttemptNumber: 5,
                    recoveryAttemptId: "attempt-6",
                    recoveryAttemptNumber: 6,
                    issue: .staleSimulatorState,
                    detectedIssue: "Simulator continuity was stale.",
                    action: .resetLaunchContinuity,
                    status: .failed,
                    resumed: false,
                    summary: "Recovery did not restore a usable runtime path.",
                    detail: nil,
                    recordedAt: Date(timeIntervalSince1970: 1_743_700_300)
                )
            ],
            currentAttempt: makeAttempt(
                attemptId: "attempt-5",
                attemptNumber: 5,
                phase: .diagnosisRuntime,
                status: .failed,
                summary: DiagnosisStatusSummary(
                    source: .runtime,
                    headline: "Runtime inspection stopped after environment recovery failed."
                ),
                evidence: []
            ),
            sourceAttempt: nil,
            comparison: nil,
            failure: nil,
            persistedRunPath: nil
        )

        let unsupportedResult = DiagnosisFinalResult(
            phase: .diagnosisRuntime,
            status: .unsupported,
            runId: "run-unsupported",
            attemptId: "attempt-7",
            sourceAttemptId: nil,
            summary: DiagnosisStatusSummary(
                source: .runtime,
                headline: "Runtime screenshot capture is unsupported for the active launch path."
            ),
            recoveryHistory: [],
            currentAttempt: makeAttempt(
                attemptId: "attempt-7",
                attemptNumber: 7,
                phase: .diagnosisRuntime,
                status: .unsupported,
                summary: DiagnosisStatusSummary(
                    source: .runtime,
                    headline: "Runtime screenshot capture is unsupported for the active launch path."
                ),
                evidence: []
            ),
            sourceAttempt: nil,
            comparison: nil,
            failure: nil,
            persistedRunPath: nil
        )

        let blockedRendered = DiagnosisFinalResultRenderer.render(blockedResult)
        let unsupportedRendered = DiagnosisFinalResultRenderer.render(unsupportedResult)

        #expect(blockedRendered.contains("  outcome: Blocked by environment"))
        #expect(blockedRendered.contains("  next_review: Review Recovery Narrative below."))
        #expect(blockedRendered.contains("Recovery Narrative"))
        #expect(unsupportedRendered.contains("  outcome: Unsupported result"))
        #expect(unsupportedRendered.contains("  next_review: Review Current Evidence Bundle below."))
    }

    @Test("render separates build observed evidence from inferred conclusion with distinct headers")
    func renderSeparatesBuildObservedEvidenceFromInferredConclusion() {
        let buildDiagnosis = BuildDiagnosisSummary(
            observedEvidence: ObservedBuildEvidence(
                summary: "Build failed with 2 errors in WidgetView.swift.",
                primarySignal: BuildIssueSummary(
                    severity: .error,
                    message: "Cannot find 'WidgetView' in scope",
                    location: SourceLocation(filePath: "Sources/App/WidgetView.swift", line: 14, column: 5),
                    source: "swiftc"
                ),
                additionalIssueCount: 1,
                errorCount: 2,
                warningCount: 0,
                analyzerWarningCount: 0
            ),
            inferredConclusion: InferredBuildConclusion(
                summary: "The WidgetView type was removed or renamed in a recent refactor."
            ),
            supportingEvidence: []
        )

        let result = DiagnosisFinalResult(
            phase: .diagnosisBuild,
            status: .failed,
            runId: "run-build-diag",
            attemptId: "attempt-1",
            sourceAttemptId: nil,
            summary: DiagnosisStatusSummary(source: .build, headline: "Build failed."),
            recoveryHistory: [],
            currentAttempt: makeAttempt(
                attemptId: "attempt-1",
                attemptNumber: 1,
                phase: .diagnosisBuild,
                status: .failed,
                summary: DiagnosisStatusSummary(source: .build, headline: "Build failed."),
                diagnosisSummary: buildDiagnosis,
                evidence: []
            ),
            sourceAttempt: nil,
            comparison: nil,
            failure: nil,
            persistedRunPath: nil
        )

        let rendered = DiagnosisFinalResultRenderer.render(result.withDerivedFollowOnAction())

        #expect(rendered.contains("Diagnosis Detail"))
        #expect(rendered.contains("  Build Observed Evidence"))
        #expect(rendered.contains("    summary: Build failed with 2 errors in WidgetView.swift."))
        #expect(rendered.contains("    primary_signal: Cannot find 'WidgetView' in scope"))
        #expect(rendered.contains("    severity: error"))
        #expect(rendered.contains("    location: Sources/App/WidgetView.swift:14:5"))
        #expect(rendered.contains("    counts: errors=2, warnings=0, analyzer_warnings=0"))
        #expect(rendered.contains("  Build Inferred Conclusion"))
        #expect(rendered.contains("    summary: The WidgetView type was removed or renamed in a recent refactor."))
        assertSectionOrder(
            rendered,
            sections: [
                "Investigation Summary",
                "Current State",
                "Diagnosis Detail",
                "Build Observed Evidence",
                "Build Inferred Conclusion",
                "Current Evidence Bundle",
                "Next Step"
            ]
        )
    }

    @Test("render separates test observed evidence from inferred conclusion with distinct headers")
    func renderSeparatesTestObservedEvidenceFromInferredConclusion() {
        let testDiagnosis = TestDiagnosisSummary(
            observedEvidence: ObservedTestEvidence(
                summary: "3 of 10 tests failed.",
                primaryFailure: TestFailureSummary(
                    testName: "testWidgetRendering",
                    testIdentifier: "WidgetTests/testWidgetRendering",
                    message: "Expected view to contain 'Hello' but found empty view.",
                    source: "XCTest"
                ),
                additionalFailureCount: 2,
                totalTestCount: 10,
                failedTestCount: 3,
                passedTestCount: 7,
                skippedTestCount: 0,
                expectedFailureCount: 0
            ),
            inferredConclusion: InferredTestConclusion(
                summary: "Widget rendering tests regressed after the layout refactor."
            ),
            supportingEvidence: []
        )

        let result = DiagnosisFinalResult(
            phase: .diagnosisTest,
            status: .failed,
            runId: "run-test-diag",
            attemptId: "attempt-1",
            sourceAttemptId: nil,
            summary: DiagnosisStatusSummary(source: .test, headline: "Tests failed."),
            recoveryHistory: [],
            currentAttempt: makeAttempt(
                attemptId: "attempt-1",
                attemptNumber: 1,
                phase: .diagnosisTest,
                status: .failed,
                summary: DiagnosisStatusSummary(source: .test, headline: "Tests failed."),
                testDiagnosisSummary: testDiagnosis,
                evidence: []
            ),
            sourceAttempt: nil,
            comparison: nil,
            failure: nil,
            persistedRunPath: nil
        )

        let rendered = DiagnosisFinalResultRenderer.render(result.withDerivedFollowOnAction())

        #expect(rendered.contains("Diagnosis Detail"))
        #expect(rendered.contains("  Test Observed Evidence"))
        #expect(rendered.contains("    summary: 3 of 10 tests failed."))
        #expect(rendered.contains("    primary_test: testWidgetRendering"))
        #expect(rendered.contains("    test_identifier: WidgetTests/testWidgetRendering"))
        #expect(rendered.contains("    failure_message: Expected view to contain 'Hello' but found empty view."))
        #expect(rendered.contains("    counts: total=10, failed=3, passed=7, skipped=0"))
        #expect(rendered.contains("  Test Inferred Conclusion"))
        #expect(rendered.contains("    summary: Widget rendering tests regressed after the layout refactor."))
        assertSectionOrder(
            rendered,
            sections: [
                "Investigation Summary",
                "Current State",
                "Diagnosis Detail",
                "Test Observed Evidence",
                "Test Inferred Conclusion",
                "Current Evidence Bundle",
                "Next Step"
            ]
        )
    }

    @Test("render omits inferred section when conclusion is nil")
    func renderOmitsInferredSectionWhenConclusionIsNil() {
        let buildDiagnosis = BuildDiagnosisSummary(
            observedEvidence: ObservedBuildEvidence(
                summary: "Build failed with 1 error.",
                primarySignal: nil,
                additionalIssueCount: 0,
                errorCount: 1,
                warningCount: 0,
                analyzerWarningCount: 0
            ),
            inferredConclusion: nil,
            supportingEvidence: []
        )

        let result = DiagnosisFinalResult(
            phase: .diagnosisBuild,
            status: .failed,
            runId: "run-no-conclusion",
            attemptId: "attempt-1",
            sourceAttemptId: nil,
            summary: DiagnosisStatusSummary(source: .build, headline: "Build failed."),
            recoveryHistory: [],
            currentAttempt: makeAttempt(
                attemptId: "attempt-1",
                attemptNumber: 1,
                phase: .diagnosisBuild,
                status: .failed,
                summary: DiagnosisStatusSummary(source: .build, headline: "Build failed."),
                diagnosisSummary: buildDiagnosis,
                evidence: []
            ),
            sourceAttempt: nil,
            comparison: nil,
            failure: nil,
            persistedRunPath: nil
        )

        let rendered = DiagnosisFinalResultRenderer.render(result.withDerivedFollowOnAction())

        #expect(rendered.contains("  Build Observed Evidence"))
        #expect(!rendered.contains("Build Inferred Conclusion"))
    }

    @Test("render shows explicit empty state when no diagnosis detail is available")
    func renderShowsExplicitEmptyStateWhenNoDiagnosisDetailIsAvailable() {
        let result = DiagnosisFinalResult(
            phase: .diagnosisBuild,
            status: .failed,
            runId: "run-no-diag",
            attemptId: "attempt-1",
            sourceAttemptId: nil,
            summary: DiagnosisStatusSummary(source: .build, headline: "Build failed."),
            recoveryHistory: [],
            currentAttempt: makeAttempt(
                attemptId: "attempt-1",
                attemptNumber: 1,
                phase: .diagnosisBuild,
                status: .failed,
                summary: DiagnosisStatusSummary(source: .build, headline: "Build failed."),
                evidence: []
            ),
            sourceAttempt: nil,
            comparison: nil,
            failure: nil,
            persistedRunPath: nil
        )

        let rendered = DiagnosisFinalResultRenderer.render(result.withDerivedFollowOnAction())

        #expect(rendered.contains("Diagnosis Detail"))
        #expect(rendered.contains("No diagnosis detail is available. Producing step: build diagnosis"))
    }

    @Test("render shows missing diagnosis empty state for test phase")
    func renderShowsMissingDiagnosisEmptyStateForTestPhase() {
        let result = DiagnosisFinalResult(
            phase: .diagnosisTest,
            status: .failed,
            runId: "run-no-test-diag",
            attemptId: "attempt-1",
            sourceAttemptId: nil,
            summary: DiagnosisStatusSummary(source: .test, headline: "Tests failed."),
            recoveryHistory: [],
            currentAttempt: makeAttempt(
                attemptId: "attempt-1",
                attemptNumber: 1,
                phase: .diagnosisTest,
                status: .failed,
                summary: DiagnosisStatusSummary(source: .test, headline: "Tests failed."),
                evidence: []
            ),
            sourceAttempt: nil,
            comparison: nil,
            failure: nil,
            persistedRunPath: nil
        )

        let rendered = DiagnosisFinalResultRenderer.render(result.withDerivedFollowOnAction())

        #expect(rendered.contains("No diagnosis detail is available. Producing step: test diagnosis"))
    }

    @Test("render presents guidance block structurally separate from diagnosis and evidence")
    func renderPresentsGuidanceBlockStructurallySeparateFromDiagnosisAndEvidence() {
        let buildDiagnosis = BuildDiagnosisSummary(
            observedEvidence: ObservedBuildEvidence(
                summary: "Build succeeded.",
                primarySignal: nil,
                additionalIssueCount: 0,
                errorCount: 0,
                warningCount: 1,
                analyzerWarningCount: 0
            ),
            inferredConclusion: nil,
            supportingEvidence: []
        )

        let result = DiagnosisFinalResult(
            phase: .diagnosisBuild,
            status: .succeeded,
            runId: "run-guidance",
            attemptId: "attempt-1",
            sourceAttemptId: nil,
            summary: DiagnosisStatusSummary(source: .build, headline: "Build succeeded."),
            recoveryHistory: [],
            currentAttempt: makeAttempt(
                attemptId: "attempt-1",
                attemptNumber: 1,
                phase: .diagnosisBuild,
                status: .succeeded,
                summary: DiagnosisStatusSummary(source: .build, headline: "Build succeeded."),
                diagnosisSummary: buildDiagnosis,
                evidence: [
                    makeEvidence(
                        kind: .buildSummary,
                        phase: .diagnosisBuild,
                        attemptId: "attempt-1",
                        attemptNumber: 1,
                        availability: .available,
                        reference: "run_record.diagnosisSummary",
                        source: "xcforge.diagnosis_build.summary"
                    )
                ]
            ),
            sourceAttempt: nil,
            comparison: nil,
            failure: nil,
            persistedRunPath: nil
        )

        let rendered = DiagnosisFinalResultRenderer.render(result.withDerivedFollowOnAction())

        #expect(rendered.contains("Next Step"))
        #expect(rendered.contains("  suggested_action: Review evidence to confirm the result meets expectations."))
        #expect(rendered.contains("  rationale: build diagnosis completed successfully."))
        #expect(rendered.contains("  confidence: inferred"))
        assertSectionOrder(
            rendered,
            sections: [
                "Investigation Summary",
                "Current State",
                "Diagnosis Detail",
                "Current Evidence Bundle",
                "Next Step",
                "Meaningful Change"
            ]
        )
    }

    @Test("render presents follow-on guidance for failure with action-oriented label")
    func renderPresentsFollowOnGuidanceForFailureWithActionOrientedLabel() {
        let result = DiagnosisFinalResult(
            phase: nil,
            status: nil,
            runId: "run-no-evidence",
            attemptId: nil,
            sourceAttemptId: nil,
            summary: nil,
            recoveryHistory: [],
            currentAttempt: nil,
            sourceAttempt: nil,
            comparison: nil,
            followOnAction: WorkflowFollowOnAction(
                action: "Review the failure details and address the root cause before retrying.",
                rationale: "Workflow failed at run: No run found.",
                confidence: .evidenceSupported
            ),
            failure: WorkflowFailure(
                field: .run,
                classification: .notFound,
                message: "No run found."
            ),
            persistedRunPath: nil
        )

        let rendered = DiagnosisFinalResultRenderer.render(result.withDerivedFollowOnAction())

        #expect(rendered.contains("Next Step"))
        #expect(rendered.contains("  suggested_action: Review the failure details and address the root cause before retrying."))
        #expect(rendered.contains("  rationale: Workflow failed at run: No run found."))
        #expect(rendered.contains("  confidence: evidence_supported"))
        #expect(!rendered.contains("Diagnosis Detail"))
    }

    @Test("render with narrow layout uses stacked evidence format and status prefix on header")
    func renderWithNarrowLayoutUsesStackedEvidenceFormatAndStatusPrefix() {
        let result = DiagnosisFinalResult(
            phase: .diagnosisBuild,
            status: .failed,
            runId: "run-narrow",
            attemptId: "attempt-1",
            sourceAttemptId: nil,
            summary: DiagnosisStatusSummary(
                source: .build,
                headline: "Build failed.",
                detail: "Missing symbol"
            ),
            recoveryHistory: [],
            currentAttempt: makeAttempt(
                attemptId: "attempt-1",
                attemptNumber: 1,
                phase: .diagnosisBuild,
                status: .failed,
                summary: DiagnosisStatusSummary(source: .build, headline: "Build failed.", detail: "Missing symbol"),
                evidence: [
                    makeEvidence(
                        kind: .xcresult,
                        phase: .diagnosisBuild,
                        attemptId: "attempt-1",
                        attemptNumber: 1,
                        availability: .available,
                        reference: "/tmp/build.xcresult",
                        source: "xcodebuild.result_bundle"
                    )
                ]
            ),
            sourceAttempt: nil,
            comparison: nil,
            failure: nil,
            persistedRunPath: nil
        )

        let rendered = DiagnosisFinalResultRenderer.render(result.withDerivedFollowOnAction(), layout: .narrow)

        #expect(rendered.contains("[FAILED] Investigation Summary"))
        #expect(rendered.contains("    phase: diagnosis_build"))
        #expect(rendered.contains("    attempt: 1"))
        #expect(rendered.contains("    source: xcodebuild.result_bundle"))
        assertSectionOrder(
            rendered,
            sections: [
                "Investigation Summary",
                "Run Context",
                "Current State",
                "Current Evidence Bundle",
                "Next Step",
                "Meaningful Change"
            ]
        )
    }

    @Test("render with medium layout wraps evidence lines and includes status prefix")
    func renderWithMediumLayoutWrapsEvidenceLinesAndIncludesStatusPrefix() {
        let result = DiagnosisFinalResult(
            phase: .diagnosisBuild,
            status: .succeeded,
            runId: "run-medium",
            attemptId: "attempt-1",
            sourceAttemptId: nil,
            summary: DiagnosisStatusSummary(source: .build, headline: "Build succeeded."),
            recoveryHistory: [],
            currentAttempt: makeAttempt(
                attemptId: "attempt-1",
                attemptNumber: 1,
                phase: .diagnosisBuild,
                status: .succeeded,
                summary: DiagnosisStatusSummary(source: .build, headline: "Build succeeded."),
                evidence: [
                    makeEvidence(
                        kind: .buildSummary,
                        phase: .diagnosisBuild,
                        attemptId: "attempt-1",
                        attemptNumber: 1,
                        availability: .available,
                        reference: "run_record.diagnosisSummary",
                        source: "xcforge.diagnosis_build.summary"
                    )
                ]
            ),
            sourceAttempt: nil,
            comparison: nil,
            failure: nil,
            persistedRunPath: nil
        )

        let rendered = DiagnosisFinalResultRenderer.render(result.withDerivedFollowOnAction(), layout: .medium)

        #expect(rendered.contains("[OK] Investigation Summary"))
        #expect(rendered.contains("    - build_summary | phase=diagnosis_build | attempt=1"))
        #expect(rendered.contains("      state="))
    }

    @Test("render with wide layout matches default output format")
    func renderWithWideLayoutMatchesDefaultOutputFormat() {
        let result = DiagnosisFinalResult(
            phase: .diagnosisBuild,
            status: .failed,
            runId: "run-wide",
            attemptId: "attempt-1",
            sourceAttemptId: nil,
            summary: DiagnosisStatusSummary(source: .build, headline: "Build failed."),
            recoveryHistory: [],
            currentAttempt: makeAttempt(
                attemptId: "attempt-1",
                attemptNumber: 1,
                phase: .diagnosisBuild,
                status: .failed,
                summary: DiagnosisStatusSummary(source: .build, headline: "Build failed."),
                evidence: []
            ),
            sourceAttempt: nil,
            comparison: nil,
            failure: nil,
            persistedRunPath: nil
        )

        let defaultRendered = DiagnosisFinalResultRenderer.render(result)
        let wideRendered = DiagnosisFinalResultRenderer.render(result, layout: .wide)

        #expect(defaultRendered == wideRendered)
        #expect(!wideRendered.contains("[FAILED]"))
        #expect(wideRendered.hasPrefix("Investigation Summary"))
    }

    @Test("render with narrow layout stacks resolved context fields")
    func renderWithNarrowLayoutStacksResolvedContextFields() {
        let result = DiagnosisFinalResult(
            phase: .diagnosisBuild,
            status: .failed,
            runId: "run-narrow-ctx",
            attemptId: "attempt-1",
            sourceAttemptId: nil,
            summary: DiagnosisStatusSummary(source: .build, headline: "Build failed."),
            recoveryHistory: [],
            currentAttempt: makeAttempt(
                attemptId: "attempt-1",
                attemptNumber: 1,
                phase: .diagnosisBuild,
                status: .failed,
                summary: DiagnosisStatusSummary(source: .build, headline: "Build failed."),
                evidence: []
            ),
            sourceAttempt: nil,
            comparison: nil,
            failure: nil,
            persistedRunPath: nil
        )

        let rendered = DiagnosisFinalResultRenderer.render(result.withDerivedFollowOnAction(), layout: .narrow)

        #expect(rendered.contains("    project:\n      /tmp/App.xcodeproj"))
        #expect(rendered.contains("    simulator:\n      iPhone 16 Pro"))
    }

    @Test("render includes status prefix for all terminal states")
    func renderIncludesStatusPrefixForAllTerminalStates() {
        let partialResult = DiagnosisFinalResult(
            phase: .diagnosisRuntime,
            status: .partial,
            runId: "run-partial",
            attemptId: "attempt-1",
            sourceAttemptId: nil,
            summary: DiagnosisStatusSummary(source: .runtime, headline: "Partial."),
            recoveryHistory: [],
            currentAttempt: makeAttempt(
                attemptId: "attempt-1",
                attemptNumber: 1,
                phase: .diagnosisRuntime,
                status: .partial,
                summary: DiagnosisStatusSummary(source: .runtime, headline: "Partial."),
                evidence: []
            ),
            sourceAttempt: nil,
            comparison: nil,
            failure: nil,
            persistedRunPath: nil
        )

        let unsupportedResult = DiagnosisFinalResult(
            phase: .diagnosisRuntime,
            status: .unsupported,
            runId: "run-unsup",
            attemptId: "attempt-1",
            sourceAttemptId: nil,
            summary: DiagnosisStatusSummary(source: .runtime, headline: "Unsupported."),
            recoveryHistory: [],
            currentAttempt: makeAttempt(
                attemptId: "attempt-1",
                attemptNumber: 1,
                phase: .diagnosisRuntime,
                status: .unsupported,
                summary: DiagnosisStatusSummary(source: .runtime, headline: "Unsupported."),
                evidence: []
            ),
            sourceAttempt: nil,
            comparison: nil,
            failure: nil,
            persistedRunPath: nil
        )

        let partialRendered = DiagnosisFinalResultRenderer.render(partialResult, layout: .medium)
        let unsupportedRendered = DiagnosisFinalResultRenderer.render(unsupportedResult, layout: .narrow)

        #expect(partialRendered.contains("[PARTIAL] Investigation Summary"))
        #expect(unsupportedRendered.contains("[UNSUPPORTED] Investigation Summary"))
    }

    @Test("render with medium layout shows blocked prefix when recovery did not resume")
    func renderWithMediumLayoutShowsBlockedPrefixWhenRecoveryDidNotResume() {
        let result = DiagnosisFinalResult(
            phase: .diagnosisRuntime,
            status: .failed,
            runId: "run-blocked-prefix",
            attemptId: "attempt-1",
            sourceAttemptId: nil,
            summary: DiagnosisStatusSummary(source: .runtime, headline: "Failed."),
            recoveryHistory: [
                WorkflowRecoveryRecord(
                    recoveryId: "r-1",
                    sourceAttemptId: "attempt-1",
                    sourceAttemptNumber: 1,
                    triggeringAttemptId: "attempt-1",
                    triggeringAttemptNumber: 1,
                    recoveryAttemptId: "attempt-2",
                    recoveryAttemptNumber: 2,
                    issue: .staleSimulatorState,
                    detectedIssue: "Simulator stale.",
                    action: .resetLaunchContinuity,
                    status: .failed,
                    resumed: false,
                    summary: "Recovery failed.",
                    recordedAt: Date(timeIntervalSince1970: 1_743_700_000)
                )
            ],
            currentAttempt: makeAttempt(
                attemptId: "attempt-1",
                attemptNumber: 1,
                phase: .diagnosisRuntime,
                status: .failed,
                summary: DiagnosisStatusSummary(source: .runtime, headline: "Failed."),
                evidence: []
            ),
            sourceAttempt: nil,
            comparison: nil,
            failure: nil,
            persistedRunPath: nil
        )

        let rendered = DiagnosisFinalResultRenderer.render(result.withDerivedFollowOnAction(), layout: .medium)

        #expect(rendered.contains("[BLOCKED] Investigation Summary"))
    }

    @Test("render with narrow layout formats recovery narrative with stacked fields")
    func renderWithNarrowLayoutFormatsRecoveryNarrativeWithStackedFields() {
        let result = DiagnosisFinalResult(
            phase: .diagnosisRuntime,
            status: .succeeded,
            runId: "run-narrow-recovery",
            attemptId: "attempt-2",
            sourceAttemptId: nil,
            summary: DiagnosisStatusSummary(source: .runtime, headline: "Succeeded."),
            recoveryHistory: [
                WorkflowRecoveryRecord(
                    recoveryId: "recovery-1",
                    sourceAttemptId: "attempt-1",
                    sourceAttemptNumber: 1,
                    triggeringAttemptId: "attempt-1",
                    triggeringAttemptNumber: 1,
                    recoveryAttemptId: "attempt-2",
                    recoveryAttemptNumber: 2,
                    issue: .brokenLaunchContinuity,
                    detectedIssue: "App did not stay running.",
                    action: .resetLaunchContinuity,
                    status: .succeeded,
                    resumed: true,
                    summary: "Recovered launch continuity.",
                    recordedAt: Date(timeIntervalSince1970: 1_743_700_000)
                )
            ],
            currentAttempt: makeAttempt(
                attemptId: "attempt-2",
                attemptNumber: 2,
                phase: .diagnosisRuntime,
                status: .succeeded,
                summary: DiagnosisStatusSummary(source: .runtime, headline: "Succeeded."),
                evidence: []
            ),
            sourceAttempt: nil,
            comparison: nil,
            failure: nil,
            persistedRunPath: nil
        )

        let rendered = DiagnosisFinalResultRenderer.render(result.withDerivedFollowOnAction(), layout: .narrow)

        #expect(rendered.contains("Recovery Narrative"))
        #expect(rendered.contains("  - recovery-1"))
        #expect(rendered.contains("    issue:"))
        #expect(rendered.contains("    action:"))
        #expect(rendered.contains("    resumed: yes"))
    }

    private func assertSectionOrder(_ rendered: String, sections: [String]) {
        var previousStart = rendered.startIndex

        for section in sections {
            let range = rendered.range(of: section, range: previousStart..<rendered.endIndex)
            #expect(range != nil, "Expected section \(section) to appear in order.")
            previousStart = range?.lowerBound ?? previousStart
        }
    }

    private func makeAttempt(
        attemptId: String,
        attemptNumber: Int,
        phase: WorkflowPhase,
        status: WorkflowStatus,
        summary: DiagnosisStatusSummary,
        diagnosisSummary: BuildDiagnosisSummary? = nil,
        testDiagnosisSummary: TestDiagnosisSummary? = nil,
        evidence: [WorkflowEvidenceRecord]
    ) -> DiagnosisCompareAttemptSnapshot {
        DiagnosisCompareAttemptSnapshot(
            attemptId: attemptId,
            attemptNumber: attemptNumber,
            phase: phase,
            status: status,
            resolvedContext: makeResolvedContext(),
            summary: summary,
            diagnosisSummary: diagnosisSummary,
            testDiagnosisSummary: testDiagnosisSummary,
            evidence: evidence,
            recordedAt: Date(timeIntervalSince1970: 1_743_700_000)
        )
    }

    private func makeResolvedContext() -> ResolvedWorkflowContext {
        ResolvedWorkflowContext(
            project: "/tmp/App.xcodeproj",
            scheme: "App",
            simulator: "iPhone 16 Pro",
            configuration: "Debug",
            app: AppContext(bundleId: "com.example.app", appPath: "/tmp/App.app")
        )
    }

    private func makeEvidence(
        kind: WorkflowEvidenceKind,
        phase: WorkflowPhase,
        attemptId: String,
        attemptNumber: Int,
        availability: WorkflowEvidenceAvailability,
        unavailableReason: WorkflowEvidenceUnavailableReason? = nil,
        reference: String?,
        source: String,
        detail: String? = nil
    ) -> WorkflowEvidenceRecord {
        WorkflowEvidenceRecord(
            kind: kind,
            phase: phase,
            attemptId: attemptId,
            attemptNumber: attemptNumber,
            availability: availability,
            unavailableReason: unavailableReason,
            reference: reference,
            source: source,
            detail: detail
        )
    }
}

@Suite("WorkflowPresentationHelpers follow-on guidance", .serialized)
struct WorkflowPresentationHelpersFollowOnGuidanceTests {

    @Test("follow-on action for failed build with diagnosis evidence")
    func followOnActionForFailedBuildWithDiagnosisEvidence() {
        let buildDiagnosis = BuildDiagnosisSummary(
            observedEvidence: ObservedBuildEvidence(
                summary: "Build failed with 3 errors.",
                primarySignal: BuildIssueSummary(
                    severity: .error,
                    message: "Cannot find 'WidgetView' in scope",
                    location: SourceLocation(filePath: "Sources/App/WidgetView.swift", line: 42, column: nil),
                    source: "swiftc"
                ),
                additionalIssueCount: 2,
                errorCount: 3,
                warningCount: 0,
                analyzerWarningCount: 0
            ),
            inferredConclusion: nil,
            supportingEvidence: []
        )

        let result = DiagnosisFinalResult(
            phase: .diagnosisBuild,
            status: .failed,
            runId: "run-1",
            attemptId: "a-1",
            sourceAttemptId: nil,
            summary: DiagnosisStatusSummary(source: .build, headline: "Build failed."),
            recoveryHistory: [],
            currentAttempt: makeAttempt(
                phase: .diagnosisBuild,
                status: .failed,
                diagnosisSummary: buildDiagnosis
            ),
            sourceAttempt: nil,
            comparison: nil,
            failure: nil,
            persistedRunPath: nil
        )

        let guidance = result.withDerivedFollowOnAction().followOnAction

        #expect(guidance != nil)
        #expect(guidance?.action == "Review the build error and apply a fix, then rerun validation.")
        #expect(guidance?.rationale.contains("3 error(s)") == true)
        #expect(guidance?.rationale.contains("Cannot find 'WidgetView' in scope") == true)
        #expect(guidance?.confidence == .evidenceSupported)
    }

    @Test("follow-on action for failed test with diagnosis evidence")
    func followOnActionForFailedTestWithDiagnosisEvidence() {
        let testDiagnosis = TestDiagnosisSummary(
            observedEvidence: ObservedTestEvidence(
                summary: "2 of 8 tests failed.",
                primaryFailure: TestFailureSummary(
                    testName: "testWidget",
                    testIdentifier: "WidgetTests/testWidget",
                    message: "Expected 'Hello'",
                    source: "XCTest"
                ),
                additionalFailureCount: 1,
                totalTestCount: 8,
                failedTestCount: 2,
                passedTestCount: 6,
                skippedTestCount: 0,
                expectedFailureCount: 0
            ),
            inferredConclusion: nil,
            supportingEvidence: []
        )

        let result = DiagnosisFinalResult(
            phase: .diagnosisTest,
            status: .failed,
            runId: "run-2",
            attemptId: "a-1",
            sourceAttemptId: nil,
            summary: DiagnosisStatusSummary(source: .test, headline: "Tests failed."),
            recoveryHistory: [],
            currentAttempt: makeAttempt(
                phase: .diagnosisTest,
                status: .failed,
                testDiagnosisSummary: testDiagnosis
            ),
            sourceAttempt: nil,
            comparison: nil,
            failure: nil,
            persistedRunPath: nil
        )

        let guidance = result.withDerivedFollowOnAction().followOnAction

        #expect(guidance != nil)
        #expect(guidance?.action == "Review the failing tests and apply a fix, then rerun validation.")
        #expect(guidance?.rationale.contains("2 of 8 tests failed") == true)
        #expect(guidance?.rationale.contains("WidgetTests/testWidget") == true)
        #expect(guidance?.confidence == .evidenceSupported)
    }

    @Test("follow-on action for succeeded after recovery")
    func followOnActionForSucceededAfterRecovery() {
        let result = DiagnosisFinalResult(
            phase: .diagnosisRuntime,
            status: .succeeded,
            runId: "run-3",
            attemptId: "a-2",
            sourceAttemptId: "a-1",
            summary: DiagnosisStatusSummary(source: .runtime, headline: "Succeeded."),
            recoveryHistory: [
                WorkflowRecoveryRecord(
                    recoveryId: "r-1",
                    sourceAttemptId: "a-1",
                    sourceAttemptNumber: 1,
                    triggeringAttemptId: "a-1",
                    triggeringAttemptNumber: 1,
                    recoveryAttemptId: "a-2",
                    recoveryAttemptNumber: 2,
                    issue: .brokenLaunchContinuity,
                    detectedIssue: "App stalled.",
                    action: .resetLaunchContinuity,
                    status: .succeeded,
                    resumed: true,
                    summary: "Recovered.",
                    recordedAt: Date(timeIntervalSince1970: 1_700_000_000)
                )
            ],
            currentAttempt: makeAttempt(phase: .diagnosisRuntime, status: .succeeded),
            sourceAttempt: nil,
            comparison: nil,
            failure: nil,
            persistedRunPath: nil
        )

        let guidance = result.withDerivedFollowOnAction().followOnAction

        #expect(guidance != nil)
        #expect(guidance?.action == "Verify the fix holds across related targets.")
        #expect(guidance?.rationale.contains("1 recovery action") == true)
        #expect(guidance?.confidence == .evidenceSupported)
    }

    @Test("follow-on action for partial with blocked recovery")
    func followOnActionForPartialWithBlockedRecovery() {
        let result = DiagnosisFinalResult(
            phase: .diagnosisRuntime,
            status: .partial,
            runId: "run-4",
            attemptId: "a-1",
            sourceAttemptId: nil,
            summary: DiagnosisStatusSummary(source: .runtime, headline: "Partial."),
            recoveryHistory: [
                WorkflowRecoveryRecord(
                    recoveryId: "r-1",
                    sourceAttemptId: "a-1",
                    sourceAttemptNumber: 1,
                    triggeringAttemptId: "a-1",
                    triggeringAttemptNumber: 1,
                    recoveryAttemptId: "a-2",
                    recoveryAttemptNumber: 2,
                    issue: .staleSimulatorState,
                    detectedIssue: "Simulator stale.",
                    action: .resetLaunchContinuity,
                    status: .failed,
                    resumed: false,
                    summary: "Recovery failed.",
                    recordedAt: Date(timeIntervalSince1970: 1_700_000_000)
                )
            ],
            currentAttempt: makeAttempt(phase: .diagnosisRuntime, status: .partial),
            sourceAttempt: nil,
            comparison: nil,
            failure: nil,
            persistedRunPath: nil
        )

        let guidance = result.withDerivedFollowOnAction().followOnAction

        #expect(guidance != nil)
        #expect(guidance?.action == "Resolve the environment issue before retrying the diagnosis.")
        #expect(guidance?.rationale.contains("1 recovery action") == true)
        #expect(guidance?.confidence == .evidenceSupported)
    }

    @Test("follow-on action for rerun with comparison")
    func followOnActionForRerunWithComparison() {
        let result = DiagnosisFinalResult(
            phase: .diagnosisBuild,
            status: .succeeded,
            runId: "run-5",
            attemptId: "a-2",
            sourceAttemptId: "a-1",
            summary: DiagnosisStatusSummary(source: .build, headline: "Build succeeded."),
            recoveryHistory: [],
            currentAttempt: makeAttempt(phase: .diagnosisBuild, status: .succeeded),
            sourceAttempt: nil,
            comparison: DiagnosisFinalComparison(
                outcome: .improved,
                changedEvidence: [
                    DiagnosisComparisonChange(field: "status", priorValue: "failed", currentValue: "succeeded")
                ],
                unchangedBlockers: []
            ),
            failure: nil,
            persistedRunPath: nil
        )

        let guidance = result.withDerivedFollowOnAction().followOnAction

        #expect(guidance != nil)
        #expect(guidance?.action == "Review the comparison to confirm the change had the expected effect.")
        #expect(guidance?.confidence == .evidenceSupported)
    }

    @Test("follow-on action is nil when no state is available")
    func followOnActionIsNilWhenNoStateIsAvailable() {
        let result = DiagnosisFinalResult(
            phase: nil,
            status: nil,
            runId: "run-empty",
            attemptId: nil,
            sourceAttemptId: nil,
            summary: nil,
            recoveryHistory: [],
            currentAttempt: nil,
            sourceAttempt: nil,
            comparison: nil,
            comparisonNote: nil,
            failure: nil,
            persistedRunPath: nil
        )

        let guidance = result.withDerivedFollowOnAction().followOnAction
        #expect(guidance == nil)

        let block = WorkflowPresentationHelpers.guidanceBlock(for: result)
        #expect(block.isEmpty)
    }

    @Test("follow-on action for failure object directs to root cause")
    func followOnActionForFailureObjectDirectsToRootCause() {
        let result = DiagnosisFinalResult(
            phase: nil,
            status: nil,
            runId: "run-fail",
            attemptId: nil,
            sourceAttemptId: nil,
            summary: nil,
            recoveryHistory: [],
            currentAttempt: nil,
            sourceAttempt: nil,
            comparison: nil,
            failure: WorkflowFailure(
                field: .run,
                classification: .notFound,
                message: "No run found."
            ),
            persistedRunPath: nil
        )

        let guidance = result.withDerivedFollowOnAction().followOnAction

        #expect(guidance != nil)
        #expect(guidance?.action == "Review the failure details and address the root cause before retrying.")
        #expect(guidance?.rationale.contains("No run found.") == true)
        #expect(guidance?.confidence == .evidenceSupported)
    }

    @Test("guidance block renders structured next step section")
    func guidanceBlockRendersStructuredNextStepSection() {
        let result = DiagnosisFinalResult(
            phase: .diagnosisBuild,
            status: .failed,
            runId: "run-block",
            attemptId: "a-1",
            sourceAttemptId: nil,
            summary: DiagnosisStatusSummary(source: .build, headline: "Build failed."),
            recoveryHistory: [],
            currentAttempt: makeAttempt(phase: .diagnosisBuild, status: .failed),
            sourceAttempt: nil,
            comparison: nil,
            failure: nil,
            persistedRunPath: nil
        ).withDerivedFollowOnAction()

        let block = WorkflowPresentationHelpers.guidanceBlock(for: result)

        #expect(block.count == 4)
        #expect(block[0] == "Next Step")
        #expect(block[1].hasPrefix("  suggested_action:"))
        #expect(block[2].hasPrefix("  rationale:"))
        #expect(block[3].hasPrefix("  confidence:"))
    }

    private func makeAttempt(
        phase: WorkflowPhase,
        status: WorkflowStatus,
        diagnosisSummary: BuildDiagnosisSummary? = nil,
        testDiagnosisSummary: TestDiagnosisSummary? = nil
    ) -> DiagnosisCompareAttemptSnapshot {
        DiagnosisCompareAttemptSnapshot(
            attemptId: "a-1",
            attemptNumber: 1,
            phase: phase,
            status: status,
            resolvedContext: ResolvedWorkflowContext(
                project: "/tmp/App.xcodeproj",
                scheme: "App",
                simulator: "iPhone 16 Pro",
                configuration: "Debug",
                app: AppContext(bundleId: "com.example.app", appPath: "/tmp/App.app")
            ),
            summary: DiagnosisStatusSummary(source: .build, headline: "Summary."),
            diagnosisSummary: diagnosisSummary,
            testDiagnosisSummary: testDiagnosisSummary,
            evidence: [],
            recordedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }
}

@Suite("DiagnosisFinalResult JSON follow-on action", .serialized)
struct DiagnosisFinalResultJSONFollowOnActionTests {

    @Test("JSON output includes followOnAction for failed build")
    func jsonOutputIncludesFollowOnActionForFailedBuild() throws {
        let result = DiagnosisFinalResult(
            phase: .diagnosisBuild,
            status: .failed,
            runId: "run-json-1",
            attemptId: "a-1",
            sourceAttemptId: nil,
            summary: DiagnosisStatusSummary(source: .build, headline: "Build failed."),
            recoveryHistory: [],
            currentAttempt: nil,
            sourceAttempt: nil,
            comparison: nil,
            failure: nil,
            persistedRunPath: nil
        ).withDerivedFollowOnAction()

        let json = try DiagnosisFinalResultRenderer.renderJSON(result)

        #expect(json.contains("\"followOnAction\""))
        #expect(json.contains("\"action\""))
        #expect(json.contains("\"rationale\""))
        #expect(json.contains("\"confidence\""))
        #expect(json.contains("\"inferred\""))
    }

    @Test("JSON output includes evidence_supported confidence for failure object")
    func jsonOutputIncludesEvidenceSupportedConfidenceForFailure() throws {
        let result = DiagnosisFinalResult(
            phase: nil,
            status: nil,
            runId: "run-json-2",
            attemptId: nil,
            sourceAttemptId: nil,
            summary: nil,
            recoveryHistory: [],
            currentAttempt: nil,
            sourceAttempt: nil,
            comparison: nil,
            followOnAction: WorkflowFollowOnAction(
                action: "Review the failure details and address the root cause before retrying.",
                rationale: "Workflow failed at run: Not found.",
                confidence: .evidenceSupported
            ),
            failure: WorkflowFailure(
                field: .run,
                classification: .notFound,
                message: "Not found."
            ),
            persistedRunPath: nil
        )

        let json = try DiagnosisFinalResultRenderer.renderJSON(result)

        #expect(json.contains("\"evidence_supported\""))
        #expect(json.contains("\"followOnAction\""))
    }

    @Test("JSON output omits followOnAction for canceled status")
    func jsonOutputOmitsFollowOnActionForCanceledStatus() throws {
        let result = DiagnosisFinalResult(
            phase: .diagnosisBuild,
            status: .canceled,
            runId: "run-json-3",
            attemptId: "a-1",
            sourceAttemptId: nil,
            summary: DiagnosisStatusSummary(source: .build, headline: "Canceled."),
            recoveryHistory: [],
            currentAttempt: nil,
            sourceAttempt: nil,
            comparison: nil,
            failure: nil,
            persistedRunPath: nil
        ).withDerivedFollowOnAction()

        let json = try DiagnosisFinalResultRenderer.renderJSON(result)

        #expect(!json.contains("\"followOnAction\""))
    }

    @Test("JSON output omits followOnAction for in-progress status")
    func jsonOutputOmitsFollowOnActionForInProgressStatus() throws {
        let result = DiagnosisFinalResult(
            phase: .diagnosisBuild,
            status: .inProgress,
            runId: "run-json-4",
            attemptId: "a-1",
            sourceAttemptId: nil,
            summary: DiagnosisStatusSummary(source: .build, headline: "In progress."),
            recoveryHistory: [],
            currentAttempt: nil,
            sourceAttempt: nil,
            comparison: nil,
            failure: nil,
            persistedRunPath: nil
        ).withDerivedFollowOnAction()

        let json = try DiagnosisFinalResultRenderer.renderJSON(result)

        #expect(!json.contains("\"followOnAction\""))
    }

    @Test("JSON output produces inferred guidance for partial with nil currentAttempt")
    func jsonOutputProducesInferredGuidanceForPartialWithNilCurrentAttempt() throws {
        let result = DiagnosisFinalResult(
            phase: .diagnosisRuntime,
            status: .partial,
            runId: "run-json-partial",
            attemptId: "a-1",
            sourceAttemptId: nil,
            summary: DiagnosisStatusSummary(source: .runtime, headline: "Partial."),
            recoveryHistory: [],
            currentAttempt: nil,
            sourceAttempt: nil,
            comparison: nil,
            failure: nil,
            persistedRunPath: nil
        ).withDerivedFollowOnAction()

        let json = try DiagnosisFinalResultRenderer.renderJSON(result)

        #expect(json.contains("\"followOnAction\""))
        #expect(json.contains("\"inferred\""))
        #expect(json.contains("partial result"))
    }

    @Test("followOnAction is structurally distinct from failure and evidence in JSON")
    func followOnActionIsStructurallyDistinctFromFailureAndEvidence() throws {
        let result = DiagnosisFinalResult(
            phase: nil,
            status: nil,
            runId: "run-json-5",
            attemptId: nil,
            sourceAttemptId: nil,
            summary: nil,
            recoveryHistory: [],
            currentAttempt: nil,
            sourceAttempt: nil,
            comparison: nil,
            followOnAction: WorkflowFollowOnAction(
                action: "Review the failure details and address the root cause before retrying.",
                rationale: "Workflow failed at run: Missing.",
                confidence: .evidenceSupported
            ),
            failure: WorkflowFailure(
                field: .run,
                classification: .notFound,
                message: "Missing.",
                observed: ObservedFailureEvidence(summary: "Missing.")
            ),
            persistedRunPath: nil
        )

        let json = try DiagnosisFinalResultRenderer.renderJSON(result)
        let data = json.data(using: .utf8)!
        let parsed = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        // followOnAction, failure, and evidence are separate top-level keys
        #expect(parsed["followOnAction"] is [String: Any])
        #expect(parsed["failure"] is [String: Any])

        let followOn = parsed["followOnAction"] as! [String: Any]
        let failure = parsed["failure"] as! [String: Any]

        // They have different structures
        #expect(followOn["action"] as? String != nil)
        #expect(followOn["rationale"] as? String != nil)
        #expect(followOn["confidence"] as? String != nil)
        #expect(failure["field"] as? String != nil)
        #expect(failure["classification"] as? String != nil)
    }
}

// MARK: - Deferred hardening bundle tests

@Suite("Deferred hardening: nextReviewAction status awareness", .serialized)
struct NextReviewActionStatusTests {

    @Test("nextReviewAction returns status-aware message for canceled")
    func canceledStatusReturnsStatusAwareMessage() {
        let result = DiagnosisFinalResult(
            phase: .diagnosisBuild,
            status: .canceled,
            runId: "run-canceled",
            attemptId: "a-1",
            sourceAttemptId: nil,
            summary: DiagnosisStatusSummary(source: .build, headline: "Canceled."),
            recoveryHistory: [],
            currentAttempt: nil,
            sourceAttempt: nil,
            comparison: nil,
            failure: nil,
            persistedRunPath: nil
        )

        let rendered = DiagnosisFinalResultRenderer.render(result)
        #expect(rendered.contains("Run was canceled"))
        #expect(rendered.contains("evidence collection may be incomplete"))
    }

    @Test("nextReviewAction returns status-aware message for inProgress")
    func inProgressStatusReturnsStatusAwareMessage() {
        let result = DiagnosisFinalResult(
            phase: .diagnosisTest,
            status: .inProgress,
            runId: "run-progress",
            attemptId: "a-1",
            sourceAttemptId: nil,
            summary: DiagnosisStatusSummary(source: .test, headline: "In progress."),
            recoveryHistory: [],
            currentAttempt: nil,
            sourceAttempt: nil,
            comparison: nil,
            failure: nil,
            persistedRunPath: nil
        )

        let rendered = DiagnosisFinalResultRenderer.render(result)
        #expect(rendered.contains("Run is still in progress"))
        #expect(rendered.contains("evidence is incomplete"))
    }
}

@Suite("Deferred hardening: runtime-phase follow-on action", .serialized)
struct RuntimeFollowOnActionTests {

    @Test("deriveForFailed produces evidence-supported guidance when runtimeSummary is present")
    func runtimeSummaryProducesEvidenceSupportedGuidance() {
        let runtimeSummary = RuntimeDiagnosisSummary(
            observedEvidence: ObservedRuntimeEvidence(
                summary: "App launched but crashed during runtime inspection.",
                launchedApp: true,
                appRunning: false,
                relaunchedApp: false,
                primarySignal: RuntimeSignalSummary(
                    stream: .stderr,
                    message: "Fatal error: index out of range",
                    source: "stderr"
                ),
                additionalSignalCount: 0,
                stdoutLineCount: 5,
                stderrLineCount: 3
            ),
            inferredConclusion: nil,
            supportingEvidence: []
        )

        let attempt = DiagnosisCompareAttemptSnapshot(
            attemptId: "a-1",
            attemptNumber: 1,
            phase: .diagnosisRuntime,
            status: .failed,
            resolvedContext: ResolvedWorkflowContext(
                project: "/tmp/App.xcodeproj",
                scheme: "App",
                simulator: "iPhone 16 Pro",
                configuration: "Debug",
                app: AppContext(bundleId: "com.example.app", appPath: "/tmp/App.app")
            ),
            summary: DiagnosisStatusSummary(source: .runtime, headline: "Runtime failed."),
            runtimeSummary: runtimeSummary,
            evidence: [],
            recordedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let result = DiagnosisFinalResult(
            phase: .diagnosisRuntime,
            status: .failed,
            runId: "run-rt-1",
            attemptId: "a-1",
            sourceAttemptId: nil,
            summary: DiagnosisStatusSummary(source: .runtime, headline: "Runtime failed."),
            recoveryHistory: [],
            currentAttempt: attempt,
            sourceAttempt: nil,
            comparison: nil,
            failure: nil,
            persistedRunPath: nil
        ).withDerivedFollowOnAction()

        #expect(result.followOnAction?.confidence == .evidenceSupported)
        #expect(result.followOnAction?.action.contains("runtime failure") == true)
        #expect(result.followOnAction?.rationale.contains("did not stay running") == true)
    }

    @Test("render includes runtime diagnosis detail when runtimeSummary is present")
    func renderIncludesRuntimeDiagnosisDetail() {
        let runtimeSummary = RuntimeDiagnosisSummary(
            observedEvidence: ObservedRuntimeEvidence(
                summary: "App launched and stayed running.",
                launchedApp: true,
                appRunning: true,
                relaunchedApp: false,
                primarySignal: nil,
                additionalSignalCount: 0,
                stdoutLineCount: 10,
                stderrLineCount: 0
            ),
            inferredConclusion: InferredRuntimeConclusion(summary: "App appears stable."),
            supportingEvidence: []
        )

        let attempt = DiagnosisCompareAttemptSnapshot(
            attemptId: "a-1",
            attemptNumber: 1,
            phase: .diagnosisRuntime,
            status: .succeeded,
            resolvedContext: ResolvedWorkflowContext(
                project: "/tmp/App.xcodeproj",
                scheme: "App",
                simulator: "iPhone 16 Pro",
                configuration: "Debug",
                app: AppContext(bundleId: "com.example.app", appPath: "/tmp/App.app")
            ),
            summary: DiagnosisStatusSummary(source: .runtime, headline: "Runtime OK."),
            runtimeSummary: runtimeSummary,
            evidence: [],
            recordedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let result = DiagnosisFinalResult(
            phase: .diagnosisRuntime,
            status: .succeeded,
            runId: "run-rt-2",
            attemptId: "a-1",
            sourceAttemptId: nil,
            summary: DiagnosisStatusSummary(source: .runtime, headline: "Runtime OK."),
            recoveryHistory: [],
            currentAttempt: attempt,
            sourceAttempt: nil,
            comparison: nil,
            failure: nil,
            persistedRunPath: nil
        )

        let rendered = DiagnosisFinalResultRenderer.render(result)
        #expect(rendered.contains("Runtime Observed Evidence"))
        #expect(rendered.contains("App launched and stayed running."))
        #expect(rendered.contains("Runtime Inferred Conclusion"))
        #expect(rendered.contains("App appears stable."))
        #expect(rendered.contains("stdout_lines=10"))
    }
}

@Suite("Deferred hardening: sourceAttempt diagnosis detail", .serialized)
struct SourceAttemptDiagnosisDetailTests {

    @Test("render includes diagnosis detail for sourceAttempt in rerun comparison")
    func sourceAttemptGetsDiagnosisDetail() {
        let buildSummary = BuildDiagnosisSummary(
            observedEvidence: ObservedBuildEvidence(
                summary: "Prior build had 2 errors.",
                primarySignal: nil,
                additionalIssueCount: 0,
                errorCount: 2,
                warningCount: 0,
                analyzerWarningCount: 0
            ),
            inferredConclusion: nil,
            supportingEvidence: []
        )

        let sourceAttempt = DiagnosisCompareAttemptSnapshot(
            attemptId: "a-prior",
            attemptNumber: 1,
            phase: .diagnosisBuild,
            status: .failed,
            resolvedContext: ResolvedWorkflowContext(
                project: "/tmp/App.xcodeproj",
                scheme: "App",
                simulator: "iPhone 16 Pro",
                configuration: "Debug",
                app: AppContext(bundleId: "com.example.app", appPath: "/tmp/App.app")
            ),
            summary: DiagnosisStatusSummary(source: .build, headline: "Prior build failed."),
            diagnosisSummary: buildSummary,
            evidence: [],
            recordedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let currentAttempt = DiagnosisCompareAttemptSnapshot(
            attemptId: "a-current",
            attemptNumber: 2,
            phase: .diagnosisBuild,
            status: .succeeded,
            resolvedContext: ResolvedWorkflowContext(
                project: "/tmp/App.xcodeproj",
                scheme: "App",
                simulator: "iPhone 16 Pro",
                configuration: "Debug",
                app: AppContext(bundleId: "com.example.app", appPath: "/tmp/App.app")
            ),
            summary: DiagnosisStatusSummary(source: .build, headline: "Build succeeded."),
            evidence: [],
            recordedAt: Date(timeIntervalSince1970: 1_700_001_000)
        )

        let result = DiagnosisFinalResult(
            phase: .diagnosisBuild,
            status: .succeeded,
            runId: "run-rerun",
            attemptId: "a-current",
            sourceAttemptId: "a-prior",
            summary: DiagnosisStatusSummary(source: .build, headline: "Build succeeded."),
            recoveryHistory: [],
            currentAttempt: currentAttempt,
            sourceAttempt: sourceAttempt,
            comparison: nil,
            failure: nil,
            persistedRunPath: nil
        )

        let rendered = DiagnosisFinalResultRenderer.render(result)

        // The "Prior State" section should now include diagnosis detail
        let priorStateIndex = rendered.range(of: "Prior State")
        #expect(priorStateIndex != nil)

        // After "Prior State", there should be "Diagnosis Detail" with build info
        let afterPrior = rendered[priorStateIndex!.lowerBound...]
        #expect(afterPrior.contains("Build Observed Evidence"))
        #expect(afterPrior.contains("Prior build had 2 errors."))
    }
}

@Suite("Deferred hardening: CLI JSON error envelope", .serialized)
struct CLIJSONErrorEnvelopeTests {

    @Test("CLIErrorEnvelope encodes to valid JSON with error and code fields")
    func envelopeEncodesToJSON() throws {
        let envelope = CLIErrorEnvelope(error: "Test error", code: "resolution_failed")
        let data = try JSONEncoder().encode(envelope)
        let decoded = try JSONSerialization.jsonObject(with: data) as! [String: String]

        #expect(decoded["error"] == "Test error")
        #expect(decoded["code"] == "resolution_failed")
    }

    @Test("runAsyncJSON re-throws error as-is when json is false")
    func nonJSONPassesThrough() {
        do {
            try runAsyncJSON(json: false) {
                throw SampleError.test
            }
            Issue.record("Expected error to be thrown")
        } catch is SampleError {
            // Expected — error passes through without wrapping
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    private enum SampleError: Error {
        case test
    }
}

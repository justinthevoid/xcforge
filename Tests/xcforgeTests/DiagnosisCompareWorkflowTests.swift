import Foundation
import Testing
@testable import xcforgeCore

@Suite("DiagnosisCompareWorkflow", .serialized)
struct DiagnosisCompareWorkflowTests {

    @Test("improved build rerun compares the prior failure against the new success")
    func improvedBuildRerunComparesThePriorFailureAgainstTheNewSuccess() async throws {
        let tempDir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = RunStore(baseDirectory: tempDir)
        let sourceXCResult = tempDir.appendingPathComponent("source-build.xcresult", isDirectory: true)
        let rerunXCResult = tempDir.appendingPathComponent("rerun-build.xcresult", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceXCResult, withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.createDirectory(at: rerunXCResult, withIntermediateDirectories: true, attributes: nil)

        let run = makeBuildComparisonRun(
            runId: "run-build-compare",
            sourceStatus: .failed,
            currentStatus: .succeeded,
            sourceSummary: makeBuildSummary(
                headline: "Build failed with a primary compiler error.",
                primaryMessage: "Cannot find 'WidgetView' in scope",
                additionalIssueCount: 1,
                errorCount: 2,
                warningCount: 0,
                analyzerWarningCount: 0,
                inferredSummary: "The run failed because WidgetView is unresolved.",
                supportingEvidencePath: sourceXCResult.path
            ),
            currentSummary: makeBuildSummary(
                headline: "Build succeeded without an error diagnostic.",
                primaryMessage: nil,
                additionalIssueCount: 0,
                errorCount: 0,
                warningCount: 1,
                analyzerWarningCount: 0,
                inferredSummary: "No build failure signal was found for this run.",
                supportingEvidencePath: rerunXCResult.path
            ),
            sourceEvidencePath: sourceXCResult.path,
            currentEvidencePath: rerunXCResult.path
        )
        _ = try store.save(run)

        let workflow = makeWorkflow(store: store)
        let result = await workflow.compare(request: DiagnosisCompareRequest(runId: run.runId))

        #expect(result.isSuccessfulComparison)
        #expect(result.outcome == .improved)
        #expect(result.status == .succeeded)
        #expect(result.phase == .diagnosisBuild)
        #expect(result.attemptId == "attempt-2")
        #expect(result.sourceAttemptId == "attempt-1")
        #expect(result.changedEvidence.contains(where: { $0.field == "Overall status" }))
        #expect(result.changedEvidence.contains(where: { $0.field == "Primary signal" }))
        #expect(result.unchangedBlockers.isEmpty)
        #expect(result.priorAttempt?.availableEvidence.count == 2)
        #expect(result.currentAttempt?.availableEvidence.count == 2)
        #expect(result.persistedRunPath == store.runFileURL(runId: run.runId).path)
    }

    @Test("unchanged test rerun stays compact when the failure signal is the same")
    func unchangedTestRerunStaysCompactWhenFailureSignalIsTheSame() async throws {
        let tempDir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = RunStore(baseDirectory: tempDir)
        let sourceXCResult = tempDir.appendingPathComponent("source-test.xcresult", isDirectory: true)
        let rerunXCResult = tempDir.appendingPathComponent("rerun-test.xcresult", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceXCResult, withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.createDirectory(at: rerunXCResult, withIntermediateDirectories: true, attributes: nil)

        let summary = makeTestSummary(
            headline: "Primary failing test selected from 1 failing test(s): AppTests/LoginTests/testShowsErrorBanner().",
            primaryTestName: "testShowsErrorBanner()",
            primaryTestIdentifier: "AppTests/LoginTests/testShowsErrorBanner()",
            failureMessage: "XCTAssertEqual failed",
            additionalFailureCount: 0,
            totalTestCount: 6,
            failedTestCount: 1,
            passedTestCount: 5,
            skippedTestCount: 0,
            expectedFailureCount: 0,
            inferredSummary: "The run appears primarily blocked by failing test AppTests/LoginTests/testShowsErrorBanner(): XCTAssertEqual failed",
            supportingEvidencePath: sourceXCResult.path
        )

        let run = makeTestComparisonRun(
            runId: "run-test-compare",
            sourceStatus: .failed,
            currentStatus: .failed,
            sourceSummary: summary,
            currentSummary: summary,
            sourceEvidencePath: sourceXCResult.path,
            currentEvidencePath: rerunXCResult.path
        )
        _ = try store.save(run)

        let workflow = makeWorkflow(store: store)
        let result = await workflow.compare(request: DiagnosisCompareRequest(runId: run.runId))

        #expect(result.isSuccessfulComparison)
        #expect(result.outcome == .unchanged)
        #expect(result.status == .failed)
        #expect(result.phase == .diagnosisTest)
        #expect(result.changedEvidence.isEmpty)
        #expect(result.unchangedBlockers.contains("Primary test remains: AppTests/LoginTests/testShowsErrorBanner() - XCTAssertEqual failed"))
        #expect(result.currentAttempt?.summary.detail == "AppTests/LoginTests/testShowsErrorBanner()")
    }

    @Test("partial build improvement keeps the remaining blockers explicit")
    func partialBuildImprovementKeepsTheRemainingBlockersExplicit() async throws {
        let tempDir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = RunStore(baseDirectory: tempDir)
        let sourceXCResult = tempDir.appendingPathComponent("source-partial.xcresult", isDirectory: true)
        let rerunXCResult = tempDir.appendingPathComponent("rerun-partial.xcresult", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceXCResult, withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.createDirectory(at: rerunXCResult, withIntermediateDirectories: true, attributes: nil)

        let run = makeBuildComparisonRun(
            runId: "run-build-partial",
            sourceStatus: .failed,
            currentStatus: .failed,
            sourceSummary: makeBuildSummary(
                headline: "Build failed with a primary compiler error.",
                primaryMessage: "Cannot find 'WidgetView' in scope",
                additionalIssueCount: 3,
                errorCount: 3,
                warningCount: 1,
                analyzerWarningCount: 1,
                inferredSummary: "The run failed because WidgetView is unresolved.",
                supportingEvidencePath: sourceXCResult.path
            ),
            currentSummary: makeBuildSummary(
                headline: "Build failed with a narrower compiler error set.",
                primaryMessage: "Cannot find 'WidgetView' in scope",
                additionalIssueCount: 1,
                errorCount: 1,
                warningCount: 1,
                analyzerWarningCount: 0,
                inferredSummary: "The run still fails because WidgetView is unresolved.",
                supportingEvidencePath: rerunXCResult.path
            ),
            sourceEvidencePath: sourceXCResult.path,
            currentEvidencePath: rerunXCResult.path
        )
        _ = try store.save(run)

        let workflow = makeWorkflow(store: store)
        let result = await workflow.compare(request: DiagnosisCompareRequest(runId: run.runId))

        #expect(result.isSuccessfulComparison)
        #expect(result.outcome == .partial)
        #expect(result.status == .failed)
        #expect(result.changedEvidence.contains(where: { $0.field == "Error count" }))
        #expect(result.changedEvidence.contains(where: { $0.field == "Analyzer warning count" }))
        #expect(result.unchangedBlockers.contains("Primary build signal remains: Cannot find 'WidgetView' in scope"))
    }

    @Test("failed to partial rerun stays partial and reports evidence changes")
    func failedToPartialRerunStaysPartialAndReportsEvidenceChanges() async throws {
        let tempDir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = RunStore(baseDirectory: tempDir)
        let sourceXCResult = tempDir.appendingPathComponent("source-partial-status.xcresult", isDirectory: true)
        let rerunXCResult = tempDir.appendingPathComponent("rerun-partial-status.xcresult", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceXCResult, withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.createDirectory(at: rerunXCResult, withIntermediateDirectories: true, attributes: nil)

        let run = makeTestComparisonRun(
            runId: "run-test-partial-status",
            sourceStatus: .failed,
            currentStatus: .partial,
            sourceSummary: makeTestSummary(
                headline: "Test run completed with one failing test signal.",
                primaryTestName: "testShowsErrorBanner()",
                primaryTestIdentifier: "AppTests/LoginTests/testShowsErrorBanner()",
                failureMessage: "XCTAssertEqual failed",
                additionalFailureCount: 0,
                totalTestCount: 8,
                failedTestCount: 1,
                passedTestCount: 7,
                skippedTestCount: 0,
                expectedFailureCount: 0,
                inferredSummary: "The run is blocked by failing test AppTests/LoginTests/testShowsErrorBanner(): XCTAssertEqual failed",
                supportingEvidencePath: sourceXCResult.path
            ),
            currentSummary: makeTestSummary(
                headline: "Test rerun improved but still ended with one failing test signal.",
                primaryTestName: "testShowsErrorBanner()",
                primaryTestIdentifier: "AppTests/LoginTests/testShowsErrorBanner()",
                failureMessage: "XCTAssertEqual failed",
                additionalFailureCount: 0,
                totalTestCount: 8,
                failedTestCount: 1,
                passedTestCount: 7,
                skippedTestCount: 0,
                expectedFailureCount: 0,
                inferredSummary: "The rerun still reports the same failing test after improving evidence capture.",
                supportingEvidencePath: rerunXCResult.path
            ),
            sourceEvidencePath: sourceXCResult.path,
            currentEvidencePath: rerunXCResult.path,
            sourceExtraEvidence: [
                WorkflowEvidenceRecord(
                    kind: .stderr,
                    phase: .diagnosisTest,
                    attemptId: "attempt-1",
                    attemptNumber: 1,
                    availability: .unavailable,
                    unavailableReason: .notCaptured,
                    reference: nil,
                    source: "xcodebuild.stderr",
                    detail: "stderr was not captured"
                ),
            ],
            currentExtraEvidence: [
                WorkflowEvidenceRecord(
                    kind: .stderr,
                    phase: .diagnosisTest,
                    attemptId: "attempt-2",
                    attemptNumber: 2,
                    availability: .available,
                    unavailableReason: nil,
                    reference: tempDir.appendingPathComponent("rerun.stderr.txt").path,
                    source: "xcodebuild.stderr"
                ),
            ]
        )
        _ = try store.save(run)

        let workflow = makeWorkflow(store: store)
        let result = await workflow.compare(request: DiagnosisCompareRequest(runId: run.runId))

        #expect(result.isSuccessfulComparison)
        #expect(result.outcome == .partial)
        #expect(result.status == .partial)
        #expect(result.changedEvidence.contains(where: { $0.field == "Newly available artifacts" }))
    }

    @Test("regressed comparison flags the follow-up attempt as worse than the prior success")
    func regressedComparisonFlagsTheFollowUpAttemptAsWorseThanThePriorSuccess() async throws {
        let tempDir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = RunStore(baseDirectory: tempDir)
        let sourceXCResult = tempDir.appendingPathComponent("source-regressed.xcresult", isDirectory: true)
        let rerunXCResult = tempDir.appendingPathComponent("rerun-regressed.xcresult", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceXCResult, withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.createDirectory(at: rerunXCResult, withIntermediateDirectories: true, attributes: nil)

        let run = makeTestComparisonRun(
            runId: "run-test-regressed",
            sourceStatus: .succeeded,
            currentStatus: .failed,
            sourceSummary: makeTestSummary(
                headline: "Test run completed without a failing test signal.",
                primaryTestName: nil,
                primaryTestIdentifier: nil,
                failureMessage: nil,
                additionalFailureCount: 0,
                totalTestCount: 8,
                failedTestCount: 0,
                passedTestCount: 8,
                skippedTestCount: 0,
                expectedFailureCount: 0,
                inferredSummary: "No failing test signal was found for this run.",
                supportingEvidencePath: sourceXCResult.path
            ),
            currentSummary: makeTestSummary(
                headline: "Test run completed with one failing test signal.",
                primaryTestName: "testShowsErrorBanner()",
                primaryTestIdentifier: "AppTests/LoginTests/testShowsErrorBanner()",
                failureMessage: "XCTAssertEqual failed",
                additionalFailureCount: 0,
                totalTestCount: 8,
                failedTestCount: 1,
                passedTestCount: 7,
                skippedTestCount: 0,
                expectedFailureCount: 0,
                inferredSummary: "The run is blocked by failing test AppTests/LoginTests/testShowsErrorBanner(): XCTAssertEqual failed",
                supportingEvidencePath: rerunXCResult.path
            ),
            sourceEvidencePath: sourceXCResult.path,
            currentEvidencePath: rerunXCResult.path
        )
        _ = try store.save(run)

        let workflow = makeWorkflow(store: store)
        let result = await workflow.compare(request: DiagnosisCompareRequest(runId: run.runId))

        #expect(result.isSuccessfulComparison)
        #expect(result.outcome == .regressed)
        #expect(result.status == .failed)
        #expect(result.changedEvidence.contains(where: { $0.field == "Overall status" }))
        #expect(result.changedEvidence.contains(where: { $0.field == "Primary failing test" }))
        #expect(result.unchangedBlockers.isEmpty)
    }

    @Test("missing rerun lineage fails explicitly")
    func missingRerunLineageFailsExplicitly() async throws {
        let tempDir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = RunStore(baseDirectory: tempDir)
        let run = WorkflowRunRecord(
            runId: "run-no-rerun",
            workflow: .diagnosis,
            phase: .diagnosisTest,
            status: .failed,
            createdAt: Date(timeIntervalSince1970: 1_743_700_000),
            updatedAt: Date(timeIntervalSince1970: 1_743_700_100),
            attempt: WorkflowAttemptRecord(
                attemptId: "attempt-1",
                attemptNumber: 1,
                phase: .diagnosisTest,
                startedAt: Date(timeIntervalSince1970: 1_743_700_100),
                status: .failed
            ),
            resolvedContext: makeResolvedContext()
        )
        _ = try store.save(run)

        let workflow = makeWorkflow(store: store)
        let result = await workflow.compare(request: DiagnosisCompareRequest(runId: run.runId))

        #expect(result.isSuccessfulComparison == false)
        #expect(result.failure?.field == .run)
        #expect(result.failure?.classification == .invalidRunState)
    }

    @Test("multi-rerun chains compare the latest attempt against the original source attempt")
    func multiRerunChainsCompareTheLatestAttemptAgainstTheOriginalSourceAttempt() async throws {
        let tempDir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = RunStore(baseDirectory: tempDir)
        let sourceXCResult = tempDir.appendingPathComponent("source-chain.xcresult", isDirectory: true)
        let middleXCResult = tempDir.appendingPathComponent("middle-chain.xcresult", isDirectory: true)
        let latestXCResult = tempDir.appendingPathComponent("latest-chain.xcresult", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceXCResult, withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.createDirectory(at: middleXCResult, withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.createDirectory(at: latestXCResult, withIntermediateDirectories: true, attributes: nil)

        let attempt1 = WorkflowAttemptRecord(
            attemptId: "attempt-1",
            attemptNumber: 1,
            phase: .diagnosisBuild,
            startedAt: Date(timeIntervalSince1970: 1_743_700_000),
            status: .failed
        )
        let attempt2 = WorkflowAttemptRecord(
            attemptId: "attempt-2",
            attemptNumber: 2,
            rerunOfAttemptId: "attempt-1",
            phase: .diagnosisBuild,
            startedAt: Date(timeIntervalSince1970: 1_743_700_100),
            status: .failed
        )
        let attempt3 = WorkflowAttemptRecord(
            attemptId: "attempt-3",
            attemptNumber: 3,
            rerunOfAttemptId: "attempt-2",
            phase: .diagnosisBuild,
            startedAt: Date(timeIntervalSince1970: 1_743_700_200),
            status: .succeeded
        )

        let sourceSummary = makeBuildSummary(
            headline: "Build failed with a primary compiler error.",
            primaryMessage: "Cannot find 'WidgetView' in scope",
            additionalIssueCount: 2,
            errorCount: 2,
            warningCount: 0,
            analyzerWarningCount: 0,
            inferredSummary: "The run failed because WidgetView is unresolved.",
            supportingEvidencePath: sourceXCResult.path
        )
        let middleSummary = makeBuildSummary(
            headline: "Build failed with a narrower compiler error set.",
            primaryMessage: "Cannot find 'WidgetView' in scope",
            additionalIssueCount: 1,
            errorCount: 1,
            warningCount: 0,
            analyzerWarningCount: 0,
            inferredSummary: "The rerun still fails because WidgetView is unresolved.",
            supportingEvidencePath: middleXCResult.path
        )
        let latestSummary = makeBuildSummary(
            headline: "Build succeeded without an error diagnostic.",
            primaryMessage: nil,
            additionalIssueCount: 0,
            errorCount: 0,
            warningCount: 0,
            analyzerWarningCount: 0,
            inferredSummary: "No build failure signal was found for this run.",
            supportingEvidencePath: latestXCResult.path
        )

        let run = WorkflowRunRecord(
            runId: "run-build-chain",
            workflow: .diagnosis,
            phase: .diagnosisBuild,
            status: .succeeded,
            createdAt: Date(timeIntervalSince1970: 1_743_700_000),
            updatedAt: Date(timeIntervalSince1970: 1_743_700_200),
            attempt: attempt3,
            resolvedContext: makeResolvedContext(),
            diagnosisSummary: latestSummary,
            evidence: [
                WorkflowEvidenceRecord(kind: .buildSummary, phase: .diagnosisBuild, attemptId: "attempt-1", attemptNumber: 1, availability: .available, unavailableReason: nil, reference: "run_record.diagnosisSummary", source: "xcforge.diagnosis_build.summary"),
                WorkflowEvidenceRecord(kind: .xcresult, phase: .diagnosisBuild, attemptId: "attempt-1", attemptNumber: 1, availability: .available, unavailableReason: nil, reference: sourceXCResult.path, source: "xcodebuild.result_bundle"),
                WorkflowEvidenceRecord(kind: .buildSummary, phase: .diagnosisBuild, attemptId: "attempt-2", attemptNumber: 2, availability: .available, unavailableReason: nil, reference: "run_record.diagnosisSummary", source: "xcforge.diagnosis_build.summary"),
                WorkflowEvidenceRecord(kind: .xcresult, phase: .diagnosisBuild, attemptId: "attempt-2", attemptNumber: 2, availability: .available, unavailableReason: nil, reference: middleXCResult.path, source: "xcodebuild.result_bundle"),
                WorkflowEvidenceRecord(kind: .buildSummary, phase: .diagnosisBuild, attemptId: "attempt-3", attemptNumber: 3, availability: .available, unavailableReason: nil, reference: "run_record.diagnosisSummary", source: "xcforge.diagnosis_build.summary"),
                WorkflowEvidenceRecord(kind: .xcresult, phase: .diagnosisBuild, attemptId: "attempt-3", attemptNumber: 3, availability: .available, unavailableReason: nil, reference: latestXCResult.path, source: "xcodebuild.result_bundle"),
            ],
            attemptHistory: [
                WorkflowAttemptSnapshot(attempt: attempt1, phase: .diagnosisBuild, status: .failed, resolvedContext: makeResolvedContext(), diagnosisSummary: sourceSummary, recordedAt: Date(timeIntervalSince1970: 1_743_700_000)),
                WorkflowAttemptSnapshot(attempt: attempt2, phase: .diagnosisBuild, status: .failed, resolvedContext: makeResolvedContext(), diagnosisSummary: middleSummary, recordedAt: Date(timeIntervalSince1970: 1_743_700_100)),
                WorkflowAttemptSnapshot(attempt: attempt3, phase: .diagnosisBuild, status: .succeeded, resolvedContext: makeResolvedContext(), diagnosisSummary: latestSummary, recordedAt: Date(timeIntervalSince1970: 1_743_700_200)),
            ]
        )
        _ = try store.save(run)

        let workflow = makeWorkflow(store: store)
        let result = await workflow.compare(request: DiagnosisCompareRequest(runId: run.runId))

        #expect(result.isSuccessfulComparison)
        #expect(result.sourceAttemptId == "attempt-1")
        #expect(result.attemptId == "attempt-3")
    }

    private func makeWorkflow(store: RunStore) -> DiagnosisCompareWorkflow {
        DiagnosisCompareWorkflow(
            loadRun: { runId in try store.load(runId: runId) },
            loadLatestActiveRun: { try store.latestActiveDiagnosisRun() },
            loadLatestRun: { try store.latestDiagnosisRun() },
            runPath: { runId in store.runFileURL(runId: runId) }
        )
    }

    private func makeBuildComparisonRun(
        runId: String,
        sourceStatus: WorkflowStatus,
        currentStatus: WorkflowStatus,
        sourceSummary: BuildDiagnosisSummary,
        currentSummary: BuildDiagnosisSummary,
        sourceEvidencePath: String,
        currentEvidencePath: String
    ) -> WorkflowRunRecord {
        let sourceAttempt = WorkflowAttemptRecord(
            attemptId: "attempt-1",
            attemptNumber: 1,
            phase: .diagnosisBuild,
            startedAt: Date(timeIntervalSince1970: 1_743_700_000),
            status: sourceStatus
        )
        let currentAttempt = WorkflowAttemptRecord(
            attemptId: "attempt-2",
            attemptNumber: 2,
            rerunOfAttemptId: "attempt-1",
            phase: .diagnosisBuild,
            startedAt: Date(timeIntervalSince1970: 1_743_700_100),
            status: currentStatus
        )
        let sourceSnapshot = WorkflowAttemptSnapshot(
            attempt: sourceAttempt,
            phase: .diagnosisBuild,
            status: sourceStatus,
            resolvedContext: makeResolvedContext(),
            diagnosisSummary: sourceSummary,
            recordedAt: Date(timeIntervalSince1970: 1_743_700_000)
        )
        let currentSnapshot = WorkflowAttemptSnapshot(
            attempt: currentAttempt,
            phase: .diagnosisBuild,
            status: currentStatus,
            resolvedContext: makeResolvedContext(),
            diagnosisSummary: currentSummary,
            recordedAt: Date(timeIntervalSince1970: 1_743_700_100)
        )

        return WorkflowRunRecord(
            runId: runId,
            workflow: .diagnosis,
            phase: .diagnosisBuild,
            status: currentStatus,
            createdAt: Date(timeIntervalSince1970: 1_743_700_000),
            updatedAt: Date(timeIntervalSince1970: 1_743_700_100),
            attempt: currentAttempt,
            resolvedContext: makeResolvedContext(),
            diagnosisSummary: currentSummary,
            evidence: [
                WorkflowEvidenceRecord(
                    kind: .buildSummary,
                    phase: .diagnosisBuild,
                    attemptId: sourceAttempt.attemptId,
                    attemptNumber: sourceAttempt.attemptNumber,
                    availability: .available,
                    unavailableReason: nil,
                    reference: "run_record.diagnosisSummary",
                    source: "xcforge.diagnosis_build.summary"
                ),
                WorkflowEvidenceRecord(
                    kind: .xcresult,
                    phase: .diagnosisBuild,
                    attemptId: sourceAttempt.attemptId,
                    attemptNumber: sourceAttempt.attemptNumber,
                    availability: .available,
                    unavailableReason: nil,
                    reference: sourceEvidencePath,
                    source: "xcodebuild.result_bundle"
                ),
                WorkflowEvidenceRecord(
                    kind: .buildSummary,
                    phase: .diagnosisBuild,
                    attemptId: currentAttempt.attemptId,
                    attemptNumber: currentAttempt.attemptNumber,
                    availability: .available,
                    unavailableReason: nil,
                    reference: "run_record.diagnosisSummary",
                    source: "xcforge.diagnosis_build.summary"
                ),
                WorkflowEvidenceRecord(
                    kind: .xcresult,
                    phase: .diagnosisBuild,
                    attemptId: currentAttempt.attemptId,
                    attemptNumber: currentAttempt.attemptNumber,
                    availability: .available,
                    unavailableReason: nil,
                    reference: currentEvidencePath,
                    source: "xcodebuild.result_bundle"
                ),
            ],
            attemptHistory: [
                sourceSnapshot,
                currentSnapshot
            ]
        )
    }

    private func makeTestComparisonRun(
        runId: String,
        sourceStatus: WorkflowStatus,
        currentStatus: WorkflowStatus,
        sourceSummary: TestDiagnosisSummary,
        currentSummary: TestDiagnosisSummary,
        sourceEvidencePath: String,
        currentEvidencePath: String,
        sourceExtraEvidence: [WorkflowEvidenceRecord] = [],
        currentExtraEvidence: [WorkflowEvidenceRecord] = []
    ) -> WorkflowRunRecord {
        let sourceAttempt = WorkflowAttemptRecord(
            attemptId: "attempt-1",
            attemptNumber: 1,
            phase: .diagnosisTest,
            startedAt: Date(timeIntervalSince1970: 1_743_700_000),
            status: sourceStatus
        )
        let currentAttempt = WorkflowAttemptRecord(
            attemptId: "attempt-2",
            attemptNumber: 2,
            rerunOfAttemptId: "attempt-1",
            phase: .diagnosisTest,
            startedAt: Date(timeIntervalSince1970: 1_743_700_100),
            status: currentStatus
        )
        let sourceSnapshot = WorkflowAttemptSnapshot(
            attempt: sourceAttempt,
            phase: .diagnosisTest,
            status: sourceStatus,
            resolvedContext: makeResolvedContext(),
            testDiagnosisSummary: sourceSummary,
            recordedAt: Date(timeIntervalSince1970: 1_743_700_000)
        )
        let currentSnapshot = WorkflowAttemptSnapshot(
            attempt: currentAttempt,
            phase: .diagnosisTest,
            status: currentStatus,
            resolvedContext: makeResolvedContext(),
            testDiagnosisSummary: currentSummary,
            recordedAt: Date(timeIntervalSince1970: 1_743_700_100)
        )

        return WorkflowRunRecord(
            runId: runId,
            workflow: .diagnosis,
            phase: .diagnosisTest,
            status: currentStatus,
            createdAt: Date(timeIntervalSince1970: 1_743_700_000),
            updatedAt: Date(timeIntervalSince1970: 1_743_700_100),
            attempt: currentAttempt,
            resolvedContext: makeResolvedContext(),
            testDiagnosisSummary: currentSummary,
            evidence: [
                WorkflowEvidenceRecord(
                    kind: .testSummary,
                    phase: .diagnosisTest,
                    attemptId: sourceAttempt.attemptId,
                    attemptNumber: sourceAttempt.attemptNumber,
                    availability: .available,
                    unavailableReason: nil,
                    reference: "run_record.testDiagnosisSummary",
                    source: "xcforge.diagnosis_test.summary"
                ),
                WorkflowEvidenceRecord(
                    kind: .xcresult,
                    phase: .diagnosisTest,
                    attemptId: sourceAttempt.attemptId,
                    attemptNumber: sourceAttempt.attemptNumber,
                    availability: .available,
                    unavailableReason: nil,
                    reference: sourceEvidencePath,
                    source: "xcodebuild.result_bundle"
                ),
                WorkflowEvidenceRecord(
                    kind: .testSummary,
                    phase: .diagnosisTest,
                    attemptId: currentAttempt.attemptId,
                    attemptNumber: currentAttempt.attemptNumber,
                    availability: .available,
                    unavailableReason: nil,
                    reference: "run_record.testDiagnosisSummary",
                    source: "xcforge.diagnosis_test.summary"
                ),
                WorkflowEvidenceRecord(
                    kind: .xcresult,
                    phase: .diagnosisTest,
                    attemptId: currentAttempt.attemptId,
                    attemptNumber: currentAttempt.attemptNumber,
                    availability: .available,
                    unavailableReason: nil,
                    reference: currentEvidencePath,
                    source: "xcodebuild.result_bundle"
                ),
            ] + sourceExtraEvidence + currentExtraEvidence,
            attemptHistory: [
                sourceSnapshot,
                currentSnapshot
            ]
        )
    }

    private func makeBuildSummary(
        headline: String,
        primaryMessage: String?,
        additionalIssueCount: Int,
        errorCount: Int,
        warningCount: Int,
        analyzerWarningCount: Int,
        inferredSummary: String,
        supportingEvidencePath: String
    ) -> BuildDiagnosisSummary {
        BuildDiagnosisSummary(
            observedEvidence: ObservedBuildEvidence(
                summary: headline,
                primarySignal: primaryMessage.map {
                    BuildIssueSummary(
                        severity: .error,
                        message: $0,
                        location: SourceLocation(filePath: "/tmp/App/Feature.swift", line: 42, column: 9),
                        source: "xcresult.errors"
                    )
                },
                additionalIssueCount: additionalIssueCount,
                errorCount: errorCount,
                warningCount: warningCount,
                analyzerWarningCount: analyzerWarningCount
            ),
            inferredConclusion: InferredBuildConclusion(summary: inferredSummary),
            supportingEvidence: [
                EvidenceReference(kind: "xcresult", path: supportingEvidencePath, source: "xcodebuild.result_bundle")
            ]
        )
    }

    private func makeTestSummary(
        headline: String,
        primaryTestName: String?,
        primaryTestIdentifier: String?,
        failureMessage: String?,
        additionalFailureCount: Int,
        totalTestCount: Int,
        failedTestCount: Int,
        passedTestCount: Int,
        skippedTestCount: Int,
        expectedFailureCount: Int,
        inferredSummary: String,
        supportingEvidencePath: String
    ) -> TestDiagnosisSummary {
        TestDiagnosisSummary(
            observedEvidence: ObservedTestEvidence(
                summary: headline,
                primaryFailure: primaryTestName.flatMap { testName in
                    guard let primaryTestIdentifier, let failureMessage else {
                        return nil
                    }
                    return TestFailureSummary(
                        testName: testName,
                        testIdentifier: primaryTestIdentifier,
                        message: failureMessage,
                        source: "xcresult.test-details"
                    )
                },
                additionalFailureCount: additionalFailureCount,
                totalTestCount: totalTestCount,
                failedTestCount: failedTestCount,
                passedTestCount: passedTestCount,
                skippedTestCount: skippedTestCount,
                expectedFailureCount: expectedFailureCount
            ),
            inferredConclusion: InferredTestConclusion(summary: inferredSummary),
            supportingEvidence: [
                EvidenceReference(kind: "xcresult", path: supportingEvidencePath, source: "xcodebuild.result_bundle")
            ]
        )
    }

    private func makeResolvedContext() -> ResolvedWorkflowContext {
        ResolvedWorkflowContext(
            project: "/tmp/App.xcodeproj",
            scheme: "App",
            simulator: "SIM-123",
            configuration: "Debug",
            app: AppContext(bundleId: "com.example.app", appPath: "/tmp/Derived/App.app")
        )
    }

    private func makeTempDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true,
            attributes: nil
        )
        return dir
    }
}

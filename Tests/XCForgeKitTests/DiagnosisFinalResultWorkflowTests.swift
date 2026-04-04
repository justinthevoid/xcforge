import Foundation
import Testing
@testable import XCForgeKit

@Suite("DiagnosisFinalResultWorkflow", .serialized)
struct DiagnosisFinalResultWorkflowTests {

    @Test("terminal build result returns proof-oriented summary and JSON round-trips")
    func terminalBuildResultReturnsProofOrientedSummaryAndJSONRoundTrips() async throws {
        let tempDir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = RunStore(baseDirectory: tempDir)
        let xcresultURL = tempDir.appendingPathComponent("final-build.xcresult", isDirectory: true)
        try FileManager.default.createDirectory(at: xcresultURL, withIntermediateDirectories: true, attributes: nil)

        let run = makeTerminalBuildRun(
            runId: "run-final-build",
            status: .failed,
            summary: makeBuildSummary(
                headline: "Build failed with a primary compiler error.",
                primaryMessage: "Cannot find 'WidgetView' in scope",
                additionalIssueCount: 1,
                errorCount: 2,
                warningCount: 0,
                analyzerWarningCount: 0,
                inferredSummary: "The run failed because WidgetView is unresolved.",
                supportingEvidencePath: xcresultURL.path
            ),
            evidencePath: xcresultURL.path
        )
        _ = try store.save(run)

        let workflow = makeWorkflow(store: store)
        let result = await workflow.assemble(request: DiagnosisFinalResultRequest(runId: run.runId))

        #expect(result.isSuccessfulFinalResult)
        #expect(result.status == .failed)
        #expect(result.summary?.headline == "Build failed with a primary compiler error.")
        #expect(result.currentAttempt?.availableEvidence.count == 2)
        #expect(result.sourceAttemptId == nil)
        #expect(result.comparison == nil)
        #expect(result.persistedRunPath == store.runFileURL(runId: run.runId).path)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(result)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(
            DiagnosisFinalResult.self,
            from: jsonData
        )
        #expect(decoded == result)
    }

    @Test("rerun comparison includes meaningful change and both evidence bundles")
    func rerunComparisonIncludesMeaningfulChangeAndBothEvidenceBundles() async throws {
        let tempDir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = RunStore(baseDirectory: tempDir)
        let sourceXCResult = tempDir.appendingPathComponent("source-build.xcresult", isDirectory: true)
        let rerunXCResult = tempDir.appendingPathComponent("rerun-build.xcresult", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceXCResult, withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.createDirectory(at: rerunXCResult, withIntermediateDirectories: true, attributes: nil)

        let run = makeComparisonRun(
            runId: "run-final-compare",
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
        let result = await workflow.assemble(request: DiagnosisFinalResultRequest(runId: run.runId))

        #expect(result.isSuccessfulFinalResult)
        #expect(result.sourceAttemptId == "attempt-1")
        #expect(result.sourceAttempt != nil)
        #expect(result.comparison?.outcome == .improved)
        #expect(result.comparison?.changedEvidence.contains(where: { $0.field == "Overall status" }) == true)
        #expect(result.currentAttempt?.availableEvidence.count == 2)
        #expect(result.sourceAttempt?.availableEvidence.count == 2)
        #expect(result.persistedRunPath == store.runFileURL(runId: run.runId).path)
    }

    @Test("rerun without lineage degrades to the persisted truth with an explicit comparison note")
    func rerunWithoutLineageDegradesToThePersistedTruth() async throws {
        let tempDir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = RunStore(baseDirectory: tempDir)
        let xcresultURL = tempDir.appendingPathComponent("rerun-missing-source.xcresult", isDirectory: true)
        try FileManager.default.createDirectory(at: xcresultURL, withIntermediateDirectories: true, attributes: nil)

        let run = WorkflowRunRecord(
            runId: "run-final-missing-lineage",
            workflow: .diagnosis,
            phase: .diagnosisBuild,
            status: .failed,
            createdAt: Date(timeIntervalSince1970: 1_743_700_000),
            updatedAt: Date(timeIntervalSince1970: 1_743_700_100),
            attempt: WorkflowAttemptRecord(
                attemptId: "attempt-2",
                attemptNumber: 2,
                rerunOfAttemptId: "attempt-missing",
                phase: .diagnosisBuild,
                startedAt: Date(timeIntervalSince1970: 1_743_700_100),
                status: .failed
            ),
            resolvedContext: makeResolvedContext(),
            diagnosisSummary: makeBuildSummary(
                headline: "Build failed with a primary compiler error.",
                primaryMessage: "Cannot find 'WidgetView' in scope",
                additionalIssueCount: 1,
                errorCount: 2,
                warningCount: 0,
                analyzerWarningCount: 0,
                inferredSummary: "The run failed because WidgetView is unresolved.",
                supportingEvidencePath: xcresultURL.path
            ),
            evidence: [
                WorkflowEvidenceRecord(
                    kind: .buildSummary,
                    phase: .diagnosisBuild,
                    attemptId: "attempt-2",
                    attemptNumber: 2,
                    availability: .available,
                    unavailableReason: nil,
                    reference: "run_record.diagnosisSummary",
                    source: "xcforge.diagnosis_build.summary"
                ),
                WorkflowEvidenceRecord(
                    kind: .xcresult,
                    phase: .diagnosisBuild,
                    attemptId: "attempt-2",
                    attemptNumber: 2,
                    availability: .available,
                    unavailableReason: nil,
                    reference: xcresultURL.path,
                    source: "xcodebuild.result_bundle"
                )
            ],
            attemptHistory: [
                WorkflowAttemptSnapshot(
                    attempt: WorkflowAttemptRecord(
                        attemptId: "attempt-2",
                        attemptNumber: 2,
                        rerunOfAttemptId: "attempt-missing",
                        phase: .diagnosisBuild,
                        startedAt: Date(timeIntervalSince1970: 1_743_700_100),
                        status: .failed
                    ),
                    phase: .diagnosisBuild,
                    status: .failed,
                    resolvedContext: makeResolvedContext(),
                    diagnosisSummary: makeBuildSummary(
                        headline: "Build failed with a primary compiler error.",
                        primaryMessage: "Cannot find 'WidgetView' in scope",
                        additionalIssueCount: 1,
                        errorCount: 2,
                        warningCount: 0,
                        analyzerWarningCount: 0,
                        inferredSummary: "The run failed because WidgetView is unresolved.",
                        supportingEvidencePath: xcresultURL.path
                    ),
                    recordedAt: Date(timeIntervalSince1970: 1_743_700_100)
                )
            ]
        )
        _ = try store.save(run)

        let workflow = makeWorkflow(store: store)
        let result = await workflow.assemble(request: DiagnosisFinalResultRequest(runId: run.runId))

        #expect(result.isSuccessfulFinalResult)
        #expect(result.failure == nil)
        #expect(result.currentAttempt?.attemptId == "attempt-2")
        #expect(result.sourceAttemptId == "attempt-missing")
        #expect(result.comparison == nil)
        #expect(result.comparisonNote == "Run run-final-missing-lineage does not include a linked rerun attempt to compare.")
    }

    @Test("unchanged reruns keep their blockers explicit in the final result")
    func unchangedRerunsKeepTheirBlockersExplicitInTheFinalResult() async throws {
        let tempDir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = RunStore(baseDirectory: tempDir)
        let sourceXCResult = tempDir.appendingPathComponent("source-unchanged.xcresult", isDirectory: true)
        let rerunXCResult = tempDir.appendingPathComponent("rerun-unchanged.xcresult", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceXCResult, withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.createDirectory(at: rerunXCResult, withIntermediateDirectories: true, attributes: nil)

        let summary = makeBuildSummary(
            headline: "Build failed with a primary compiler error.",
            primaryMessage: "Cannot find 'WidgetView' in scope",
            additionalIssueCount: 1,
            errorCount: 1,
            warningCount: 0,
            analyzerWarningCount: 0,
            inferredSummary: "The run failed because WidgetView is unresolved.",
            supportingEvidencePath: sourceXCResult.path
        )

        let run = makeComparisonRun(
            runId: "run-final-unchanged",
            sourceSummary: summary,
            currentSummary: summary,
            sourceEvidencePath: sourceXCResult.path,
            currentEvidencePath: rerunXCResult.path,
            currentStatus: .failed
        )
        _ = try store.save(run)

        let workflow = makeWorkflow(store: store)
        let result = await workflow.assemble(request: DiagnosisFinalResultRequest(runId: run.runId))

        #expect(result.isSuccessfulFinalResult)
        #expect(result.comparison?.outcome == .unchanged)
        #expect(result.comparison?.unchangedBlockers.contains("Primary build signal remains: Cannot find 'WidgetView' in scope") == true)
        #expect(result.failure == nil)
    }

    @Test("final results preserve recovery history for recovered runtime runs")
    func finalResultsPreserveRecoveryHistoryForRecoveredRuntimeRuns() async throws {
        let tempDir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = RunStore(baseDirectory: tempDir)
        let runtimeLogURL = tempDir.appendingPathComponent("runtime-recovered.log", isDirectory: false)
        try "Application ready".write(to: runtimeLogURL, atomically: true, encoding: .utf8)

        let recoveryRecord = WorkflowRecoveryRecord(
            recoveryId: "recovery-1",
            sourceAttemptId: "attempt-1",
            sourceAttemptNumber: 1,
            triggeringAttemptId: "attempt-runtime-2",
            triggeringAttemptNumber: 2,
            recoveryAttemptId: "attempt-runtime-3",
            recoveryAttemptNumber: 3,
            issue: .brokenLaunchContinuity,
            detectedIssue: "The app launched but did not remain running through the runtime capture window.",
            action: .resetLaunchContinuity,
            status: .succeeded,
            resumed: true,
            summary: "Recovered from broken launch continuity and resumed runtime diagnosis.",
            detail: "Reset state terminated a running app before retrying.",
            recordedAt: Date(timeIntervalSince1970: 1_743_700_220)
        )

        let run = WorkflowRunRecord(
            runId: "run-final-runtime-recovery",
            workflow: .diagnosis,
            phase: .diagnosisRuntime,
            status: .succeeded,
            createdAt: Date(timeIntervalSince1970: 1_743_700_000),
            updatedAt: Date(timeIntervalSince1970: 1_743_700_220),
            attempt: WorkflowAttemptRecord(
                attemptId: "attempt-runtime-3",
                attemptNumber: 3,
                rerunOfAttemptId: "attempt-runtime-2",
                phase: .diagnosisRuntime,
                startedAt: Date(timeIntervalSince1970: 1_743_700_220),
                status: .succeeded
            ),
            resolvedContext: makeResolvedContext(),
            runtimeSummary: RuntimeDiagnosisSummary(
                observedEvidence: ObservedRuntimeEvidence(
                    summary: "App com.example.app was relaunched and runtime signals were captured.",
                    launchedApp: true,
                    appRunning: true,
                    relaunchedApp: true,
                    primarySignal: RuntimeSignalSummary(
                        stream: .stdout,
                        message: "Application ready",
                        source: "simctl.launch_console.stdout"
                    ),
                    additionalSignalCount: 0,
                    stdoutLineCount: 2,
                    stderrLineCount: 0
                ),
                inferredConclusion: InferredRuntimeConclusion(
                    summary: "Runtime inspection reached a running app state with captured console output or a confirmed live console session."
                ),
                supportingEvidence: [
                    EvidenceReference(kind: "console_log", path: runtimeLogURL.path, source: "simctl.launch_console")
                ]
            ),
            recoveryHistory: [recoveryRecord],
            evidence: [
                WorkflowEvidenceRecord(
                    kind: .runtimeSummary,
                    phase: .diagnosisRuntime,
                    attemptId: "attempt-runtime-2",
                    attemptNumber: 2,
                    availability: .available,
                    unavailableReason: nil,
                    reference: "run_record.runtimeSummary",
                    source: "xcforge.diagnosis_runtime.summary"
                ),
                WorkflowEvidenceRecord(
                    kind: .runtimeSummary,
                    phase: .diagnosisRuntime,
                    attemptId: "attempt-runtime-3",
                    attemptNumber: 3,
                    availability: .available,
                    unavailableReason: nil,
                    reference: "run_record.runtimeSummary",
                    source: "xcforge.diagnosis_runtime.summary"
                ),
                WorkflowEvidenceRecord(
                    kind: .consoleLog,
                    phase: .diagnosisRuntime,
                    attemptId: "attempt-runtime-3",
                    attemptNumber: 3,
                    availability: .available,
                    unavailableReason: nil,
                    reference: runtimeLogURL.path,
                    source: "simctl.launch_console"
                )
            ],
            attemptHistory: [
                WorkflowAttemptSnapshot(
                    attempt: WorkflowAttemptRecord(
                        attemptId: "attempt-1",
                        attemptNumber: 1,
                        phase: .diagnosisStart,
                        startedAt: Date(timeIntervalSince1970: 1_743_700_000),
                        status: .inProgress
                    ),
                    phase: .diagnosisStart,
                    status: .inProgress,
                    resolvedContext: makeResolvedContext(),
                    recordedAt: Date(timeIntervalSince1970: 1_743_700_000)
                ),
                WorkflowAttemptSnapshot(
                    attempt: WorkflowAttemptRecord(
                        attemptId: "attempt-runtime-2",
                        attemptNumber: 2,
                        rerunOfAttemptId: "attempt-1",
                        phase: .diagnosisRuntime,
                        startedAt: Date(timeIntervalSince1970: 1_743_700_100),
                        status: .partial
                    ),
                    phase: .diagnosisRuntime,
                    status: .partial,
                    resolvedContext: makeResolvedContext(),
                    runtimeSummary: RuntimeDiagnosisSummary(
                        observedEvidence: ObservedRuntimeEvidence(
                            summary: "App com.example.app launched, but runtime inspection ended before the app stayed running.",
                            launchedApp: true,
                            appRunning: false,
                            relaunchedApp: false,
                            primarySignal: RuntimeSignalSummary(
                                stream: .stderr,
                                message: "launchctl print stalled",
                                source: "simctl.launch_console.stderr"
                            ),
                            additionalSignalCount: 0,
                            stdoutLineCount: 1,
                            stderrLineCount: 1
                        ),
                        inferredConclusion: InferredRuntimeConclusion(
                            summary: "The app reached launch, but the runtime state remained unstable or exited before the capture window completed."
                        ),
                        supportingEvidence: []
                    ),
                    recordedAt: Date(timeIntervalSince1970: 1_743_700_100)
                ),
                WorkflowAttemptSnapshot(
                    attempt: WorkflowAttemptRecord(
                        attemptId: "attempt-runtime-3",
                        attemptNumber: 3,
                        rerunOfAttemptId: "attempt-runtime-2",
                        phase: .diagnosisRuntime,
                        startedAt: Date(timeIntervalSince1970: 1_743_700_220),
                        status: .succeeded
                    ),
                    phase: .diagnosisRuntime,
                    status: .succeeded,
                    resolvedContext: makeResolvedContext(),
                    runtimeSummary: RuntimeDiagnosisSummary(
                        observedEvidence: ObservedRuntimeEvidence(
                            summary: "App com.example.app was relaunched and runtime signals were captured.",
                            launchedApp: true,
                            appRunning: true,
                            relaunchedApp: true,
                            primarySignal: RuntimeSignalSummary(
                                stream: .stdout,
                                message: "Application ready",
                                source: "simctl.launch_console.stdout"
                            ),
                            additionalSignalCount: 0,
                            stdoutLineCount: 2,
                            stderrLineCount: 0
                        ),
                        inferredConclusion: InferredRuntimeConclusion(
                            summary: "Runtime inspection reached a running app state with captured console output or a confirmed live console session."
                        ),
                        supportingEvidence: [
                            EvidenceReference(kind: "console_log", path: runtimeLogURL.path, source: "simctl.launch_console")
                        ]
                    ),
                    recordedAt: Date(timeIntervalSince1970: 1_743_700_220)
                )
            ]
        )
        _ = try store.save(run)

        let workflow = makeWorkflow(store: store)
        let result = await workflow.assemble(request: DiagnosisFinalResultRequest(runId: run.runId))

        #expect(result.isSuccessfulFinalResult)
        #expect(result.recoveryHistory.count == 1)
        #expect(result.recoveryHistory.first?.summary == "Recovered from broken launch continuity and resumed runtime diagnosis.")
        #expect(result.currentAttempt?.attemptId == "attempt-runtime-3")
    }

    @Test("missing or non-terminal runs fail explicitly")
    func missingOrNonTerminalRunsFailExplicitly() async throws {
        let tempDir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let missingWorkflow = DiagnosisFinalResultWorkflow(
            loadRun: { _ in throw CocoaError(.fileNoSuchFile) },
            loadLatestActiveRun: { nil },
            loadLatestTerminalRun: { nil },
            loadLatestRun: { nil },
            runPath: { runId in tempDir.appendingPathComponent("\(runId).json") }
        )
        let missingResult = await missingWorkflow.assemble(request: DiagnosisFinalResultRequest(runId: "missing-run"))

        #expect(missingResult.isSuccessfulFinalResult == false)
        #expect(missingResult.failure?.field == .run)
        #expect(missingResult.failure?.classification == .notFound)

        let nonTerminalStore = RunStore(baseDirectory: tempDir)
        let nonTerminalRun = WorkflowRunRecord(
            runId: "run-in-progress",
            workflow: .diagnosis,
            phase: .diagnosisBuild,
            status: .inProgress,
            createdAt: Date(timeIntervalSince1970: 1_743_700_000),
            updatedAt: Date(timeIntervalSince1970: 1_743_700_100),
            attempt: WorkflowAttemptRecord(
                attemptId: "attempt-1",
                attemptNumber: 1,
                phase: .diagnosisBuild,
                startedAt: Date(timeIntervalSince1970: 1_743_700_100),
                status: .inProgress
            ),
            resolvedContext: makeResolvedContext()
        )
        _ = try nonTerminalStore.save(nonTerminalRun)

        let workflow = makeWorkflow(store: nonTerminalStore)
        let result = await workflow.assemble(request: DiagnosisFinalResultRequest(runId: nonTerminalRun.runId))

        #expect(result.isSuccessfulFinalResult == false)
        #expect(result.failure?.field == .run)
        #expect(result.failure?.classification == .invalidRunState)
    }

    @Test("omitted run id prefers the newest terminal diagnosis run over an active one")
    func omittedRunIdPrefersNewestTerminalDiagnosisRun() async throws {
        let tempDir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = RunStore(baseDirectory: tempDir)
        let terminalXCResult = tempDir.appendingPathComponent("terminal-build.xcresult", isDirectory: true)
        try FileManager.default.createDirectory(at: terminalXCResult, withIntermediateDirectories: true, attributes: nil)

        let terminalRun = makeTerminalBuildRun(
            runId: "run-terminal",
            status: .succeeded,
            summary: makeBuildSummary(
                headline: "Build succeeded without an error diagnostic.",
                primaryMessage: nil,
                additionalIssueCount: 0,
                errorCount: 0,
                warningCount: 1,
                analyzerWarningCount: 0,
                inferredSummary: "No build failure signal was found for this run.",
                supportingEvidencePath: terminalXCResult.path
            ),
            evidencePath: terminalXCResult.path,
            updatedAt: Date(timeIntervalSince1970: 1_743_700_100)
        )
        _ = try store.save(terminalRun)

        let activeRun = WorkflowRunRecord(
            runId: "run-active",
            workflow: .diagnosis,
            phase: .diagnosisBuild,
            status: .inProgress,
            createdAt: Date(timeIntervalSince1970: 1_743_700_200),
            updatedAt: Date(timeIntervalSince1970: 1_743_700_300),
            attempt: WorkflowAttemptRecord(
                attemptId: "attempt-active",
                attemptNumber: 1,
                phase: .diagnosisBuild,
                startedAt: Date(timeIntervalSince1970: 1_743_700_200),
                status: .inProgress
            ),
            resolvedContext: makeResolvedContext()
        )
        _ = try store.save(activeRun)

        let workflow = makeWorkflow(store: store)
        let result = await workflow.assemble(request: DiagnosisFinalResultRequest())

        #expect(result.isSuccessfulFinalResult)
        #expect(result.runId == "run-terminal")
        #expect(result.status == .succeeded)
        #expect(result.failure == nil)
    }

    private func makeWorkflow(store: RunStore) -> DiagnosisFinalResultWorkflow {
        DiagnosisFinalResultWorkflow(
            loadRun: { runId in try store.load(runId: runId) },
            loadLatestActiveRun: { try store.latestActiveDiagnosisRun() },
            loadLatestTerminalRun: { try store.latestTerminalDiagnosisRun() },
            loadLatestRun: { try store.latestDiagnosisRun() },
            runPath: { runId in store.runFileURL(runId: runId) }
        )
    }

    private func makeComparisonRun(
        runId: String,
        sourceSummary: BuildDiagnosisSummary,
        currentSummary: BuildDiagnosisSummary,
        sourceEvidencePath: String,
        currentEvidencePath: String,
        currentStatus: WorkflowStatus = .succeeded
    ) -> WorkflowRunRecord {
        let sourceAttempt = WorkflowAttemptRecord(
            attemptId: "attempt-1",
            attemptNumber: 1,
            phase: .diagnosisBuild,
            startedAt: Date(timeIntervalSince1970: 1_743_700_000),
            status: .failed
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
            status: .failed,
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

    private func makeTerminalBuildRun(
        runId: String,
        status: WorkflowStatus,
        summary: BuildDiagnosisSummary,
        evidencePath: String,
        updatedAt: Date = Date(timeIntervalSince1970: 1_743_700_100)
    ) -> WorkflowRunRecord {
        let attempt = WorkflowAttemptRecord(
            attemptId: "attempt-1",
            attemptNumber: 1,
            phase: .diagnosisBuild,
            startedAt: Date(timeIntervalSince1970: 1_743_700_000),
            status: status
        )
        return WorkflowRunRecord(
            runId: runId,
            workflow: .diagnosis,
            phase: .diagnosisBuild,
            status: status,
            createdAt: Date(timeIntervalSince1970: 1_743_700_000),
            updatedAt: updatedAt,
            attempt: attempt,
            resolvedContext: makeResolvedContext(),
            diagnosisSummary: summary,
            evidence: [
                WorkflowEvidenceRecord(
                    kind: .buildSummary,
                    phase: .diagnosisBuild,
                    attemptId: attempt.attemptId,
                    attemptNumber: attempt.attemptNumber,
                    availability: .available,
                    unavailableReason: nil,
                    reference: "run_record.diagnosisSummary",
                    source: "xcforge.diagnosis_build.summary"
                ),
                WorkflowEvidenceRecord(
                    kind: .xcresult,
                    phase: .diagnosisBuild,
                    attemptId: attempt.attemptId,
                    attemptNumber: attempt.attemptNumber,
                    availability: .available,
                    unavailableReason: nil,
                    reference: evidencePath,
                    source: "xcodebuild.result_bundle"
                ),
                WorkflowEvidenceRecord(
                    kind: .stderr,
                    phase: .diagnosisBuild,
                    attemptId: attempt.attemptId,
                    attemptNumber: attempt.attemptNumber,
                    availability: .unavailable,
                    unavailableReason: .notCaptured,
                    reference: nil,
                    source: "xcodebuild.stderr",
                    detail: "No stderr artifact was captured for this build diagnosis phase."
                ),
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

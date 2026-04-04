import Foundation

public struct DiagnosisRuntimeWorkflow: Sendable {
    typealias LoadRun = @Sendable (String) throws -> WorkflowRunRecord
    typealias PersistRun = @Sendable (WorkflowRunRecord) throws -> URL
    typealias ResolveSimulator = @Sendable (String) async throws -> String
    typealias CaptureRuntime = @Sendable (String, String) async throws -> ConsoleTools.RuntimeSignalCapture
    typealias ResetRuntimeContinuity = @Sendable (String, String, WDAClient) async -> SimTools.RuntimeContinuityReset
    typealias CaptureScreenshot = @Sendable (String, URL) async -> ScreenshotTools.WorkflowCaptureResult
    typealias ArtifactURL = @Sendable (String, String, String, String) -> URL
    typealias NowProvider = @Sendable () -> Date
    typealias IDProvider = @Sendable () -> String

    private let loadRun: LoadRun
    private let persistRun: PersistRun
    private let resolveSimulator: ResolveSimulator
    private let captureRuntime: CaptureRuntime
    private let resetRuntimeContinuity: ResetRuntimeContinuity
    private let captureScreenshot: CaptureScreenshot
    private let artifactURL: ArtifactURL
    private let now: NowProvider
    private let makeID: IDProvider
    private let wdaClient: WDAClient

    public init(wdaClient: WDAClient = WDAClient()) {
        self.init(
            loadRun: { runId in
                let store = RunStore()
                let fileURL = store.runFileURL(runId: runId)
                guard FileManager.default.fileExists(atPath: fileURL.path) else {
                    throw DiagnosisRuntimeWorkflowError(
                        status: .failed,
                        field: .run,
                        classification: .notFound,
                        message: "No diagnosis run was found for run ID \(runId).",
                        options: []
                    )
                }
                return try store.load(runId: runId)
            },
            persistRun: { run in try RunStore().update(run) },
            resolveSimulator: { try await SimTools.resolveSimulator($0) },
            captureRuntime: { simulatorUDID, bundleId in
                try await ConsoleTools.captureRuntimeSignals(
                    simulatorUDID: simulatorUDID,
                    bundleId: bundleId,
                    env: .live
                )
            },
            resetRuntimeContinuity: { simulatorUDID, bundleId, wdaClient in
                await ConsoleTools.resetRuntimeCaptureContext(
                    simulatorUDID: simulatorUDID,
                    bundleId: bundleId,
                    wdaClient: wdaClient
                )
            },
            captureScreenshot: { simulatorUDID, outputURL in
                await ScreenshotTools.captureWorkflowScreenshot(
                    simulatorUDID: simulatorUDID,
                    outputURL: outputURL
                )
            },
            artifactURL: { runId, attemptId, name, ext in
                RunStore().evidenceFileURL(runId: runId, attemptId: attemptId, name: name, ext: ext)
            },
            now: Date.init,
            makeID: { UUID().uuidString.lowercased() },
            wdaClient: wdaClient
        )
    }

    init(
        loadRun: @escaping LoadRun,
        persistRun: @escaping PersistRun,
        resolveSimulator: @escaping ResolveSimulator,
        captureRuntime: @escaping CaptureRuntime,
        resetRuntimeContinuity: @escaping ResetRuntimeContinuity = { await ConsoleTools.resetRuntimeCaptureContext(simulatorUDID: $0, bundleId: $1, wdaClient: $2) },
        captureScreenshot: @escaping CaptureScreenshot,
        artifactURL: @escaping ArtifactURL,
        now: @escaping NowProvider = Date.init,
        makeID: @escaping IDProvider = { UUID().uuidString.lowercased() },
        wdaClient: WDAClient = WDAClient()
    ) {
        self.loadRun = loadRun
        self.persistRun = persistRun
        self.resolveSimulator = resolveSimulator
        self.captureRuntime = captureRuntime
        self.resetRuntimeContinuity = resetRuntimeContinuity
        self.captureScreenshot = captureScreenshot
        self.artifactURL = artifactURL
        self.now = now
        self.makeID = makeID
        self.wdaClient = wdaClient
    }

    public func diagnose(request: DiagnosisRuntimeRequest) async -> DiagnosisRuntimeResult {
        var resolvedRun: WorkflowRunRecord?

        do {
            let run: WorkflowRunRecord
            do {
                run = try loadRun(request.runId)
            } catch let error as DiagnosisRuntimeWorkflowError {
                throw error
            } catch let error as CocoaError
                where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
                throw DiagnosisRuntimeWorkflowError(
                    status: .failed,
                    field: .run,
                    classification: .notFound,
                    message: "No diagnosis run was found for run ID \(request.runId).",
                    options: []
                )
            } catch {
                throw DiagnosisRuntimeWorkflowError(
                    status: .failed,
                    field: .run,
                    classification: .executionFailed,
                    message: "\(error)",
                    options: []
                )
            }
            resolvedRun = run

            try Self.validate(run)

            let nextAttemptNumber = (run.backfilledAttemptHistory.map { $0.attempt.attemptNumber }.max() ?? run.attempt.attemptNumber) + 1
            let runtimeAttemptId = makeID()
            let runtimeStartedAt = now()

            let simulatorUDID: String
            do {
                simulatorUDID = try await resolveSimulator(run.resolvedContext.simulator)
            } catch {
                return await persistRuntimeFailure(
                    run: run,
                    attemptId: runtimeAttemptId,
                    attemptNumber: nextAttemptNumber,
                    startedAt: runtimeStartedAt,
                    message: "\(error)",
                    requestedScreenshot: request.captureScreenshot,
                    recoveryHistory: run.recoveryHistory
                )
            }

            let capture: ConsoleTools.RuntimeSignalCapture
            do {
                capture = try await captureRuntime(simulatorUDID, run.resolvedContext.app.bundleId)
            } catch {
                return await persistRuntimeFailure(
                    run: run,
                    attemptId: runtimeAttemptId,
                    attemptNumber: nextAttemptNumber,
                    startedAt: runtimeStartedAt,
                    message: "\(error)",
                    requestedScreenshot: request.captureScreenshot,
                    recoveryHistory: run.recoveryHistory
                )
            }

            let initialConsoleReference: String?
            do {
                initialConsoleReference = try persistConsoleArtifact(
                    runId: run.runId,
                    attemptId: runtimeAttemptId,
                    text: capture.combinedText
                )
            } catch {
                return await persistRuntimeFailure(
                    run: run,
                    attemptId: runtimeAttemptId,
                    attemptNumber: nextAttemptNumber,
                    startedAt: runtimeStartedAt,
                    message: "\(error)",
                    requestedScreenshot: request.captureScreenshot,
                    recoveryHistory: run.recoveryHistory
                )
            }

            let initialScreenshotCapture = await captureScreenshotIfRequested(
                request.captureScreenshot,
                simulatorUDID: simulatorUDID,
                runId: run.runId,
                attemptId: runtimeAttemptId
            )
            let initialSummary = Self.runtimeSummary(
                bundleId: run.resolvedContext.app.bundleId,
                capture: capture,
                consoleReference: initialConsoleReference,
                screenshotCapture: initialScreenshotCapture
            )
            let initialOutcome = Self.classifyOutcome(
                bundleId: run.resolvedContext.app.bundleId,
                capture: capture,
                screenshotCapture: initialScreenshotCapture,
                requestedScreenshot: request.captureScreenshot
            )
            let initialAttempt = WorkflowAttemptRecord(
                attemptId: runtimeAttemptId,
                attemptNumber: nextAttemptNumber,
                rerunOfAttemptId: run.attempt.attemptId,
                phase: .diagnosisRuntime,
                startedAt: runtimeStartedAt,
                status: initialOutcome.status
            )
            let initialEvidence = Self.evidence(
                for: initialSummary,
                consoleReference: initialConsoleReference,
                screenshotCapture: initialScreenshotCapture,
                attempt: initialAttempt,
                requestedScreenshot: request.captureScreenshot
            )

            guard let recoveryPlan = Self.recoveryPlan(
                bundleId: run.resolvedContext.app.bundleId,
                capture: capture,
                outcome: initialOutcome.status
            ) else {
                return await persistRuntimeResult(
                    run: run,
                    attempt: initialAttempt,
                    runtimeSummary: initialSummary,
                    recoveryHistory: run.recoveryHistory,
                    evidence: run.evidence + initialEvidence,
                    attemptSnapshots: [
                        Self.makeAttemptSnapshot(
                            attempt: initialAttempt,
                            resolvedContext: run.resolvedContext,
                            diagnosisSummary: run.diagnosisSummary,
                            testDiagnosisSummary: run.testDiagnosisSummary,
                            runtimeSummary: initialSummary,
                            recordedAt: runtimeStartedAt
                        )
                    ],
                    status: initialOutcome.status,
                    failure: initialOutcome.failure
                )
            }

            let recoveryStartedAt = now()
            let recoveryAttemptId = makeID()
            let recoveryAttemptNumber = nextAttemptNumber + 1
            let continuityReset = await resetRuntimeContinuity(
                simulatorUDID,
                run.resolvedContext.app.bundleId,
                wdaClient
            )
            let recoveryConsoleReference: String?
            let recoveryScreenshotCapture: ScreenshotTools.WorkflowCaptureResult?
            let recoverySummary: RuntimeDiagnosisSummary?
            let recoveryAttemptStatus: WorkflowStatus
            let persistedStatus: WorkflowStatus
            let persistedFailure: WorkflowFailure?
            let recoveryEvidence: [WorkflowEvidenceRecord]
            let recoveryAttempt: WorkflowAttemptRecord
            let recoveryResumed: Bool

            do {
                let retryCapture = try await captureRuntime(simulatorUDID, run.resolvedContext.app.bundleId)
                recoveryConsoleReference = try persistConsoleArtifact(
                    runId: run.runId,
                    attemptId: recoveryAttemptId,
                    text: retryCapture.combinedText
                )
                recoveryScreenshotCapture = await captureScreenshotIfRequested(
                    request.captureScreenshot,
                    simulatorUDID: simulatorUDID,
                    runId: run.runId,
                    attemptId: recoveryAttemptId
                )
                recoverySummary = Self.runtimeSummary(
                    bundleId: run.resolvedContext.app.bundleId,
                    capture: retryCapture,
                    consoleReference: recoveryConsoleReference,
                    screenshotCapture: recoveryScreenshotCapture
                )
                let recoveryOutcome = Self.classifyOutcome(
                    bundleId: run.resolvedContext.app.bundleId,
                    capture: retryCapture,
                    screenshotCapture: recoveryScreenshotCapture,
                    requestedScreenshot: request.captureScreenshot
                )
                recoveryAttemptStatus = recoveryOutcome.status
                persistedStatus = recoveryOutcome.status
                persistedFailure = recoveryOutcome.failure
                recoveryAttempt = WorkflowAttemptRecord(
                    attemptId: recoveryAttemptId,
                    attemptNumber: recoveryAttemptNumber,
                    rerunOfAttemptId: initialAttempt.attemptId,
                    phase: .diagnosisRuntime,
                    startedAt: recoveryStartedAt,
                    status: recoveryAttemptStatus
                )
                recoveryEvidence = Self.evidence(
                    for: recoverySummary!,
                    consoleReference: recoveryConsoleReference,
                    screenshotCapture: recoveryScreenshotCapture,
                    attempt: recoveryAttempt,
                    requestedScreenshot: request.captureScreenshot
                )
                recoveryResumed = Self.didResumeRuntime(
                    bundleId: run.resolvedContext.app.bundleId,
                    capture: retryCapture
                )
            } catch {
                recoveryConsoleReference = nil
                recoveryScreenshotCapture = nil
                recoverySummary = nil
                recoveryAttemptStatus = .failed
                persistedStatus = initialOutcome.status == .partial ? .partial : .failed
                persistedFailure = WorkflowFailure(
                    field: Self.classifyFailureField(message: "\(error)"),
                    classification: .executionFailed,
                    message: "\(error)",
                    observed: ObservedFailureEvidence(
                        summary: "\(error)"
                    ),
                    inferred: InferredFailureConclusion(
                        summary: "Recovery runtime capture failed; the app may have crashed or the simulator environment became unstable."
                    ),
                    recoverability: .retryAfterFix
                )
                recoveryAttempt = WorkflowAttemptRecord(
                    attemptId: recoveryAttemptId,
                    attemptNumber: recoveryAttemptNumber,
                    rerunOfAttemptId: initialAttempt.attemptId,
                    phase: .diagnosisRuntime,
                    startedAt: recoveryStartedAt,
                    status: recoveryAttemptStatus
                )
                recoveryEvidence = Self.unavailableEvidence(
                    for: recoveryAttempt,
                    message: "\(error)",
                    requestedScreenshot: request.captureScreenshot
                )
                recoveryResumed = false
            }

            let recoveryRecord = WorkflowRecoveryRecord(
                recoveryId: makeID(),
                sourceAttemptId: run.attempt.attemptId,
                sourceAttemptNumber: run.attempt.attemptNumber,
                triggeringAttemptId: initialAttempt.attemptId,
                triggeringAttemptNumber: initialAttempt.attemptNumber,
                recoveryAttemptId: recoveryAttempt.attemptId,
                recoveryAttemptNumber: recoveryAttempt.attemptNumber,
                issue: recoveryPlan.issue,
                detectedIssue: recoveryPlan.detectedIssue,
                action: .resetLaunchContinuity,
                status: recoveryAttemptStatus,
                resumed: recoveryResumed,
                summary: recoveryPlan.summary,
                detail: Self.recoveryDetail(
                    base: recoveryPlan.detail,
                    resetWasNeeded: continuityReset.wasRunning,
                    sessionCleared: continuityReset.sessionCleared
                ),
                recordedAt: recoveryStartedAt
            )

            return await persistRuntimeResult(
                run: run,
                attempt: recoveryAttempt,
                runtimeSummary: recoverySummary ?? initialSummary,
                recoveryHistory: run.recoveryHistory + [recoveryRecord],
                evidence: run.evidence + initialEvidence + recoveryEvidence,
                attemptSnapshots: [
                    Self.makeAttemptSnapshot(
                        attempt: initialAttempt,
                        resolvedContext: run.resolvedContext,
                        diagnosisSummary: run.diagnosisSummary,
                        testDiagnosisSummary: run.testDiagnosisSummary,
                        runtimeSummary: initialSummary,
                        recordedAt: runtimeStartedAt
                    ),
                    Self.makeAttemptSnapshot(
                        attempt: recoveryAttempt,
                        resolvedContext: run.resolvedContext,
                        diagnosisSummary: run.diagnosisSummary,
                        testDiagnosisSummary: run.testDiagnosisSummary,
                        runtimeSummary: recoverySummary,
                        recordedAt: recoveryStartedAt
                    )
                ],
                status: persistedStatus,
                failure: persistedFailure
            )
        } catch let error as DiagnosisRuntimeWorkflowError {
            return DiagnosisRuntimeResult(
                status: error.status,
                runId: request.runId,
                attemptId: nil,
                resolvedContext: resolvedRun?.resolvedContext,
                summary: nil,
                recoveryHistory: resolvedRun?.recoveryHistory ?? [],
                evidence: resolvedRun?.evidence ?? [],
                failure: WorkflowFailure(
                    field: error.field,
                    classification: error.classification,
                    message: error.message,
                    options: error.options,
                    observed: ObservedFailureEvidence(
                        summary: error.message
                    ),
                    recoverability: error.classification == .executionFailed
                        ? .retryAfterFix : .stop
                ),
                persistedRunPath: nil
            )
        } catch {
            return DiagnosisRuntimeResult(
                status: .failed,
                runId: request.runId,
                attemptId: nil,
                resolvedContext: resolvedRun?.resolvedContext,
                summary: nil,
                recoveryHistory: resolvedRun?.recoveryHistory ?? [],
                evidence: resolvedRun?.evidence ?? [],
                failure: WorkflowFailure(
                    field: .workflow,
                    classification: .executionFailed,
                    message: "\(error)",
                    observed: ObservedFailureEvidence(
                        summary: "\(error)"
                    ),
                    inferred: InferredFailureConclusion(
                        summary: "An unexpected error occurred during runtime diagnosis; the workflow could not complete."
                    ),
                    recoverability: .retryAfterFix
                ),
                persistedRunPath: nil
            )
        }
    }

    static func validate(_ run: WorkflowRunRecord) throws {
        guard run.workflow == .diagnosis else {
            throw DiagnosisRuntimeWorkflowError(
                status: .failed,
                field: .run,
                classification: .invalidRunState,
                message: "Run \(run.runId) is not a diagnosis workflow run.",
                options: []
            )
        }

        switch run.phase {
        case .diagnosisStart, .diagnosisBuild, .diagnosisTest:
            return
        case .diagnosisRuntime:
            throw DiagnosisRuntimeWorkflowError(
                status: .failed,
                field: .run,
                classification: .invalidRunState,
                message: "Run \(run.runId) has already completed diagnosis_runtime; repeat runtime or recovery attempts belong to a later workflow story.",
                options: []
            )
        }
    }

    private func persistConsoleArtifact(runId: String, attemptId: String, text: String) throws -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let url = artifactURL(runId, attemptId, "runtime-console", "log")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        try trimmed.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    private func captureScreenshotIfRequested(
        _ requestedScreenshot: Bool,
        simulatorUDID: String,
        runId: String,
        attemptId: String
    ) async -> ScreenshotTools.WorkflowCaptureResult? {
        guard requestedScreenshot else {
            return nil
        }

        let outputURL = artifactURL(runId, attemptId, "runtime-screenshot", "png")
        return await captureScreenshot(simulatorUDID, outputURL)
    }

    private static func makeAttemptSnapshot(
        attempt: WorkflowAttemptRecord,
        resolvedContext: ResolvedWorkflowContext,
        diagnosisSummary: BuildDiagnosisSummary?,
        testDiagnosisSummary: TestDiagnosisSummary?,
        runtimeSummary: RuntimeDiagnosisSummary?,
        recordedAt: Date
    ) -> WorkflowAttemptSnapshot {
        WorkflowAttemptSnapshot(
            attempt: attempt,
            phase: .diagnosisRuntime,
            status: attempt.status,
            resolvedContext: resolvedContext,
            diagnosisSummary: diagnosisSummary,
            testDiagnosisSummary: testDiagnosisSummary,
            runtimeSummary: runtimeSummary,
            recordedAt: recordedAt
        )
    }

    private static func recoveryPlan(
        bundleId: String,
        capture: ConsoleTools.RuntimeSignalCapture,
        outcome: WorkflowStatus
    ) -> RuntimeRecoveryPlan? {
        guard outcome == .partial || outcome == .failed else {
            return nil
        }

        let signalText = (capture.stdout + capture.stderr)
            .joined(separator: "\n")
            .lowercased()

        if Self.containsAny(
            signalText,
            markers: ["stale simulator state", "wda session stale", "stale session"]
        ) {
            return RuntimeRecoveryPlan(
                issue: .staleSimulatorState,
                detectedIssue: "The runtime capture reported stale simulator state.",
                summary: "xcforge reset stale simulator continuity and retried runtime capture.",
                detail: "A stale simulator or session state was detected while inspecting \(bundleId)."
            )
        }

        guard Self.hasLaunchSignal(bundleId: bundleId, capture: capture),
            capture.isRunning == false,
            Self.isSupportedLaunchContinuityBreak(capture: capture, signalText: signalText)
        else {
            return nil
        }

        return RuntimeRecoveryPlan(
            issue: .brokenLaunchContinuity,
            detectedIssue: "The app launched but did not remain running through the runtime capture window.",
            summary: "xcforge reset launch continuity and retried runtime capture.",
            detail: "The runtime capture observed launch continuity breaking before the app stayed running."
        )
    }

    private static func recoveryDetail(base: String?, resetWasNeeded: Bool, sessionCleared: Bool) -> String {
        let resetDescription = resetWasNeeded
            ? "Reset state terminated a running app before retrying."
            : "Reset state found no running app to terminate before retrying."
        let sessionDescription = sessionCleared
            ? "WDA session context was cleared before retrying."
            : "WDA session context could not be confirmed cleared before retrying."
        let detail = [base, resetDescription, sessionDescription]
            .compactMap { value in
                guard let value, !value.isEmpty else {
                    return nil
                }
                return value
            }
            .joined(separator: " ")
        if !detail.isEmpty {
            return detail
        }
        return resetDescription + " " + sessionDescription
    }

    private func persistRuntimeFailure(
        run: WorkflowRunRecord,
        attemptId: String,
        attemptNumber: Int,
        startedAt: Date,
        message: String,
        requestedScreenshot: Bool,
        recoveryHistory: [WorkflowRecoveryRecord]
    ) async -> DiagnosisRuntimeResult {
        let attempt = WorkflowAttemptRecord(
            attemptId: attemptId,
            attemptNumber: attemptNumber,
            rerunOfAttemptId: run.attempt.attemptId,
            phase: .diagnosisRuntime,
            startedAt: startedAt,
            status: .failed
        )
        let evidence = Self.unavailableEvidence(
            for: attempt,
            message: message,
            requestedScreenshot: requestedScreenshot
        )
        return await persistRuntimeResult(
            run: run,
            attempt: attempt,
            runtimeSummary: nil,
            recoveryHistory: recoveryHistory,
            evidence: evidence,
            attemptSnapshots: [
                Self.makeAttemptSnapshot(
                    attempt: attempt,
                    resolvedContext: run.resolvedContext,
                    diagnosisSummary: run.diagnosisSummary,
                    testDiagnosisSummary: run.testDiagnosisSummary,
                    runtimeSummary: nil,
                    recordedAt: startedAt
                )
            ],
            status: .failed,
            failure: WorkflowFailure(
                field: Self.classifyFailureField(message: message),
                classification: .executionFailed,
                message: message,
                observed: ObservedFailureEvidence(
                    summary: message
                ),
                inferred: InferredFailureConclusion(
                    summary: "Runtime execution failed before xcforge could complete the capture; the simulator or app environment may need attention."
                ),
                recoverability: .retryAfterFix
            )
        )
    }

    private func persistRuntimeResult(
        run: WorkflowRunRecord,
        attempt: WorkflowAttemptRecord,
        runtimeSummary: RuntimeDiagnosisSummary?,
        recoveryHistory: [WorkflowRecoveryRecord],
        evidence: [WorkflowEvidenceRecord],
        attemptSnapshots: [WorkflowAttemptSnapshot],
        status: WorkflowStatus,
        failure: WorkflowFailure?
    ) async -> DiagnosisRuntimeResult {
        let persistedAt = now()
        let updatedRun = WorkflowRunRecord(
            schemaVersion: WorkflowRunRecord.currentSchemaVersion,
            runId: run.runId,
            workflow: run.workflow,
            phase: .diagnosisRuntime,
            status: status,
            createdAt: run.createdAt,
            updatedAt: persistedAt,
            attempt: attempt,
            resolvedContext: run.resolvedContext,
            diagnosisSummary: run.diagnosisSummary,
            testDiagnosisSummary: run.testDiagnosisSummary,
            runtimeSummary: runtimeSummary,
            environmentPreflight: run.environmentPreflight,
            recoveryHistory: recoveryHistory,
            evidence: run.evidence + evidence,
            attemptHistory: run.backfilledAttemptHistory + attemptSnapshots,
            actionHistory: run.actionHistory + [
                WorkflowActionRecord(
                    kind: .runtimeStarted,
                    phase: .diagnosisRuntime,
                    attemptId: attempt.attemptId,
                    timestamp: attempt.startedAt
                ),
                WorkflowActionRecord(
                    kind: .runtimeCompleted,
                    phase: .diagnosisRuntime,
                    attemptId: attempt.attemptId,
                    timestamp: persistedAt,
                    detail: status == .succeeded ? "Runtime diagnosis succeeded" : "Runtime diagnosis failed"
                ),
                WorkflowActionRecord(
                    kind: .evidenceCaptured,
                    phase: .diagnosisRuntime,
                    attemptId: attempt.attemptId,
                    timestamp: persistedAt,
                    detail: "Runtime diagnosis evidence captured"
                )
            ]
        )

        let persistedURL: URL?
        do {
            persistedURL = try persistRun(updatedRun)
        } catch {
            return DiagnosisRuntimeResult(
                status: status,
                runId: updatedRun.runId,
                attemptId: updatedRun.attempt.attemptId,
                resolvedContext: updatedRun.resolvedContext,
                summary: runtimeSummary,
                recoveryHistory: recoveryHistory,
                evidence: evidence,
                failure: WorkflowFailure(
                    field: .workflow,
                    classification: .executionFailed,
                    message: "xcforge could not persist the runtime run state: \(error)",
                    observed: ObservedFailureEvidence(
                        summary: "xcforge could not persist the runtime run state.",
                        detail: "\(error)"
                    ),
                    recoverability: .retryAfterFix
                ),
                persistedRunPath: nil
            )
        }

        return DiagnosisRuntimeResult(
            status: status,
            runId: updatedRun.runId,
            attemptId: updatedRun.attempt.attemptId,
            resolvedContext: updatedRun.resolvedContext,
            summary: runtimeSummary,
            recoveryHistory: recoveryHistory,
            evidence: evidence,
            failure: failure,
            persistedRunPath: persistedURL?.path
        )
    }

    static func runtimeSummary(
        bundleId: String,
        capture: ConsoleTools.RuntimeSignalCapture,
        consoleReference: String?,
        screenshotCapture: ScreenshotTools.WorkflowCaptureResult?
    ) -> RuntimeDiagnosisSummary {
        let launchDetected = hasLaunchSignal(bundleId: bundleId, capture: capture)
        let primarySignal = choosePrimarySignal(from: capture)
        let signalCount = capture.stdout.count + capture.stderr.count
        let observed = ObservedRuntimeEvidence(
            summary: observedSummary(bundleId: bundleId, capture: capture, launchDetected: launchDetected),
            launchedApp: launchDetected,
            appRunning: capture.isRunning,
            relaunchedApp: capture.relaunchedApp,
            primarySignal: primarySignal,
            additionalSignalCount: max(signalCount - (primarySignal == nil ? 0 : 1), 0),
            stdoutLineCount: capture.stdout.count,
            stderrLineCount: capture.stderr.count
        )

        var supportingEvidence: [EvidenceReference] = []
        if let consoleReference {
            supportingEvidence.append(
                EvidenceReference(
                    kind: "console_log",
                    path: consoleReference,
                    source: "simctl.launch_console"
                )
            )
        }
        if let screenshotReference = screenshotCapture?.reference,
            screenshotCapture?.availability == .available
        {
            supportingEvidence.append(
                EvidenceReference(
                    kind: "screenshot",
                    path: screenshotReference,
                    source: screenshotCapture?.source ?? "xcforge.runtime_screenshot"
                )
            )
        }

        return RuntimeDiagnosisSummary(
            observedEvidence: observed,
            inferredConclusion: InferredRuntimeConclusion(
                summary: inferredSummary(bundleId: bundleId, capture: capture, launchDetected: launchDetected)
            ),
            supportingEvidence: supportingEvidence
        )
    }

    static func evidence(
        for _: RuntimeDiagnosisSummary,
        consoleReference: String?,
        screenshotCapture: ScreenshotTools.WorkflowCaptureResult?,
        attempt: WorkflowAttemptRecord,
        requestedScreenshot: Bool
    ) -> [WorkflowEvidenceRecord] {
        var evidence = [
            WorkflowEvidenceRecord(
                kind: .runtimeSummary,
                phase: .diagnosisRuntime,
                attemptId: attempt.attemptId,
                attemptNumber: attempt.attemptNumber,
                availability: .available,
                reference: "run_record.runtimeSummary",
                source: "xcforge.diagnosis_runtime.summary"
            )
        ]

        if let consoleReference {
            evidence.append(
                WorkflowEvidenceRecord(
                    kind: .consoleLog,
                    phase: .diagnosisRuntime,
                    attemptId: attempt.attemptId,
                    attemptNumber: attempt.attemptNumber,
                    availability: .available,
                    reference: consoleReference,
                    source: "simctl.launch_console"
                )
            )
        } else {
            evidence.append(
                WorkflowEvidenceRecord(
                    kind: .consoleLog,
                    phase: .diagnosisRuntime,
                    attemptId: attempt.attemptId,
                    attemptNumber: attempt.attemptNumber,
                    availability: .unavailable,
                    unavailableReason: .notCaptured,
                    reference: nil,
                    source: "simctl.launch_console",
                    detail: "Runtime inspection did not capture any console output for this attempt."
                )
            )
        }

        if requestedScreenshot {
            if let screenshotCapture, screenshotCapture.availability == .available {
                evidence.append(
                    WorkflowEvidenceRecord(
                        kind: .screenshot,
                        phase: .diagnosisRuntime,
                        attemptId: attempt.attemptId,
                        attemptNumber: attempt.attemptNumber,
                        availability: .available,
                        reference: screenshotCapture.reference,
                        source: screenshotCapture.source,
                        detail: nil
                    )
                )
            } else {
                evidence.append(
                    WorkflowEvidenceRecord(
                        kind: .screenshot,
                        phase: .diagnosisRuntime,
                        attemptId: attempt.attemptId,
                        attemptNumber: attempt.attemptNumber,
                        availability: .unavailable,
                        unavailableReason: screenshotCapture?.unavailableReason ?? .notCaptured,
                        reference: nil,
                        source: screenshotCapture?.source ?? "xcforge.runtime_screenshot",
                        detail: screenshotCapture?.detail ?? "Runtime inspection did not capture a screenshot for this attempt."
                    )
                )
            }
        }

        return evidence
    }

    static func unavailableEvidence(
        for attempt: WorkflowAttemptRecord,
        message: String,
        requestedScreenshot: Bool
    ) -> [WorkflowEvidenceRecord] {
        var evidence = [
            WorkflowEvidenceRecord(
                kind: .runtimeSummary,
                phase: .diagnosisRuntime,
                attemptId: attempt.attemptId,
                attemptNumber: attempt.attemptNumber,
                availability: .unavailable,
                unavailableReason: .executionFailed,
                reference: nil,
                source: "xcforge.diagnosis_runtime.summary",
                detail: "Runtime execution failed before xcforge could persist a runtime summary."
            ),
            WorkflowEvidenceRecord(
                kind: .consoleLog,
                phase: .diagnosisRuntime,
                attemptId: attempt.attemptId,
                attemptNumber: attempt.attemptNumber,
                availability: .unavailable,
                unavailableReason: .executionFailed,
                reference: nil,
                source: "simctl.launch_console",
                detail: message
            )
        ]
        if requestedScreenshot {
            evidence.append(
                WorkflowEvidenceRecord(
                    kind: .screenshot,
                    phase: .diagnosisRuntime,
                    attemptId: attempt.attemptId,
                    attemptNumber: attempt.attemptNumber,
                    availability: .unavailable,
                    unavailableReason: .executionFailed,
                    reference: nil,
                    source: "xcforge.runtime_screenshot",
                    detail: "Requested screenshot capture could not run because runtime execution failed before the visual-capture step completed."
                )
            )
        }
        return evidence
    }

    private static func classifyOutcome(
        bundleId: String,
        capture: ConsoleTools.RuntimeSignalCapture,
        screenshotCapture: ScreenshotTools.WorkflowCaptureResult?,
        requestedScreenshot: Bool
    ) -> (status: WorkflowStatus, failure: WorkflowFailure?) {
        let launchDetected = hasLaunchSignal(bundleId: bundleId, capture: capture)
        let screenshotUnavailable = requestedScreenshot
            && screenshotCapture?.availability == .unavailable
        let runtimeSignalsCaptured = capture.stdout.contains(where: hasContent)
            || capture.stderr.contains(where: hasContent)
        let screenshotFailure = screenshotFailure(
            capture: screenshotCapture,
            requestedScreenshot: requestedScreenshot
        )
        if launchDetected && capture.isRunning {
            if screenshotUnavailable {
                return (.partial, screenshotFailure)
            }
            return (.succeeded, nil)
        }

        if launchDetected {
            if screenshotUnavailable {
                return (.partial, screenshotFailure ?? WorkflowFailure(
                    field: .runtime,
                    classification: .executionFailed,
                    message: "The app launched for runtime inspection but did not remain running for the full capture window.",
                    observed: ObservedFailureEvidence(
                        summary: "The app launched for runtime inspection but did not remain running for the full capture window."
                    ),
                    inferred: InferredFailureConclusion(
                        summary: "The app may have crashed or been terminated shortly after launch; console output may contain crash signals."
                    ),
                    recoverability: .retryAfterFix
                ))
            }
            return (
                .partial,
                WorkflowFailure(
                    field: .runtime,
                    classification: .executionFailed,
                    message: "The app launched for runtime inspection but did not remain running for the full capture window.",
                    observed: ObservedFailureEvidence(
                        summary: "The app launched for runtime inspection but did not remain running for the full capture window."
                    ),
                    inferred: InferredFailureConclusion(
                        summary: "The app may have crashed or been terminated shortly after launch; console output may contain crash signals."
                    ),
                    recoverability: .retryAfterFix
                )
            )
        }

        if let screenshotFailure,
            screenshotFailure.classification == .unsupportedContext
        {
            return (
                runtimeSignalsCaptured ? .partial : .unsupported,
                screenshotFailure
            )
        }

        let failureMessage = chooseFailureMessage(from: capture)
        return (
            .failed,
            WorkflowFailure(
                field: classifyFailureField(message: failureMessage),
                classification: .executionFailed,
                message: failureMessage,
                observed: ObservedFailureEvidence(
                    summary: failureMessage
                ),
                inferred: InferredFailureConclusion(
                    summary: "No reliable launch success signal was captured; the app may have failed to install, launch, or the simulator environment may be misconfigured."
                ),
                recoverability: .retryAfterFix
            )
        )
    }

    private static func screenshotFailure(
        capture: ScreenshotTools.WorkflowCaptureResult?,
        requestedScreenshot: Bool
    ) -> WorkflowFailure? {
        guard requestedScreenshot,
            let capture,
            capture.availability == .unavailable
        else {
            return nil
        }

        let classification: WorkflowFailureClassification =
            capture.unavailableReason == .unsupported ? .unsupportedContext : .executionFailed
        return WorkflowFailure(
            field: classifyFailureField(message: capture.detail ?? capture.source),
            classification: classification,
            message: capture.detail ?? "Requested screenshot capture was unavailable for this runtime attempt.",
            observed: ObservedFailureEvidence(
                summary: capture.detail ?? "Requested screenshot capture was unavailable for this runtime attempt.",
                detail: capture.source
            ),
            recoverability: classification.recoverability
        )
    }

    private static func hasContent(_ line: String) -> Bool {
        !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func containsAny(_ value: String, markers: [String]) -> Bool {
        markers.contains { value.contains($0) }
    }

    private static func isSupportedLaunchContinuityBreak(
        capture: ConsoleTools.RuntimeSignalCapture,
        signalText: String
    ) -> Bool {
        capture.relaunchedApp
            || containsAny(
                signalText,
                markers: [
                    "launchctl print stalled",
                    "launch continuity"
                ]
            )
    }

    private static func choosePrimarySignal(from capture: ConsoleTools.RuntimeSignalCapture) -> RuntimeSignalSummary? {
        if let stderr = capture.stderr.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return RuntimeSignalSummary(stream: .stderr, message: stderr, source: "simctl.launch_console.stderr")
        }
        if let stdout = capture.stdout.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return RuntimeSignalSummary(stream: .stdout, message: stdout, source: "simctl.launch_console.stdout")
        }
        return nil
    }

    private static func hasLaunchSignal(
        bundleId: String,
        capture: ConsoleTools.RuntimeSignalCapture
    ) -> Bool {
        let matchesLaunchSignal: (String) -> Bool = { line in
            let lowered = line.lowercased()
            return line.contains("\(bundleId):")
                || (line.contains(bundleId) && (lowered.contains("launch") || lowered.contains("launched")))
        }

        return capture.stdout.contains(where: matchesLaunchSignal)
            || capture.stderr.contains(where: matchesLaunchSignal)
    }

    private static func didResumeRuntime(
        bundleId: String,
        capture: ConsoleTools.RuntimeSignalCapture
    ) -> Bool {
        hasLaunchSignal(bundleId: bundleId, capture: capture) && capture.isRunning
    }

    private static func observedSummary(
        bundleId: String,
        capture: ConsoleTools.RuntimeSignalCapture,
        launchDetected: Bool
    ) -> String {
        if launchDetected && capture.isRunning {
            return capture.relaunchedApp
                ? "App \(bundleId) was relaunched and runtime signals were captured."
                : "App \(bundleId) launched and runtime signals were captured."
        }
        if launchDetected {
            return "App \(bundleId) launched, but runtime inspection ended before the app stayed running."
        }
        return "App \(bundleId) did not reach a confirmed running state during runtime inspection."
    }

    private static func inferredSummary(
        bundleId: String,
        capture: ConsoleTools.RuntimeSignalCapture,
        launchDetected: Bool
    ) -> String {
        if launchDetected && capture.isRunning {
            return "Runtime inspection reached a running app state with captured console output or a confirmed live console session."
        }
        if launchDetected {
            return "The app reached launch, but the runtime state remained unstable or exited before the capture window completed."
        }
        return "No reliable launch success signal was captured for \(bundleId); inspect the runtime evidence for environment or app-level blockers."
    }

    private static func chooseFailureMessage(from capture: ConsoleTools.RuntimeSignalCapture) -> String {
        if let stderr = capture.stderr.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return stderr
        }
        if let stdout = capture.stdout.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return stdout
        }
        return "Runtime launch failed before xcforge captured a supported runtime signal."
    }

    private static func classifyFailureField(message: String) -> ContextField {
        let lowered = message.lowercased()
        if lowered.contains("simulator") || lowered.contains("simctl") || lowered.contains("device") {
            return .simulator
        }
        if lowered.contains("bundle")
            || lowered.contains("code sign")
            || lowered.contains("codesign")
            || lowered.contains("application identifier")
            || lowered.contains("launchctl")
            || lowered.contains(".app")
        {
            return .app
        }
        return .runtime
    }
}

private struct RuntimeRecoveryPlan {
    let issue: WorkflowRecoveryIssue
    let detectedIssue: String
    let summary: String
    let detail: String?
}

private struct DiagnosisRuntimeWorkflowError: Error {
    let status: WorkflowStatus
    let field: ContextField
    let classification: WorkflowFailureClassification
    let message: String
    let options: [String]
}

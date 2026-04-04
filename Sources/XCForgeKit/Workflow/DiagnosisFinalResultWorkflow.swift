import Foundation

public struct DiagnosisFinalResultWorkflow: Sendable {
    typealias LoadRun = @Sendable (String) throws -> WorkflowRunRecord
    typealias LoadLatestActiveRun = @Sendable () throws -> WorkflowRunRecord?
    typealias LoadLatestTerminalRun = @Sendable () throws -> WorkflowRunRecord?
    typealias LoadLatestRun = @Sendable () throws -> WorkflowRunRecord?
    typealias RunPath = @Sendable (String) -> URL

    private let loadRun: LoadRun
    private let loadLatestActiveRun: LoadLatestActiveRun
    private let loadLatestTerminalRun: LoadLatestTerminalRun
    private let loadLatestRun: LoadLatestRun
    private let runPath: RunPath

    public init() {
        self.init(
            loadRun: { runId in
                let store = RunStore()
                let fileURL = store.runFileURL(runId: runId)
                guard FileManager.default.fileExists(atPath: fileURL.path) else {
                    throw DiagnosisFinalResultWorkflowError(
                        field: .run,
                        classification: .notFound,
                        message: "No diagnosis run was found for run ID \(runId)."
                    )
                }
                return try store.load(runId: runId)
            },
            loadLatestActiveRun: { try RunStore().latestActiveDiagnosisRun() },
            loadLatestTerminalRun: { try RunStore().latestTerminalDiagnosisRun() },
            loadLatestRun: { try RunStore().latestDiagnosisRun() },
            runPath: { runId in RunStore().runFileURL(runId: runId) }
        )
    }

    init(
        loadRun: @escaping LoadRun,
        loadLatestActiveRun: @escaping LoadLatestActiveRun,
        loadLatestTerminalRun: @escaping LoadLatestTerminalRun,
        loadLatestRun: @escaping LoadLatestRun,
        runPath: @escaping RunPath
    ) {
        self.loadRun = loadRun
        self.loadLatestActiveRun = loadLatestActiveRun
        self.loadLatestTerminalRun = loadLatestTerminalRun
        self.loadLatestRun = loadLatestRun
        self.runPath = runPath
    }

    public func assemble(request: DiagnosisFinalResultRequest) async -> DiagnosisFinalResult {
        do {
            let run = try resolveRun(for: request)
            try Self.validate(run)

            let currentSnapshot = run.attemptSnapshot(forAttemptId: run.attempt.attemptId, phase: run.phase) ?? run.latestSnapshot
            let currentAttempt = makeSnapshot(
                from: currentSnapshot,
                evidence: run.evidence(forAttemptId: currentSnapshot.attempt.attemptId)
            )

            let comparisonContext = comparisonContext(from: currentSnapshot)
            let sourceAttemptId = comparisonContext.sourceAttemptId

            guard let sourceAttemptId else {
                let result = DiagnosisFinalResult(
                    phase: run.phase,
                    status: run.status,
                    runId: run.runId,
                    attemptId: currentAttempt.attemptId,
                    sourceAttemptId: nil,
                    summary: currentAttempt.summary,
                    recoveryHistory: run.recoveryHistory,
                    currentAttempt: currentAttempt,
                    sourceAttempt: nil,
                    comparison: nil,
                    comparisonNote: comparisonContext.note,
                    followOnAction: nil,
                    failure: nil,
                    persistedRunPath: runPath(run.runId).path
                )
                return result.withDerivedFollowOnAction()
            }

            let compareWorkflow = DiagnosisCompareWorkflow(
                loadRun: loadRun,
                loadLatestActiveRun: loadLatestActiveRun,
                loadLatestRun: loadLatestRun,
                runPath: runPath
            )
            let compareResult = await compareWorkflow.compare(request: DiagnosisCompareRequest(runId: run.runId))

            if compareResult.isSuccessfulComparison,
               let comparisonOutcome = compareResult.outcome,
               let priorAttempt = compareResult.priorAttempt,
               let currentAttempt = compareResult.currentAttempt {
                let result = DiagnosisFinalResult(
                    phase: compareResult.phase,
                    status: compareResult.status,
                    runId: compareResult.runId,
                    attemptId: compareResult.attemptId,
                    sourceAttemptId: compareResult.sourceAttemptId,
                    summary: currentAttempt.summary,
                    recoveryHistory: run.recoveryHistory,
                    currentAttempt: currentAttempt,
                    sourceAttempt: priorAttempt,
                    comparison: DiagnosisFinalComparison(
                        outcome: comparisonOutcome,
                        changedEvidence: compareResult.changedEvidence,
                        unchangedBlockers: compareResult.unchangedBlockers
                    ),
                    comparisonNote: nil,
                    followOnAction: nil,
                    failure: nil,
                    persistedRunPath: compareResult.persistedRunPath
                )
                return result.withDerivedFollowOnAction()
            }

            let fallbackResult = DiagnosisFinalResult(
                phase: run.phase,
                status: run.status,
                runId: run.runId,
                attemptId: currentAttempt.attemptId,
                sourceAttemptId: sourceAttemptId,
                summary: currentAttempt.summary,
                recoveryHistory: run.recoveryHistory,
                currentAttempt: currentAttempt,
                sourceAttempt: nil,
                comparison: nil,
                comparisonNote: compareResult.failure?.message
                    ?? "Comparison is unavailable for the linked rerun attempt.",
                followOnAction: nil,
                failure: nil,
                persistedRunPath: runPath(run.runId).path
            )
            return fallbackResult.withDerivedFollowOnAction()
        } catch let error as DiagnosisFinalResultWorkflowError {
            let failure = WorkflowFailure(
                field: error.field,
                classification: error.classification,
                message: error.message,
                options: error.options,
                observed: ObservedFailureEvidence(summary: error.message),
                inferred: nil,
                recoverability: error.classification.recoverability
            )
            return DiagnosisFinalResult(
                phase: nil,
                status: nil,
                runId: request.runId,
                attemptId: nil,
                sourceAttemptId: nil,
                summary: nil,
                recoveryHistory: [],
                currentAttempt: nil,
                sourceAttempt: nil,
                comparison: nil,
                comparisonNote: nil,
                followOnAction: WorkflowFollowOnAction(
                    action: "Review the failure details and address the root cause before retrying.",
                    rationale: sanitizeRationale("Workflow failed at \(failure.field.rawValue): \(failure.message)"),
                    confidence: .evidenceSupported
                ),
                failure: failure,
                persistedRunPath: nil
            )
        } catch {
            let failure = WorkflowFailure(
                field: .workflow,
                classification: .executionFailed,
                message: "\(error)",
                observed: ObservedFailureEvidence(summary: "\(error)"),
                inferred: InferredFailureConclusion(summary: "An unexpected error occurred while assembling final results; the underlying issue may be transient or environmental."),
                recoverability: .retryAfterFix
            )
            return DiagnosisFinalResult(
                phase: nil,
                status: nil,
                runId: request.runId,
                attemptId: nil,
                sourceAttemptId: nil,
                summary: nil,
                recoveryHistory: [],
                currentAttempt: nil,
                sourceAttempt: nil,
                comparison: nil,
                comparisonNote: nil,
                followOnAction: WorkflowFollowOnAction(
                    action: "Review the failure details and address the root cause before retrying.",
                    rationale: sanitizeRationale("Workflow failed at \(failure.field.rawValue): \(failure.message)"),
                    confidence: .evidenceSupported
                ),
                failure: failure,
                persistedRunPath: nil
            )
        }
    }

    private func resolveRun(for request: DiagnosisFinalResultRequest) throws -> WorkflowRunRecord {
        if let runId = request.runId {
            let trimmedRunId = runId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedRunId.isEmpty else {
                throw DiagnosisFinalResultWorkflowError(
                    field: .run,
                    classification: .notFound,
                    message: "Run ID must not be empty."
                )
            }
            do {
                return try loadRun(trimmedRunId)
            } catch let error as DiagnosisFinalResultWorkflowError {
                throw error
            } catch let error as CocoaError
                where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
                throw DiagnosisFinalResultWorkflowError(
                    field: .run,
                    classification: .notFound,
                    message: "No diagnosis run was found for run ID \(trimmedRunId)."
                )
            } catch {
                throw DiagnosisFinalResultWorkflowError(
                    field: .run,
                    classification: .executionFailed,
                    message: "\(error)"
                )
            }
        }

        if let run = try loadLatestTerminalRun() {
            return run
        }

        let activeRun = try loadLatestActiveRun()
        let latestRun = try loadLatestRun()

        if let run = activeRun ?? latestRun {
            throw DiagnosisFinalResultWorkflowError(
                field: .run,
                classification: .invalidRunState,
                message: "Run \(run.runId) is still in progress; final results require a completed diagnosis."
            )
        }

        throw DiagnosisFinalResultWorkflowError(
            field: .run,
            classification: .notFound,
            message: "No terminal diagnosis runs are available to inspect."
        )
    }

    private static func validate(_ run: WorkflowRunRecord) throws {
        guard run.workflow == .diagnosis else {
            throw DiagnosisFinalResultWorkflowError(
                field: .run,
                classification: .invalidRunState,
                message: "Run \(run.runId) is not a diagnosis workflow run."
            )
        }

        guard run.phase == .diagnosisBuild || run.phase == .diagnosisTest || run.phase == .diagnosisRuntime else {
            throw DiagnosisFinalResultWorkflowError(
                field: .run,
                classification: .invalidRunState,
                message: "Run \(run.runId) is in phase \(run.phase.rawValue); final results require a completed build, test, or runtime diagnosis."
            )
        }

        guard run.status != .inProgress else {
            throw DiagnosisFinalResultWorkflowError(
                field: .run,
                classification: .invalidRunState,
                message: "Run \(run.runId) is still in progress; final results require a completed diagnosis."
            )
        }
    }

    private func makeSnapshot(
        from snapshot: WorkflowAttemptSnapshot,
        evidence: [WorkflowEvidenceRecord]
    ) -> DiagnosisCompareAttemptSnapshot {
        DiagnosisCompareAttemptSnapshot(
            attemptId: snapshot.attempt.attemptId,
            attemptNumber: snapshot.attempt.attemptNumber,
            phase: snapshot.phase,
            status: snapshot.status,
            resolvedContext: snapshot.resolvedContext,
            summary: Self.summary(for: snapshot),
            diagnosisSummary: snapshot.diagnosisSummary,
            testDiagnosisSummary: snapshot.testDiagnosisSummary,
            runtimeSummary: snapshot.runtimeSummary,
            evidence: evidence,
            recordedAt: snapshot.recordedAt
        )
    }

    private static func summary(for snapshot: WorkflowAttemptSnapshot) -> DiagnosisStatusSummary {
        switch snapshot.phase {
        case .diagnosisStart:
            return DiagnosisStatusSummary(
                source: .start,
                headline: "Diagnosis run is in phase \(snapshot.phase.rawValue) with status \(snapshot.status.rawValue).",
                detail: "No build or test diagnosis summary is available for this attempt."
            )
        case .diagnosisBuild:
            if let summary = snapshot.diagnosisSummary {
                return DiagnosisStatusSummary(
                    source: .build,
                    headline: summary.observedEvidence.summary,
                    detail: summary.observedEvidence.primarySignal?.message
                        ?? summary.inferredConclusion?.summary
                )
            }
            return DiagnosisStatusSummary(
                source: .build,
                headline: "Diagnosis run is in phase \(snapshot.phase.rawValue) with status \(snapshot.status.rawValue).",
                detail: "No persisted build diagnosis summary is available for this attempt."
            )
        case .diagnosisTest:
            if let summary = snapshot.testDiagnosisSummary {
                return DiagnosisStatusSummary(
                    source: .test,
                    headline: summary.observedEvidence.summary,
                    detail: summary.observedEvidence.primaryFailure?.testIdentifier
                        ?? summary.inferredConclusion?.summary
                )
            }
            return DiagnosisStatusSummary(
                source: .test,
                headline: "Diagnosis run is in phase \(snapshot.phase.rawValue) with status \(snapshot.status.rawValue).",
                detail: "No persisted test diagnosis summary is available for this attempt."
            )
        case .diagnosisRuntime:
            if let summary = snapshot.runtimeSummary {
                return DiagnosisStatusSummary(
                    source: .runtime,
                    headline: summary.observedEvidence.summary,
                    detail: summary.observedEvidence.primarySignal?.message
                        ?? summary.inferredConclusion?.summary
                )
            }
            return DiagnosisStatusSummary(
                source: .runtime,
                headline: "Diagnosis run is in phase \(snapshot.phase.rawValue) with status \(snapshot.status.rawValue).",
                detail: "No persisted runtime diagnosis summary is available for this attempt."
            )
        }
    }

    private func comparisonContext(from snapshot: WorkflowAttemptSnapshot) -> (sourceAttemptId: String?, note: String?) {
        guard let rawSourceAttemptId = snapshot.attempt.rerunOfAttemptId else {
            return (nil, nil)
        }

        let sourceAttemptId = rawSourceAttemptId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sourceAttemptId.isEmpty else {
            return (
                nil,
                "Comparison is unavailable because the rerun lineage was recorded with an empty source attempt ID."
            )
        }

        return (sourceAttemptId, nil)
    }

    private func sanitizeRationale(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension DiagnosisFinalResult {
    func withDerivedFollowOnAction() -> DiagnosisFinalResult {
        guard followOnAction == nil else { return self }
        let derived = Self.deriveFollowOnAction(for: self)
        guard let derived else { return self }
        var result = self
        result.followOnAction = derived
        return result
    }

    private static func deriveFollowOnAction(for result: DiagnosisFinalResult) -> WorkflowFollowOnAction? {
        if let failure = result.failure {
            return WorkflowFollowOnAction(
                action: "Review the failure details and address the root cause before retrying.",
                rationale: sanitize("Workflow failed at \(failure.field.rawValue): \(failure.message)"),
                confidence: .evidenceSupported
            )
        }

        let isBlocked = result.recoveryHistory.last?.resumed == false

        if isBlocked {
            let count = result.recoveryHistory.count
            return WorkflowFollowOnAction(
                action: "Resolve the environment issue before retrying the diagnosis.",
                rationale: "Recovery did not resume after \(count == 1 ? "1 recovery action" : "\(count) recovery actions").",
                confidence: .evidenceSupported
            )
        }

        switch result.status {
        case .failed:
            return deriveForFailed(result)
        case .succeeded:
            return deriveForSucceeded(result)
        case .partial:
            return deriveForPartial(result)
        case .unsupported:
            return WorkflowFollowOnAction(
                action: "Review run context to determine an alternative workflow path.",
                rationale: "The current workflow path is unsupported for this configuration.",
                confidence: .inferred
            )
        case .canceled, .inProgress, nil:
            return nil
        }
    }

    private static func deriveForFailed(_ result: DiagnosisFinalResult) -> WorkflowFollowOnAction {
        if let attempt = result.currentAttempt {
            if let buildSummary = attempt.diagnosisSummary {
                let detail = buildSummary.observedEvidence.primarySignal.map {
                    " Primary signal: \($0.message)"
                } ?? ""
                return WorkflowFollowOnAction(
                    action: "Review the build error and apply a fix, then rerun validation.",
                    rationale: "Build diagnosis identified \(buildSummary.observedEvidence.errorCount) error(s).\(detail)",
                    confidence: .evidenceSupported
                )
            }
            if let testSummary = attempt.testDiagnosisSummary {
                let detail = testSummary.observedEvidence.primaryFailure.map {
                    " Primary failure: \($0.testIdentifier)"
                } ?? ""
                return WorkflowFollowOnAction(
                    action: "Review the failing tests and apply a fix, then rerun validation.",
                    rationale: "\(testSummary.observedEvidence.failedTestCount) of \(testSummary.observedEvidence.totalTestCount) tests failed.\(detail)",
                    confidence: .evidenceSupported
                )
            }
            if let runtimeSummary = attempt.runtimeSummary {
                let detail = runtimeSummary.observedEvidence.primarySignal.map {
                    " Primary signal: \($0.message)"
                } ?? ""
                return WorkflowFollowOnAction(
                    action: "Review the runtime failure and captured evidence, then rerun validation.",
                    rationale: "Runtime diagnosis failed — app \(runtimeSummary.observedEvidence.appRunning ? "was running" : "did not stay running").\(detail)",
                    confidence: .evidenceSupported
                )
            }
        }

        return WorkflowFollowOnAction(
            action: "Review the diagnosis detail and evidence to identify the root cause.",
            rationale: sanitize("\(phaseLabel(result.phase)) ended with a failed status."),
            confidence: .inferred
        )
    }

    private static func deriveForSucceeded(_ result: DiagnosisFinalResult) -> WorkflowFollowOnAction {
        if !result.recoveryHistory.isEmpty {
            let count = result.recoveryHistory.count
            let label = count == 1 ? "1 recovery action" : "\(count) recovery actions"

            if let comparison = result.comparison, comparison.outcome == .improved {
                return WorkflowFollowOnAction(
                    action: "Verify the fix holds across related targets.",
                    rationale: "Succeeded after \(label) with improved comparison outcome.",
                    confidence: .evidenceSupported
                )
            }

            return WorkflowFollowOnAction(
                action: "Verify the fix holds across related targets.",
                rationale: "Succeeded after \(label). No remaining blockers detected.",
                confidence: .evidenceSupported
            )
        }

        if result.comparison != nil {
            return WorkflowFollowOnAction(
                action: "Review the comparison to confirm the change had the expected effect.",
                rationale: "Rerun completed successfully with a prior attempt linked for comparison.",
                confidence: .evidenceSupported
            )
        }

        return WorkflowFollowOnAction(
            action: "Review evidence to confirm the result meets expectations.",
            rationale: sanitize("\(phaseLabel(result.phase)) completed successfully."),
            confidence: .inferred
        )
    }

    private static func deriveForPartial(_ result: DiagnosisFinalResult) -> WorkflowFollowOnAction {
        if let attempt = result.currentAttempt, !attempt.unavailableEvidence.isEmpty {
            return WorkflowFollowOnAction(
                action: "Review missing evidence to determine what workflow step would produce it.",
                rationale: "\(attempt.unavailableEvidence.count) expected evidence artifact(s) are unavailable.",
                confidence: .evidenceSupported
            )
        }

        return WorkflowFollowOnAction(
            action: "Review the available evidence and run context for partial findings.",
            rationale: sanitize("\(phaseLabel(result.phase)) ended with a partial result."),
            confidence: .inferred
        )
    }

    private static func phaseLabel(_ phase: WorkflowPhase?) -> String {
        guard let phase else { return "diagnosis" }
        switch phase {
        case .diagnosisStart: return "diagnosis setup"
        case .diagnosisBuild: return "build diagnosis"
        case .diagnosisTest: return "test diagnosis"
        case .diagnosisRuntime: return "runtime diagnosis"
        }
    }

    private static func sanitize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct DiagnosisFinalResultWorkflowError: Error {
    let field: ContextField
    let classification: WorkflowFailureClassification
    let message: String
    let options: [String]

    init(
        field: ContextField,
        classification: WorkflowFailureClassification,
        message: String,
        options: [String] = []
    ) {
        self.field = field
        self.classification = classification
        self.message = message
        self.options = options
    }
}

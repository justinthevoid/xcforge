import Foundation

public struct DiagnosisStatusWorkflow: Sendable {
    typealias LoadRun = @Sendable (String) throws -> WorkflowRunRecord
    typealias LoadLatestActiveRun = @Sendable () throws -> WorkflowRunRecord?
    typealias LoadLatestRun = @Sendable () throws -> WorkflowRunRecord?
    typealias RunPath = @Sendable (String) -> URL

    private let loadRun: LoadRun
    private let loadLatestActiveRun: LoadLatestActiveRun
    private let loadLatestRun: LoadLatestRun
    private let runPath: RunPath

    public init() {
        self.init(
            loadRun: { runId in
                let store = RunStore()
                let fileURL = store.runFileURL(runId: runId)
                guard FileManager.default.fileExists(atPath: fileURL.path) else {
                    throw DiagnosisStatusWorkflowError(
                        field: .run,
                        classification: .notFound,
                        message: "No diagnosis run was found for run ID \(runId)."
                    )
                }
                return try store.load(runId: runId)
            },
            loadLatestActiveRun: { try RunStore().latestActiveDiagnosisRun() },
            loadLatestRun: { try RunStore().latestDiagnosisRun() },
            runPath: { runId in RunStore().runFileURL(runId: runId) }
        )
    }

    init(
        loadRun: @escaping LoadRun,
        loadLatestActiveRun: @escaping LoadLatestActiveRun,
        loadLatestRun: @escaping LoadLatestRun,
        runPath: @escaping RunPath
    ) {
        self.loadRun = loadRun
        self.loadLatestActiveRun = loadLatestActiveRun
        self.loadLatestRun = loadLatestRun
        self.runPath = runPath
    }

    public func inspect(request: DiagnosisStatusRequest) async -> DiagnosisStatusResult {
        do {
            let run = try resolveRun(for: request)
            try Self.validate(run)

            return DiagnosisStatusResult(
                schemaVersion: run.schemaVersion,
                phase: run.phase,
                status: run.status,
                runId: run.runId,
                attemptId: run.attempt.attemptId,
                resolvedContext: run.resolvedContext,
                summary: Self.summary(for: run),
                recoveryHistory: run.recoveryHistory,
                actionHistory: run.actionHistory,
                failure: nil,
                persistedRunPath: runPath(run.runId).path
            )
        } catch let error as DiagnosisStatusWorkflowError {
            return DiagnosisStatusResult(
                phase: nil,
                status: nil,
                runId: request.runId,
                attemptId: nil,
                resolvedContext: nil,
                summary: nil,
                recoveryHistory: [],
                failure: WorkflowFailure(
                    field: error.field,
                    classification: error.classification,
                    message: error.message,
                    options: error.options,
                    observed: ObservedFailureEvidence(summary: error.message),
                    inferred: nil,
                    recoverability: error.classification.recoverability
                ),
                persistedRunPath: nil
            )
        } catch {
            return DiagnosisStatusResult(
                phase: nil,
                status: nil,
                runId: request.runId,
                attemptId: nil,
                resolvedContext: nil,
                summary: nil,
                recoveryHistory: [],
                failure: WorkflowFailure(
                    field: .workflow,
                    classification: .executionFailed,
                    message: "\(error)",
                    observed: ObservedFailureEvidence(summary: "\(error)"),
                    inferred: InferredFailureConclusion(summary: "An unexpected error occurred during status inspection; the underlying issue may be transient or environmental."),
                    recoverability: .retryAfterFix
                ),
                persistedRunPath: nil
            )
        }
    }

    public func inspectEvidence(request: DiagnosisStatusRequest) async -> DiagnosisEvidenceResult {
        var resolvedRun: WorkflowRunRecord?

        do {
            let run = try resolveRun(for: request)
            resolvedRun = run
            try Self.validate(run)

            return DiagnosisEvidenceResult(
                schemaVersion: run.schemaVersion,
                phase: run.phase,
                status: run.status,
                evidenceState: Self.evidenceState(for: run),
                runId: run.runId,
                attemptId: run.attempt.attemptId,
                resolvedContext: run.resolvedContext,
                buildSummary: run.diagnosisSummary,
                testSummary: run.testDiagnosisSummary,
                runtimeSummary: run.runtimeSummary,
                recoveryHistory: run.recoveryHistory,
                evidence: run.evidence,
                failure: nil,
                persistedRunPath: runPath(run.runId).path
            )
        } catch let error as DiagnosisStatusWorkflowError {
            let run = resolvedRun
            return DiagnosisEvidenceResult(
                phase: run?.phase,
                status: run?.status,
                evidenceState: nil,
                runId: run?.runId ?? request.runId,
                attemptId: run?.attempt.attemptId,
                resolvedContext: run?.resolvedContext,
                buildSummary: run?.diagnosisSummary,
                testSummary: run?.testDiagnosisSummary,
                runtimeSummary: run?.runtimeSummary,
                recoveryHistory: run?.recoveryHistory ?? [],
                evidence: run?.evidence ?? [],
                failure: WorkflowFailure(
                    field: error.field,
                    classification: error.classification,
                    message: error.message,
                    options: error.options,
                    observed: ObservedFailureEvidence(summary: error.message),
                    inferred: nil,
                    recoverability: error.classification.recoverability
                ),
                persistedRunPath: run.map { runPath($0.runId).path }
            )
        } catch {
            let run = resolvedRun
            return DiagnosisEvidenceResult(
                phase: run?.phase,
                status: run?.status,
                evidenceState: nil,
                runId: run?.runId ?? request.runId,
                attemptId: run?.attempt.attemptId,
                resolvedContext: run?.resolvedContext,
                buildSummary: run?.diagnosisSummary,
                testSummary: run?.testDiagnosisSummary,
                runtimeSummary: run?.runtimeSummary,
                recoveryHistory: run?.recoveryHistory ?? [],
                evidence: run?.evidence ?? [],
                failure: WorkflowFailure(
                    field: .workflow,
                    classification: .executionFailed,
                    message: "\(error)",
                    observed: ObservedFailureEvidence(summary: "\(error)"),
                    inferred: InferredFailureConclusion(summary: "An unexpected error occurred during evidence inspection; the underlying issue may be transient or environmental."),
                    recoverability: .retryAfterFix
                ),
                persistedRunPath: run.map { runPath($0.runId).path }
            )
        }
    }

    private func resolveRun(for request: DiagnosisStatusRequest) throws -> WorkflowRunRecord {
        if let runId = request.runId {
            let trimmedRunId = runId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedRunId.isEmpty else {
                throw DiagnosisStatusWorkflowError(
                    field: .run,
                    classification: .notFound,
                    message: "Run ID must not be empty."
                )
            }
            do {
                return try loadRun(trimmedRunId)
            } catch let error as DiagnosisStatusWorkflowError {
                throw error
            } catch let error as CocoaError
                where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
                throw DiagnosisStatusWorkflowError(
                    field: .run,
                    classification: .notFound,
                    message: "No diagnosis run was found for run ID \(trimmedRunId)."
                )
            } catch {
                throw DiagnosisStatusWorkflowError(
                    field: .run,
                    classification: .executionFailed,
                    message: "\(error)"
                )
            }
        }

        if let run = try loadLatestActiveRun() {
            return run
        }
        if let run = try loadLatestRun() {
            return run
        }

        throw DiagnosisStatusWorkflowError(
            field: .run,
            classification: .notFound,
            message: "No diagnosis runs are available to inspect."
        )
    }

    private static func validate(_ run: WorkflowRunRecord) throws {
        guard run.workflow == .diagnosis else {
            throw DiagnosisStatusWorkflowError(
                field: .run,
                classification: .invalidRunState,
                message: "Run \(run.runId) is not a diagnosis workflow run."
            )
        }
    }

    static func summary(for run: WorkflowRunRecord) -> DiagnosisStatusSummary {
        switch run.phase {
        case .diagnosisStart:
            return DiagnosisStatusSummary(
                source: .start,
                headline: "Diagnosis run is in phase \(run.phase.rawValue) with status \(run.status.rawValue).",
                detail: "No build or test diagnosis summary has been recorded yet."
            )
        case .diagnosisBuild:
            if let summary = run.diagnosisSummary {
                return DiagnosisStatusSummary(
                    source: .build,
                    headline: summary.observedEvidence.summary,
                    detail: summary.observedEvidence.primarySignal?.message
                        ?? summary.inferredConclusion?.summary
                )
            }
            return DiagnosisStatusSummary(
                source: .build,
                headline: "Diagnosis run is in phase \(run.phase.rawValue) with status \(run.status.rawValue).",
                detail: "No persisted build diagnosis summary is available for this run."
            )
        case .diagnosisTest:
            if let summary = run.testDiagnosisSummary {
                return DiagnosisStatusSummary(
                    source: .test,
                    headline: summary.observedEvidence.summary,
                    detail: summary.observedEvidence.primaryFailure?.testIdentifier
                        ?? summary.inferredConclusion?.summary
                )
            }
            return DiagnosisStatusSummary(
                source: .test,
                headline: "Diagnosis run is in phase \(run.phase.rawValue) with status \(run.status.rawValue).",
                detail: "No persisted test diagnosis summary is available for this run."
            )
        case .diagnosisRuntime:
            if let summary = run.runtimeSummary {
                let recoveryDetail = run.latestRecoveryRecord.map(Self.recoveryNarrativeDetail)
                return DiagnosisStatusSummary(
                    source: .runtime,
                    headline: summary.observedEvidence.summary,
                    detail: summary.observedEvidence.primarySignal?.message
                        ?? summary.inferredConclusion?.summary
                        ?? recoveryDetail
                )
            }
            return DiagnosisStatusSummary(
                source: .runtime,
                headline: "Diagnosis run is in phase \(run.phase.rawValue) with status \(run.status.rawValue).",
                detail: run.latestRecoveryRecord.map(Self.recoveryNarrativeDetail)
                    ?? "No persisted runtime diagnosis summary is available for this run."
            )
        }
    }

    static func evidenceState(for run: WorkflowRunRecord) -> DiagnosisEvidenceState {
        guard run.diagnosisSummary != nil || run.testDiagnosisSummary != nil || !run.evidence.isEmpty else {
            return .empty
        }

        if run.evidence.contains(where: { $0.availability == .unavailable }) {
            return .partial
        }

        switch run.phase {
        case .diagnosisStart:
            return .complete
        case .diagnosisBuild:
            return run.diagnosisSummary != nil ? .complete : .partial
        case .diagnosisTest:
            return run.testDiagnosisSummary != nil ? .complete : .partial
        case .diagnosisRuntime:
            return run.runtimeSummary != nil ? .complete : .partial
        }
    }

    private static func recoveryNarrativeDetail(_ recovery: WorkflowRecoveryRecord) -> String {
        var detail = "Recovery \(recovery.recoveryId): \(recovery.summary)"
        detail += " | issue=\(recovery.issue.label)"
        detail += " | action=\(recovery.action.label)"
        detail += " | status=\(recovery.status.rawValue)"
        detail += " | resumed=\(recovery.resumed ? "yes" : "no")"
        return detail
    }
}

private struct DiagnosisStatusWorkflowError: Error {
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

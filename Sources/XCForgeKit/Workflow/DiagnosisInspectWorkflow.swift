import Foundation

public struct DiagnosisInspectWorkflow: Sendable {
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
          throw DiagnosisInspectWorkflowError(
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

  public func inspect(request: DiagnosisInspectRequest) async -> DiagnosisInspectResult {
    do {
      let run = try resolveRun(for: request)
      try Self.validate(run)

      let completeness = Self.evidenceCompleteness(for: run)
      return DiagnosisInspectResult(
        phase: run.phase,
        status: run.status,
        runId: run.runId,
        attemptId: run.attempt.attemptId,
        resolvedContext: run.resolvedContext,
        contextProvenance: run.contextProvenance,
        actionHistory: run.actionHistory,
        evidence: run.evidence,
        evidenceCompleteness: completeness,
        evidenceCompletenessReason: Self.evidenceCompletenessReason(for: run, completeness: completeness),
        failure: Self.terminalFailure(for: run),
        followOnAction: Self.followOnAction(for: run),
        persistedRunPath: runPath(run.runId).path
      )
    } catch let error as DiagnosisInspectWorkflowError {
      return DiagnosisInspectResult(
        phase: nil,
        status: nil,
        runId: request.runId,
        attemptId: nil,
        resolvedContext: nil,
        contextProvenance: nil,
        actionHistory: [],
        evidence: [],
        evidenceCompleteness: nil,
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
      return DiagnosisInspectResult(
        phase: nil,
        status: nil,
        runId: request.runId,
        attemptId: nil,
        resolvedContext: nil,
        contextProvenance: nil,
        actionHistory: [],
        evidence: [],
        evidenceCompleteness: nil,
        failure: WorkflowFailure(
          field: .workflow,
          classification: .executionFailed,
          message: "\(error)",
          observed: ObservedFailureEvidence(summary: "\(error)"),
          inferred: InferredFailureConclusion(
            summary:
              "An unexpected error occurred during troubleshooting inspection; the underlying issue may be transient or environmental."
          ),
          recoverability: .retryAfterFix
        ),
        persistedRunPath: nil
      )
    }
  }

  // MARK: - Run Resolution

  private func resolveRun(for request: DiagnosisInspectRequest) throws -> WorkflowRunRecord {
    if let runId = request.runId {
      let trimmedRunId = runId.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmedRunId.isEmpty else {
        throw DiagnosisInspectWorkflowError(
          field: .run,
          classification: .notFound,
          message: "Run ID must not be empty."
        )
      }
      do {
        return try loadRun(trimmedRunId)
      } catch let error as DiagnosisInspectWorkflowError {
        throw error
      } catch let error as CocoaError
        where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile
      {
        throw DiagnosisInspectWorkflowError(
          field: .run,
          classification: .notFound,
          message: "No diagnosis run was found for run ID \(trimmedRunId)."
        )
      } catch {
        throw DiagnosisInspectWorkflowError(
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

    throw DiagnosisInspectWorkflowError(
      field: .run,
      classification: .notFound,
      message: "No diagnosis runs are available to inspect."
    )
  }

  // MARK: - Validation

  private static func validate(_ run: WorkflowRunRecord) throws {
    guard run.workflow == .diagnosis else {
      throw DiagnosisInspectWorkflowError(
        field: .run,
        classification: .invalidRunState,
        message: "Run \(run.runId) is not a diagnosis workflow run."
      )
    }
  }

  // MARK: - Evidence Completeness

  static func evidenceCompleteness(for run: WorkflowRunRecord)
    -> DiagnosisInspectEvidenceCompleteness
  {
    guard
      !run.evidence.isEmpty || run.diagnosisSummary != nil || run.testDiagnosisSummary != nil
        || run.runtimeSummary != nil
    else {
      return .empty
    }

    let hasUnavailable = run.evidence.contains { $0.availability == .unavailable }

    if hasUnavailable {
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

  // MARK: - Evidence Completeness Reason

  static func evidenceCompletenessReason(
    for run: WorkflowRunRecord,
    completeness: DiagnosisInspectEvidenceCompleteness
  ) -> String? {
    switch completeness {
    case .complete, .unknown:
      return nil
    case .empty:
      return "No evidence has been collected yet for this run."
    case .partial:
      let unavailable = run.evidence.filter { $0.availability == .unavailable }
      if !unavailable.isEmpty {
        let kinds = unavailable.map { $0.kind.rawValue }
        let uniqueKinds = Array(Set(kinds)).sorted()
        return
          "\(unavailable.count) evidence artifact(s) unavailable (\(uniqueKinds.joined(separator: ", "))). This is expected when a build fails before producing all outputs."
      }

      switch run.phase {
      case .diagnosisBuild where run.diagnosisSummary == nil:
        return
          "Build diagnosis summary not yet available; the build phase may still be in progress or ended before producing a summary."
      case .diagnosisTest where run.testDiagnosisSummary == nil:
        return
          "Test diagnosis summary not yet available; the test phase may still be in progress or ended before producing a summary."
      case .diagnosisRuntime where run.runtimeSummary == nil:
        return
          "Runtime diagnosis summary not yet available; the runtime phase may still be in progress or ended before producing a summary."
      default:
        return nil
      }
    }
  }

  // MARK: - Terminal Failure

  private static func terminalFailure(for run: WorkflowRunRecord) -> WorkflowFailure? {
    guard run.status == .failed else {
      return nil
    }

    switch run.phase {
    case .diagnosisBuild:
      guard let summary = run.diagnosisSummary else { break }
      return WorkflowFailure(
        field: .workflow,
        classification: .executionFailed,
        message: summary.observedEvidence.summary,
        observed: ObservedFailureEvidence(
          summary: summary.observedEvidence.summary,
          detail: summary.observedEvidence.primarySignal?.message
        ),
        inferred: summary.inferredConclusion.map {
          InferredFailureConclusion(summary: $0.summary)
        },
        evidenceReferences: summary.supportingEvidence.isEmpty ? nil : summary.supportingEvidence
      )
    case .diagnosisTest:
      guard let summary = run.testDiagnosisSummary else { break }
      return WorkflowFailure(
        field: .workflow,
        classification: .executionFailed,
        message: summary.observedEvidence.summary,
        observed: ObservedFailureEvidence(
          summary: summary.observedEvidence.summary,
          detail: summary.observedEvidence.primaryFailure?.testIdentifier
        ),
        inferred: summary.inferredConclusion.map {
          InferredFailureConclusion(summary: $0.summary)
        },
        evidenceReferences: summary.supportingEvidence.isEmpty ? nil : summary.supportingEvidence
      )
    case .diagnosisRuntime:
      guard let summary = run.runtimeSummary else { break }
      return WorkflowFailure(
        field: .workflow,
        classification: .executionFailed,
        message: summary.observedEvidence.summary,
        observed: ObservedFailureEvidence(
          summary: summary.observedEvidence.summary,
          detail: summary.observedEvidence.primarySignal?.message
        ),
        inferred: summary.inferredConclusion.map {
          InferredFailureConclusion(summary: $0.summary)
        },
        evidenceReferences: summary.supportingEvidence.isEmpty ? nil : summary.supportingEvidence
      )
    case .diagnosisStart:
      break
    }

    return WorkflowFailure(
      field: .workflow,
      classification: .executionFailed,
      message: "Run failed at \(run.phase.rawValue) with no diagnosis summary available.",
      observed: ObservedFailureEvidence(
        summary: "Run failed at \(run.phase.rawValue) with status \(run.status.rawValue)."
      ),
      inferred: InferredFailureConclusion(
        summary:
          "The failure occurred before or without producing a phase-specific diagnosis summary."
      ),
      recoverability: .retryAfterFix
    )
  }

  // MARK: - Follow-On Action

  private static func followOnAction(for run: WorkflowRunRecord) -> WorkflowFollowOnAction? {
    guard run.status == .failed || run.status == .succeeded else {
      return nil
    }

    if run.status == .failed {
      return WorkflowFollowOnAction(
        action: "Review the observed evidence and inferred conclusions to identify the root cause.",
        rationale: "Run ended with failed status at \(run.phase.rawValue).",
        confidence: .evidenceSupported
      )
    }

    if !run.recoveryHistory.isEmpty {
      let count = run.recoveryHistory.count
      return WorkflowFollowOnAction(
        action: "Verify the fix holds — recovery was triggered during this run.",
        rationale: "\(count) recovery action(s) were recorded during this run.",
        confidence: .evidenceSupported
      )
    }

    return nil
  }
}

private struct DiagnosisInspectWorkflowError: Error {
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

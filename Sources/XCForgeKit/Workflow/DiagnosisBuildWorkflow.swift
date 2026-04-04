import Foundation

public struct DiagnosisBuildWorkflow: Sendable {
  typealias LoadRun = @Sendable (String) throws -> WorkflowRunRecord
  typealias PersistRun = @Sendable (WorkflowRunRecord) throws -> URL
  typealias ExecuteBuild =
    @Sendable (ResolvedWorkflowContext) async throws -> TestTools.BuildDiagnosisExecution
  typealias NowProvider = @Sendable () -> Date

  private let loadRun: LoadRun
  private let persistRun: PersistRun
  private let executeBuild: ExecuteBuild
  private let now: NowProvider

  public init() {
    self.init(
      loadRun: { runId in
        let store = RunStore()
        let fileURL = store.runFileURL(runId: runId)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
          throw DiagnosisBuildWorkflowError(
            field: .run,
            classification: .notFound,
            message: "No diagnosis run was found for run ID \(runId).",
            options: [],
            observed: ObservedFailureEvidence(
              summary: "No diagnosis run was found for run ID \(runId)."
            ),
            recoverability: .stop
          )
        }
        return try store.load(runId: runId)
      },
      persistRun: { run in try RunStore().update(run) },
      executeBuild: { context in
        try await TestTools.executeBuildDiagnosis(
          project: context.project,
          scheme: context.scheme,
          simulator: context.simulator,
          configuration: context.configuration
        )
      },
      now: Date.init
    )
  }

  init(
    loadRun: @escaping LoadRun,
    persistRun: @escaping PersistRun,
    executeBuild: @escaping ExecuteBuild,
    now: @escaping NowProvider = Date.init
  ) {
    self.loadRun = loadRun
    self.persistRun = persistRun
    self.executeBuild = executeBuild
    self.now = now
  }

  public func diagnose(request: DiagnosisBuildRequest) async -> DiagnosisBuildResult {
    do {
      let run: WorkflowRunRecord
      do {
        run = try loadRun(request.runId)
      } catch let error as DiagnosisBuildWorkflowError {
        throw error
      } catch let error as CocoaError
        where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile
      {
        throw DiagnosisBuildWorkflowError(
          field: .run,
          classification: .notFound,
          message: "No diagnosis run was found for run ID \(request.runId).",
          options: [],
          observed: ObservedFailureEvidence(
            summary: "No diagnosis run was found for run ID \(request.runId).",
            detail: "\(error)"
          ),
          recoverability: .stop
        )
      } catch {
        throw DiagnosisBuildWorkflowError(
          field: .run,
          classification: .executionFailed,
          message: "\(error)",
          options: [],
          observed: ObservedFailureEvidence(
            summary: "Failed to load the diagnosis run record.",
            detail: "\(error)"
          ),
          inferred: InferredFailureConclusion(
            summary: "Build errors must be resolved before diagnosis can proceed."
          ),
          recoverability: .retryAfterFix
        )
      }
      try Self.validate(run)

      let execution: TestTools.BuildDiagnosisExecution
      do {
        execution = try await executeBuild(run.resolvedContext)
      } catch {
        let timestamp = now()
        let failedAttempt = WorkflowAttemptRecord(
          attemptId: run.attempt.attemptId,
          attemptNumber: run.attempt.attemptNumber,
          rerunOfAttemptId: run.attempt.rerunOfAttemptId,
          phase: .diagnosisBuild,
          startedAt: timestamp,
          status: .failed
        )
        let updatedRun = WorkflowRunRecord(
          schemaVersion: WorkflowRunRecord.currentSchemaVersion,
          runId: run.runId,
          workflow: run.workflow,
          phase: .diagnosisBuild,
          status: .failed,
          createdAt: run.createdAt,
          updatedAt: timestamp,
          attempt: failedAttempt,
          resolvedContext: run.resolvedContext,
          diagnosisSummary: nil,
          testDiagnosisSummary: run.testDiagnosisSummary,
          environmentPreflight: run.environmentPreflight,
          evidence: run.evidence
            + Self.unavailableEvidence(
              for: failedAttempt,
              phase: .diagnosisBuild
            ),
          attemptHistory: run.backfilledAttemptHistory + [
            WorkflowAttemptSnapshot(
              attempt: failedAttempt,
              phase: .diagnosisBuild,
              status: .failed,
              resolvedContext: run.resolvedContext,
              testDiagnosisSummary: run.testDiagnosisSummary,
              recordedAt: timestamp
            )
          ],
          actionHistory: run.actionHistory + [
            WorkflowActionRecord(
              kind: .buildStarted,
              phase: .diagnosisBuild,
              attemptId: failedAttempt.attemptId,
              timestamp: run.attempt.startedAt
            ),
            WorkflowActionRecord(
              kind: .buildCompleted,
              phase: .diagnosisBuild,
              attemptId: failedAttempt.attemptId,
              timestamp: timestamp,
              detail: "Build execution failed"
            ),
          ]
        )
        do {
          _ = try persistRun(updatedRun)
        } catch {
          throw DiagnosisBuildWorkflowError(
            field: .workflow,
            classification: .executionFailed,
            message:
              "Build execution failed and xcforge could not persist the failed run state: \(error)",
            options: [],
            observed: ObservedFailureEvidence(
              summary: "Build execution failed and xcforge could not persist the failed run state.",
              detail: "\(error)"
            ),
            inferred: InferredFailureConclusion(
              summary: "Build errors must be resolved before diagnosis can proceed."
            ),
            recoverability: .retryAfterFix,
            evidenceReferences: Self.evidenceReferences(from: run.evidence)
          )
        }

        throw DiagnosisBuildWorkflowError(
          field: .build,
          classification: .executionFailed,
          message: "\(error)",
          options: [],
          observed: ObservedFailureEvidence(
            summary: "Build execution failed during diagnosis.",
            detail: "\(error)"
          ),
          inferred: InferredFailureConclusion(
            summary: "Build errors must be resolved before diagnosis can proceed."
          ),
          recoverability: .retryAfterFix,
          evidenceReferences: Self.evidenceReferences(from: run.evidence)
        )
      }

      let summary = Self.buildSummary(from: execution)
      let status: WorkflowStatus = execution.succeeded ? .succeeded : .failed
      let timestamp = now()
      let updatedAttempt = WorkflowAttemptRecord(
        attemptId: run.attempt.attemptId,
        attemptNumber: run.attempt.attemptNumber,
        rerunOfAttemptId: run.attempt.rerunOfAttemptId,
        phase: .diagnosisBuild,
        startedAt: timestamp,
        status: status
      )
      let updatedRun = WorkflowRunRecord(
        schemaVersion: WorkflowRunRecord.currentSchemaVersion,
        runId: run.runId,
        workflow: run.workflow,
        phase: .diagnosisBuild,
        status: status,
        createdAt: run.createdAt,
        updatedAt: timestamp,
        attempt: updatedAttempt,
        resolvedContext: run.resolvedContext,
        diagnosisSummary: summary,
        testDiagnosisSummary: run.testDiagnosisSummary,
        environmentPreflight: run.environmentPreflight,
        evidence: run.evidence
          + Self.evidence(
            for: execution,
            attempt: updatedAttempt,
            phase: .diagnosisBuild
          ),
        attemptHistory: run.backfilledAttemptHistory + [
          WorkflowAttemptSnapshot(
            attempt: updatedAttempt,
            phase: .diagnosisBuild,
            status: status,
            resolvedContext: run.resolvedContext,
            diagnosisSummary: summary,
            testDiagnosisSummary: run.testDiagnosisSummary,
            recordedAt: timestamp
          )
        ],
        actionHistory: run.actionHistory + [
          WorkflowActionRecord(
            kind: .buildStarted,
            phase: .diagnosisBuild,
            attemptId: updatedAttempt.attemptId,
            timestamp: run.attempt.startedAt
          ),
          WorkflowActionRecord(
            kind: .buildCompleted,
            phase: .diagnosisBuild,
            attemptId: updatedAttempt.attemptId,
            timestamp: timestamp,
            detail: status == .succeeded ? "Build succeeded" : "Build failed"
          ),
          WorkflowActionRecord(
            kind: .evidenceCaptured,
            phase: .diagnosisBuild,
            attemptId: updatedAttempt.attemptId,
            timestamp: timestamp,
            detail: "Build diagnosis evidence captured"
          ),
        ]
      )
      let persistedURL = try persistRun(updatedRun)

      return DiagnosisBuildResult(
        status: status,
        runId: updatedRun.runId,
        attemptId: updatedRun.attempt.attemptId,
        resolvedContext: updatedRun.resolvedContext,
        summary: summary,
        failure: nil,
        persistedRunPath: persistedURL.path
      )
    } catch let error as DiagnosisBuildWorkflowError {
      return DiagnosisBuildResult(
        status: error.status,
        runId: request.runId,
        attemptId: nil,
        resolvedContext: nil,
        summary: nil,
        failure: WorkflowFailure(
          field: error.field,
          classification: error.classification,
          message: error.message,
          options: error.options,
          observed: error.observed,
          inferred: error.inferred,
          recoverability: error.recoverability,
          evidenceReferences: error.evidenceReferences
        ),
        persistedRunPath: nil
      )
    } catch {
      return DiagnosisBuildResult(
        status: .failed,
        runId: request.runId,
        attemptId: nil,
        resolvedContext: nil,
        summary: nil,
        failure: WorkflowFailure(
          field: .workflow,
          classification: .executionFailed,
          message: "\(error)",
          observed: ObservedFailureEvidence(
            summary: "An unexpected error occurred during the diagnosis build workflow.",
            detail: "\(error)"
          ),
          inferred: InferredFailureConclusion(
            summary: "Build errors must be resolved before diagnosis can proceed."
          ),
          recoverability: .retryAfterFix
        ),
        persistedRunPath: nil
      )
    }
  }

  static func validate(_ run: WorkflowRunRecord) throws {
    guard run.workflow == .diagnosis else {
      throw DiagnosisBuildWorkflowError(
        field: .run,
        classification: .invalidRunState,
        message: "Run \(run.runId) is not a diagnosis workflow run.",
        options: [],
        observed: ObservedFailureEvidence(
          summary: "Run \(run.runId) is not a diagnosis workflow run."
        ),
        recoverability: .stop
      )
    }

    guard run.phase == .diagnosisStart, run.status == .inProgress else {
      throw DiagnosisBuildWorkflowError(
        field: .run,
        classification: .invalidRunState,
        message:
          "Run \(run.runId) is in phase \(run.phase.rawValue) with status \(run.status.rawValue); build diagnosis currently requires a started diagnosis run.",
        options: [],
        observed: ObservedFailureEvidence(
          summary:
            "Run \(run.runId) is in phase \(run.phase.rawValue) with status \(run.status.rawValue); build diagnosis currently requires a started diagnosis run."
        ),
        recoverability: .stop
      )
    }
  }

  static func buildSummary(from execution: TestTools.BuildDiagnosisExecution)
    -> BuildDiagnosisSummary
  {
    let compactIssues = deduplicatedIssues(from: execution.issues)
    let primarySignal = choosePrimarySignal(from: compactIssues)
    var supportingEvidence = [
      EvidenceReference(
        kind: "xcresult",
        path: execution.xcresultPath,
        source: "xcodebuild.result_bundle"
      )
    ]
    if let stderrEvidencePath = execution.stderrEvidencePath {
      supportingEvidence.append(
        EvidenceReference(
          kind: "stderr",
          path: stderrEvidencePath,
          source: "xcodebuild.stderr"
        )
      )
    }

    if execution.succeeded {
      let observed = ObservedBuildEvidence(
        summary: execution.warningCount > 0 || execution.analyzerWarningCount > 0
          ? "Build succeeded without an error diagnostic."
          : "Build succeeded with no build failure signal in the captured diagnostics.",
        primarySignal: nil,
        additionalIssueCount: 0,
        errorCount: execution.errorCount,
        warningCount: execution.warningCount,
        analyzerWarningCount: execution.analyzerWarningCount
      )
      return BuildDiagnosisSummary(
        observedEvidence: observed,
        inferredConclusion: InferredBuildConclusion(
          summary: "No build failure signal was found for this run."
        ),
        supportingEvidence: supportingEvidence
      )
    }

    let observed = ObservedBuildEvidence(
      summary: observedSummary(
        for: execution, primarySignal: primarySignal, uniqueIssueCount: compactIssues.count),
      primarySignal: primarySignal.map {
        BuildIssueSummary(
          severity: $0.severity,
          message: $0.message,
          location: $0.location,
          source: $0.source
        )
      },
      additionalIssueCount: max(compactIssues.count - (primarySignal == nil ? 0 : 1), 0),
      errorCount: execution.errorCount,
      warningCount: execution.warningCount,
      analyzerWarningCount: execution.analyzerWarningCount
    )

    let inferredConclusion = InferredBuildConclusion(
      summary: inferredSummary(primarySignal: primarySignal)
    )

    return BuildDiagnosisSummary(
      observedEvidence: observed,
      inferredConclusion: inferredConclusion,
      supportingEvidence: supportingEvidence
    )
  }

  static func evidence(
    for execution: TestTools.BuildDiagnosisExecution,
    attempt: WorkflowAttemptRecord,
    phase: WorkflowPhase
  ) -> [WorkflowEvidenceRecord] {
    var evidence = [
      WorkflowEvidenceRecord(
        kind: .buildSummary,
        phase: phase,
        attemptId: attempt.attemptId,
        attemptNumber: attempt.attemptNumber,
        availability: .available,
        unavailableReason: nil,
        reference: "run_record.diagnosisSummary",
        source: "xcforge.diagnosis_build.summary"
      )
    ]

    evidence.append(
      evidenceRecord(
        kind: .xcresult,
        phase: phase,
        attempt: attempt,
        reference: execution.xcresultPath,
        source: "xcodebuild.result_bundle",
        missingDetail:
          "The build diagnosis reported an xcresult path, but no artifact was present on disk."
      )
    )

    if let stderrEvidencePath = execution.stderrEvidencePath {
      evidence.append(
        evidenceRecord(
          kind: .stderr,
          phase: phase,
          attempt: attempt,
          reference: stderrEvidencePath,
          source: "xcodebuild.stderr",
          missingDetail:
            "The build diagnosis reported a stderr artifact path, but no artifact was present on disk."
        )
      )
    } else {
      evidence.append(
        WorkflowEvidenceRecord(
          kind: .stderr,
          phase: phase,
          attemptId: attempt.attemptId,
          attemptNumber: attempt.attemptNumber,
          availability: .unavailable,
          unavailableReason: .notCaptured,
          reference: nil,
          source: "xcodebuild.stderr",
          detail: "No stderr artifact was captured for this build diagnosis phase."
        )
      )
    }

    return evidence
  }

  static func unavailableEvidence(
    for attempt: WorkflowAttemptRecord,
    phase: WorkflowPhase
  ) -> [WorkflowEvidenceRecord] {
    [
      WorkflowEvidenceRecord(
        kind: .buildSummary,
        phase: phase,
        attemptId: attempt.attemptId,
        attemptNumber: attempt.attemptNumber,
        availability: .unavailable,
        unavailableReason: .executionFailed,
        reference: nil,
        source: "xcforge.diagnosis_build.summary",
        detail: "Build execution failed before xcforge could persist a build summary."
      ),
      WorkflowEvidenceRecord(
        kind: .xcresult,
        phase: phase,
        attemptId: attempt.attemptId,
        attemptNumber: attempt.attemptNumber,
        availability: .unavailable,
        unavailableReason: .executionFailed,
        reference: nil,
        source: "xcodebuild.result_bundle",
        detail: "Build execution failed before an xcresult artifact was captured."
      ),
      WorkflowEvidenceRecord(
        kind: .stderr,
        phase: phase,
        attemptId: attempt.attemptId,
        attemptNumber: attempt.attemptNumber,
        availability: .unavailable,
        unavailableReason: .executionFailed,
        reference: nil,
        source: "xcodebuild.stderr",
        detail: "Build execution failed before a stderr artifact was captured."
      ),
    ]
  }

  static func evidenceRecord(
    kind: WorkflowEvidenceKind,
    phase: WorkflowPhase,
    attempt: WorkflowAttemptRecord,
    reference: String,
    source: String,
    missingDetail: String
  ) -> WorkflowEvidenceRecord {
    let artifactExists = FileManager.default.fileExists(atPath: reference)
    return WorkflowEvidenceRecord(
      kind: kind,
      phase: phase,
      attemptId: attempt.attemptId,
      attemptNumber: attempt.attemptNumber,
      availability: artifactExists ? .available : .unavailable,
      unavailableReason: artifactExists ? nil : .missingOnDisk,
      reference: artifactExists ? reference : nil,
      source: source,
      detail: artifactExists ? nil : missingDetail
    )
  }

  private static func observedSummary(
    for execution: TestTools.BuildDiagnosisExecution,
    primarySignal: TestTools.BuildIssueObservation?,
    uniqueIssueCount: Int
  ) -> String {
    if let primarySignal, let location = primarySignal.location {
      let shortPath = (location.filePath as NSString).lastPathComponent
      if let line = location.line {
        return
          "Primary signal selected from \(uniqueIssueCount) unique diagnostic(s): \(shortPath):\(line)."
      }
      return "Primary signal selected from \(uniqueIssueCount) unique diagnostic(s): \(shortPath)."
    }

    if execution.errorCount > 0 {
      return
        "Build failed with \(execution.errorCount) error diagnostic(s); a primary signal was selected from the captured diagnostics."
    }

    return
      "Build failed, but only limited structured diagnostics were available; inspect the supporting evidence for the full context."
  }

  private static func inferredSummary(primarySignal: TestTools.BuildIssueObservation?) -> String {
    guard let primarySignal else {
      return
        "The build failed, but a primary structured failure signal could not be inferred from the available diagnostics."
    }
    return "The build appears blocked by: \(primarySignal.message)"
  }

  private static func deduplicatedIssues(
    from issues: [TestTools.BuildIssueObservation]
  ) -> [TestTools.BuildIssueObservation] {
    var seen = Set<String>()
    var compact: [TestTools.BuildIssueObservation] = []

    for issue in issues {
      let locationKey = [
        issue.location?.filePath ?? "",
        issue.location?.line.map(String.init) ?? "",
        issue.location?.column.map(String.init) ?? "",
      ].joined(separator: "|")
      let key = [
        issue.severity.rawValue,
        issue.message.lowercased().trimmingCharacters(in: .whitespacesAndNewlines),
        locationKey,
      ].joined(separator: "|")
      if seen.insert(key).inserted {
        compact.append(issue)
      }
    }

    return compact
  }

  private static func choosePrimarySignal(
    from issues: [TestTools.BuildIssueObservation]
  ) -> TestTools.BuildIssueObservation? {
    issues.first { $0.severity == .error && $0.location != nil }
      ?? issues.first { $0.severity == .error }
      ?? issues.first { $0.location != nil }
      ?? issues.first
  }

  static func evidenceReferences(from records: [WorkflowEvidenceRecord]) -> [EvidenceReference]? {
    let refs = records.compactMap { record -> EvidenceReference? in
      guard let path = record.reference else { return nil }
      return EvidenceReference(kind: record.kind.rawValue, path: path, source: record.source)
    }
    return refs.isEmpty ? nil : refs
  }
}

private struct DiagnosisBuildWorkflowError: Error {
  let field: ContextField
  let classification: WorkflowFailureClassification
  let message: String
  let options: [String]
  let observed: ObservedFailureEvidence?
  let inferred: InferredFailureConclusion?
  let recoverability: FailureRecoverability?
  let evidenceReferences: [EvidenceReference]?

  init(
    field: ContextField,
    classification: WorkflowFailureClassification,
    message: String,
    options: [String],
    observed: ObservedFailureEvidence? = nil,
    inferred: InferredFailureConclusion? = nil,
    recoverability: FailureRecoverability? = nil,
    evidenceReferences: [EvidenceReference]? = nil
  ) {
    self.field = field
    self.classification = classification
    self.message = message
    self.options = options
    self.observed = observed
    self.inferred = inferred
    self.recoverability = recoverability
    self.evidenceReferences = evidenceReferences
  }

  var status: WorkflowStatus {
    .failed
  }
}

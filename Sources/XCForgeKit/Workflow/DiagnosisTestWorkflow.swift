import Foundation

public struct DiagnosisTestWorkflow: Sendable {
  typealias LoadRun = @Sendable (String) throws -> WorkflowRunRecord
  typealias PersistRun = @Sendable (WorkflowRunRecord) throws -> URL
  typealias ExecuteTest =
    @Sendable (ResolvedWorkflowContext) async throws -> TestTools.TestDiagnosisExecution
  typealias NowProvider = @Sendable () -> Date

  private let loadRun: LoadRun
  private let persistRun: PersistRun
  private let executeTest: ExecuteTest
  private let now: NowProvider

  public init() {
    self.init(
      loadRun: { runId in
        let store = RunStore()
        let fileURL = store.runFileURL(runId: runId)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
          throw DiagnosisTestWorkflowError(
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
      executeTest: { context in
        try await TestTools.executeTestDiagnosis(
          project: context.project,
          scheme: context.scheme,
          simulator: context.simulator,
          configuration: context.configuration,
          env: .live
        )
      },
      now: Date.init
    )
  }

  init(
    loadRun: @escaping LoadRun,
    persistRun: @escaping PersistRun,
    executeTest: @escaping ExecuteTest,
    now: @escaping NowProvider = Date.init
  ) {
    self.loadRun = loadRun
    self.persistRun = persistRun
    self.executeTest = executeTest
    self.now = now
  }

  public func diagnose(request: DiagnosisTestRequest) async -> DiagnosisTestResult {
    do {
      let run: WorkflowRunRecord
      do {
        run = try loadRun(request.runId)
      } catch let error as DiagnosisTestWorkflowError {
        throw error
      } catch let error as CocoaError
        where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile
      {
        throw DiagnosisTestWorkflowError(
          status: .failed,
          field: .run,
          classification: .notFound,
          message: "No diagnosis run was found for run ID \(request.runId).",
          options: []
        )
      } catch {
        throw DiagnosisTestWorkflowError(
          status: .failed,
          field: .run,
          classification: .executionFailed,
          message: "\(error)",
          options: []
        )
      }

      try Self.validate(run)

      let execution: TestTools.TestDiagnosisExecution
      do {
        execution = try await executeTest(run.resolvedContext)
      } catch {
        let classifiedFailure = Self.classifyExecutionFailure(message: "\(error)")
        let phaseStartedAt = now()
        let failedAttempt = WorkflowAttemptRecord(
          attemptId: run.attempt.attemptId,
          attemptNumber: run.attempt.attemptNumber,
          rerunOfAttemptId: run.attempt.rerunOfAttemptId,
          phase: .diagnosisTest,
          startedAt: phaseStartedAt,
          status: classifiedFailure.status
        )
        let updatedRun = WorkflowRunRecord(
          schemaVersion: WorkflowRunRecord.currentSchemaVersion,
          runId: run.runId,
          workflow: run.workflow,
          phase: .diagnosisTest,
          status: classifiedFailure.status,
          createdAt: run.createdAt,
          updatedAt: phaseStartedAt,
          attempt: failedAttempt,
          resolvedContext: run.resolvedContext,
          diagnosisSummary: run.diagnosisSummary,
          testDiagnosisSummary: nil,
          environmentPreflight: run.environmentPreflight,
          evidence: run.evidence
            + Self.unavailableEvidence(
              for: failedAttempt,
              phase: .diagnosisTest,
              failureMessage: classifiedFailure.message
            ),
          attemptHistory: run.backfilledAttemptHistory + [
            WorkflowAttemptSnapshot(
              attempt: failedAttempt,
              phase: .diagnosisTest,
              status: classifiedFailure.status,
              resolvedContext: run.resolvedContext,
              diagnosisSummary: run.diagnosisSummary,
              recordedAt: phaseStartedAt
            )
          ],
          actionHistory: run.actionHistory + [
            WorkflowActionRecord(
              kind: .testStarted,
              phase: .diagnosisTest,
              attemptId: failedAttempt.attemptId,
              timestamp: run.attempt.startedAt
            ),
            WorkflowActionRecord(
              kind: .testCompleted,
              phase: .diagnosisTest,
              attemptId: failedAttempt.attemptId,
              timestamp: phaseStartedAt,
              detail: "Test execution failed"
            ),
          ]
        )
        let persistedURL: URL?
        do {
          persistedURL = try persistRun(updatedRun)
        } catch {
          return DiagnosisTestResult(
            status: classifiedFailure.status,
            runId: updatedRun.runId,
            attemptId: updatedRun.attempt.attemptId,
            resolvedContext: updatedRun.resolvedContext,
            summary: nil,
            failure: WorkflowFailure(
              field: .workflow,
              classification: .executionFailed,
              message:
                "Test execution failed and xcforge could not persist the failed run state: \(error)",
              options: [],
              observed: ObservedFailureEvidence(
                summary:
                  "Test execution failed and xcforge could not persist the failed run state: \(error)",
                detail: "Original execution failure: \(classifiedFailure.message)"
              ),
              inferred: InferredFailureConclusion(
                summary:
                  "The test execution failed, and the subsequent attempt to persist the failure state also failed."
              ),
              recoverability: .retryAfterFix
            ),
            persistedRunPath: nil
          )
        }

        return DiagnosisTestResult(
          status: classifiedFailure.status,
          runId: updatedRun.runId,
          attemptId: updatedRun.attempt.attemptId,
          resolvedContext: updatedRun.resolvedContext,
          summary: nil,
          failure: WorkflowFailure(
            field: classifiedFailure.field,
            classification: classifiedFailure.classification,
            message: classifiedFailure.message,
            options: classifiedFailure.options,
            observed: ObservedFailureEvidence(
              summary: classifiedFailure.message
            ),
            inferred: InferredFailureConclusion(
              summary: "Test execution failed before xcforge could extract test results."
            ),
            recoverability: .retryAfterFix
          ),
          persistedRunPath: persistedURL?.path
        )
      }

      if let blocker = Self.classifyExecutionBlocker(execution) {
        let phaseStartedAt = now()
        let summary = Self.buildSummary(from: execution)
        let updatedAttempt = WorkflowAttemptRecord(
          attemptId: run.attempt.attemptId,
          attemptNumber: run.attempt.attemptNumber,
          rerunOfAttemptId: run.attempt.rerunOfAttemptId,
          phase: .diagnosisTest,
          startedAt: phaseStartedAt,
          status: blocker.status
        )
        let updatedRun = WorkflowRunRecord(
          schemaVersion: WorkflowRunRecord.currentSchemaVersion,
          runId: run.runId,
          workflow: run.workflow,
          phase: .diagnosisTest,
          status: blocker.status,
          createdAt: run.createdAt,
          updatedAt: phaseStartedAt,
          attempt: updatedAttempt,
          resolvedContext: run.resolvedContext,
          diagnosisSummary: run.diagnosisSummary,
          testDiagnosisSummary: summary,
          environmentPreflight: run.environmentPreflight,
          evidence: run.evidence
            + Self.evidence(
              for: execution,
              attempt: updatedAttempt,
              phase: .diagnosisTest
            ),
          attemptHistory: run.backfilledAttemptHistory + [
            WorkflowAttemptSnapshot(
              attempt: updatedAttempt,
              phase: .diagnosisTest,
              status: blocker.status,
              resolvedContext: run.resolvedContext,
              diagnosisSummary: run.diagnosisSummary,
              testDiagnosisSummary: summary,
              recordedAt: phaseStartedAt
            )
          ],
          actionHistory: run.actionHistory + [
            WorkflowActionRecord(
              kind: .testStarted,
              phase: .diagnosisTest,
              attemptId: updatedAttempt.attemptId,
              timestamp: run.attempt.startedAt
            ),
            WorkflowActionRecord(
              kind: .testCompleted,
              phase: .diagnosisTest,
              attemptId: updatedAttempt.attemptId,
              timestamp: phaseStartedAt,
              detail: "Test execution blocked"
            ),
            WorkflowActionRecord(
              kind: .evidenceCaptured,
              phase: .diagnosisTest,
              attemptId: updatedAttempt.attemptId,
              timestamp: phaseStartedAt,
              detail: "Test diagnosis evidence captured"
            ),
          ]
        )
        let persistedURL = try persistRun(updatedRun)

        return DiagnosisTestResult(
          status: blocker.status,
          runId: updatedRun.runId,
          attemptId: updatedRun.attempt.attemptId,
          resolvedContext: updatedRun.resolvedContext,
          summary: summary,
          failure: WorkflowFailure(
            field: blocker.field,
            classification: blocker.classification,
            message: blocker.message,
            options: blocker.options,
            observed: ObservedFailureEvidence(
              summary: blocker.message
            ),
            inferred: InferredFailureConclusion(
              summary: "Test execution completed but produced no extractable test failures."
            ),
            recoverability: .retryAfterFix,
            evidenceReferences: summary.supportingEvidence
          ),
          persistedRunPath: persistedURL.path
        )
      }

      let summary = Self.buildSummary(from: execution)
      let status: WorkflowStatus = execution.succeeded ? .succeeded : .failed
      let phaseStartedAt = now()
      let updatedAttempt = WorkflowAttemptRecord(
        attemptId: run.attempt.attemptId,
        attemptNumber: run.attempt.attemptNumber,
        rerunOfAttemptId: run.attempt.rerunOfAttemptId,
        phase: .diagnosisTest,
        startedAt: phaseStartedAt,
        status: status
      )
      let updatedRun = WorkflowRunRecord(
        schemaVersion: WorkflowRunRecord.currentSchemaVersion,
        runId: run.runId,
        workflow: run.workflow,
        phase: .diagnosisTest,
        status: status,
        createdAt: run.createdAt,
        updatedAt: phaseStartedAt,
        attempt: updatedAttempt,
        resolvedContext: run.resolvedContext,
        diagnosisSummary: run.diagnosisSummary,
        testDiagnosisSummary: summary,
        environmentPreflight: run.environmentPreflight,
        evidence: run.evidence
          + Self.evidence(
            for: execution,
            attempt: updatedAttempt,
            phase: .diagnosisTest
          ),
        attemptHistory: run.backfilledAttemptHistory + [
          WorkflowAttemptSnapshot(
            attempt: updatedAttempt,
            phase: .diagnosisTest,
            status: status,
            resolvedContext: run.resolvedContext,
            diagnosisSummary: run.diagnosisSummary,
            testDiagnosisSummary: summary,
            recordedAt: phaseStartedAt
          )
        ],
        actionHistory: run.actionHistory + [
          WorkflowActionRecord(
            kind: .testStarted,
            phase: .diagnosisTest,
            attemptId: updatedAttempt.attemptId,
            timestamp: run.attempt.startedAt
          ),
          WorkflowActionRecord(
            kind: .testCompleted,
            phase: .diagnosisTest,
            attemptId: updatedAttempt.attemptId,
            timestamp: phaseStartedAt,
            detail: status == .succeeded ? "Tests succeeded" : "Tests failed"
          ),
          WorkflowActionRecord(
            kind: .evidenceCaptured,
            phase: .diagnosisTest,
            attemptId: updatedAttempt.attemptId,
            timestamp: phaseStartedAt,
            detail: "Test diagnosis evidence captured"
          ),
        ]
      )
      let persistedURL = try persistRun(updatedRun)

      return DiagnosisTestResult(
        status: status,
        runId: updatedRun.runId,
        attemptId: updatedRun.attempt.attemptId,
        resolvedContext: updatedRun.resolvedContext,
        summary: summary,
        failure: nil,
        persistedRunPath: persistedURL.path
      )
    } catch let error as DiagnosisTestWorkflowError {
      let recoverability = error.classification.recoverability
      return DiagnosisTestResult(
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
          observed: ObservedFailureEvidence(
            summary: error.message
          ),
          inferred: error.classification == .executionFailed
            ? InferredFailureConclusion(
              summary: "Test execution failed before xcforge could extract test results.")
            : nil,
          recoverability: recoverability
        ),
        persistedRunPath: nil
      )
    } catch {
      return DiagnosisTestResult(
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
            summary: "\(error)"
          ),
          inferred: InferredFailureConclusion(
            summary: "An unexpected error occurred during the test diagnosis workflow."
          ),
          recoverability: .retryAfterFix
        ),
        persistedRunPath: nil
      )
    }
  }

  static func validate(_ run: WorkflowRunRecord) throws {
    guard run.workflow == .diagnosis else {
      throw DiagnosisTestWorkflowError(
        status: .failed,
        field: .run,
        classification: .invalidRunState,
        message: "Run \(run.runId) is not a diagnosis workflow run.",
        options: []
      )
    }

    if run.phase == .diagnosisStart, run.status == .inProgress {
      return
    }

    if run.phase == .diagnosisBuild {
      return
    }

    let expectedState =
      "phase diagnosis_start with status in_progress, or any persisted diagnosis_build phase"
    throw DiagnosisTestWorkflowError(
      status: .failed,
      field: .run,
      classification: .invalidRunState,
      message:
        "Run \(run.runId) is in phase \(run.phase.rawValue) with status \(run.status.rawValue); test diagnosis currently requires \(expectedState).",
      options: []
    )
  }

  static func buildSummary(from execution: TestTools.TestDiagnosisExecution) -> TestDiagnosisSummary
  {
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

    if !execution.succeeded && execution.failures.isEmpty {
      let blockerMessage =
        execution.executionFailureMessage
        ?? "Test execution failed before xcforge could extract a primary failing test."
      return TestDiagnosisSummary(
        observedEvidence: ObservedTestEvidence(
          summary: blockerMessage,
          primaryFailure: nil,
          additionalFailureCount: 0,
          totalTestCount: execution.totalTestCount,
          failedTestCount: execution.failedTestCount,
          passedTestCount: execution.passedTestCount,
          skippedTestCount: execution.skippedTestCount,
          expectedFailureCount: execution.expectedFailureCount
        ),
        inferredConclusion: InferredTestConclusion(summary: blockerMessage),
        supportingEvidence: supportingEvidence
      )
    }

    if execution.succeeded {
      return TestDiagnosisSummary(
        observedEvidence: ObservedTestEvidence(
          summary: execution.hasStructuredSummary
            ? "Test run completed without a failing test signal."
            : "Test run completed successfully, but xcforge could not capture structured test counts or failure details.",
          primaryFailure: nil,
          additionalFailureCount: 0,
          totalTestCount: execution.totalTestCount,
          failedTestCount: execution.failedTestCount,
          passedTestCount: execution.passedTestCount,
          skippedTestCount: execution.skippedTestCount,
          expectedFailureCount: execution.expectedFailureCount
        ),
        inferredConclusion: InferredTestConclusion(
          summary: execution.hasStructuredSummary
            ? "No failing test signal was found for this run."
            : "The test run succeeded, but structured test summary data was unavailable."
        ),
        supportingEvidence: supportingEvidence
      )
    }

    let primaryFailure = choosePrimaryFailure(from: execution.failures)
    let observed = ObservedTestEvidence(
      summary: observedSummary(execution, primaryFailure: primaryFailure),
      primaryFailure: primaryFailure.map {
        TestFailureSummary(
          testName: $0.testName,
          testIdentifier: $0.testIdentifier,
          message: $0.message,
          source: $0.source
        )
      },
      additionalFailureCount: max(execution.failures.count - (primaryFailure == nil ? 0 : 1), 0),
      totalTestCount: execution.totalTestCount,
      failedTestCount: execution.failedTestCount,
      passedTestCount: execution.passedTestCount,
      skippedTestCount: execution.skippedTestCount,
      expectedFailureCount: execution.expectedFailureCount
    )

    return TestDiagnosisSummary(
      observedEvidence: observed,
      inferredConclusion: InferredTestConclusion(
        summary: inferredSummary(primaryFailure: primaryFailure)
      ),
      supportingEvidence: supportingEvidence
    )
  }

  static func evidence(
    for execution: TestTools.TestDiagnosisExecution,
    attempt: WorkflowAttemptRecord,
    phase: WorkflowPhase
  ) -> [WorkflowEvidenceRecord] {
    var evidence = [
      WorkflowEvidenceRecord(
        kind: .testSummary,
        phase: phase,
        attemptId: attempt.attemptId,
        attemptNumber: attempt.attemptNumber,
        availability: .available,
        unavailableReason: nil,
        reference: "run_record.testDiagnosisSummary",
        source: "xcforge.diagnosis_test.summary"
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
          "The test diagnosis reported an xcresult path, but no artifact was present on disk."
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
            "The test diagnosis reported a stderr artifact path, but no artifact was present on disk."
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
          detail: "No stderr artifact was captured for this test diagnosis phase."
        )
      )
    }

    return evidence
  }

  static func unavailableEvidence(
    for attempt: WorkflowAttemptRecord,
    phase: WorkflowPhase,
    failureMessage: String
  ) -> [WorkflowEvidenceRecord] {
    [
      WorkflowEvidenceRecord(
        kind: .testSummary,
        phase: phase,
        attemptId: attempt.attemptId,
        attemptNumber: attempt.attemptNumber,
        availability: .unavailable,
        unavailableReason: .executionFailed,
        reference: nil,
        source: "xcforge.diagnosis_test.summary",
        detail:
          "Test execution failed before xcforge could persist a test summary. \(failureMessage)"
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
        detail: "Test execution failed before an xcresult artifact was captured."
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
        detail: "Test execution failed before a stderr artifact was captured."
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

  static func choosePrimaryFailure(
    from failures: [TestTools.TestFailureObservation]
  ) -> TestTools.TestFailureObservation? {
    failures.first { !$0.message.isEmpty && !$0.testIdentifier.isEmpty }
      ?? failures.first { !$0.message.isEmpty }
      ?? failures.first
  }

  static func observedSummary(
    _ execution: TestTools.TestDiagnosisExecution,
    primaryFailure: TestTools.TestFailureObservation?
  ) -> String {
    guard let primaryFailure else {
      return
        "Test run failed, but a primary failing test could not be extracted from the captured diagnostics."
    }

    let headline =
      primaryFailure.testIdentifier.isEmpty
      ? primaryFailure.testName : primaryFailure.testIdentifier
    return
      "Primary failing test selected from \(max(execution.failedTestCount, execution.failures.count)) failing test(s): \(headline)."
  }

  static func inferredSummary(
    primaryFailure: TestTools.TestFailureObservation?
  ) -> String {
    guard let primaryFailure else {
      return
        "The test run failed, but a primary failing test could not be inferred from the available diagnostics."
    }
    let headline =
      primaryFailure.testIdentifier.isEmpty
      ? primaryFailure.testName : primaryFailure.testIdentifier
    return
      "The run appears primarily blocked by failing test \(headline): \(primaryFailure.message)"
  }

  static func classifyExecutionBlocker(
    _ execution: TestTools.TestDiagnosisExecution
  ) -> DiagnosisTestWorkflowError? {
    guard !execution.succeeded, execution.failures.isEmpty else {
      return nil
    }

    return classifyExecutionFailure(
      message: execution.executionFailureMessage
        ?? "Test execution failed before xcforge could extract a primary failing test."
    )
  }

  static func classifyExecutionFailure(message: String) -> DiagnosisTestWorkflowError {
    let lowercaseMessage = message.lowercased()
    let unsupportedPatterns = [
      "unable to find a destination matching",
      "unsupported destination",
      "no available devices",
      "platform not currently installed",
      "failed to boot",
      "simulator device returned an error",
      "destination specifier",
      "unavailable",
    ]
    let isUnsupported = unsupportedPatterns.contains { lowercaseMessage.contains($0) }

    return DiagnosisTestWorkflowError(
      status: isUnsupported ? .unsupported : .failed,
      field: isUnsupported ? .simulator : .test,
      classification: isUnsupported ? .unsupportedContext : .executionFailed,
      message: message,
      options: []
    )
  }
}

struct DiagnosisTestWorkflowError: Error {
  let status: WorkflowStatus
  let field: ContextField
  let classification: WorkflowFailureClassification
  let message: String
  let options: [String]
}

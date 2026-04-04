import Foundation

public struct DiagnosisVerifyWorkflow: Sendable {
  typealias LoadRun = @Sendable (String) throws -> WorkflowRunRecord
  typealias PersistRun = @Sendable (WorkflowRunRecord) throws -> URL
  typealias ExecuteBuild =
    @Sendable (ResolvedWorkflowContext) async throws -> TestTools.BuildDiagnosisExecution
  typealias ExecuteTest =
    @Sendable (ResolvedWorkflowContext) async throws -> TestTools.TestDiagnosisExecution
  typealias ResolveAppContext =
    @Sendable (String, String, String, String) async throws -> AppContext
  typealias NowProvider = @Sendable () -> Date
  typealias IDProvider = @Sendable () -> String

  private let loadRun: LoadRun
  private let persistRun: PersistRun
  private let executeBuild: ExecuteBuild
  private let executeTest: ExecuteTest
  private let resolveAppContext: ResolveAppContext
  private let now: NowProvider
  private let makeID: IDProvider

  public init() {
    self.init(
      loadRun: { runId in
        let store = RunStore()
        let fileURL = store.runFileURL(runId: runId)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
          throw DiagnosisVerifyWorkflowError(
            status: .failed,
            field: .run,
            classification: .notFound,
            message: "No diagnosis run was found for run ID \(runId)."
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
          configuration: context.configuration,
          env: .live
        )
      },
      executeTest: { context in
        try await TestTools.executeTestDiagnosis(
          project: context.project,
          scheme: context.scheme,
          simulator: context.simulator,
          configuration: context.configuration,
          env: .live
        )
      },
      resolveAppContext: { project, scheme, simulator, configuration in
        let buildInfo = try await BuildTools.resolveBuildProductInfo(
          project: project,
          scheme: scheme,
          simulator: simulator,
          configuration: configuration,
          env: .live
        )
        return AppContext(bundleId: buildInfo.bundleId, appPath: buildInfo.appPath)
      },
      now: Date.init,
      makeID: { UUID().uuidString.lowercased() }
    )
  }

  init(
    loadRun: @escaping LoadRun,
    persistRun: @escaping PersistRun,
    executeBuild: @escaping ExecuteBuild,
    executeTest: @escaping ExecuteTest,
    resolveAppContext: @escaping ResolveAppContext,
    now: @escaping NowProvider = Date.init,
    makeID: @escaping IDProvider = { UUID().uuidString.lowercased() }
  ) {
    self.loadRun = loadRun
    self.persistRun = persistRun
    self.executeBuild = executeBuild
    self.executeTest = executeTest
    self.resolveAppContext = resolveAppContext
    self.now = now
    self.makeID = makeID
  }

  public func verify(request: DiagnosisVerifyRequest) async -> DiagnosisVerifyResult {
    do {
      let run = try loadRun(request.runId)
      try Self.validate(run)

      let sourceAttemptId = run.attempt.attemptId
      let attemptNumber =
        (run.backfilledAttemptHistory.map { $0.attempt.attemptNumber }.max()
          ?? run.attempt.attemptNumber) + 1
      let attemptId = makeID()
      let resolvedContext: ResolvedWorkflowContext
      do {
        resolvedContext = try await resolveContext(for: run, request: request)
      } catch let error as DiagnosisVerifyWorkflowError {
        return persistResolutionFailure(
          run: run,
          sourceAttemptId: sourceAttemptId,
          attemptId: attemptId,
          attemptNumber: attemptNumber,
          failure: error
        )
      }

      switch run.phase {
      case .diagnosisBuild:
        return await verifyBuild(
          run: run,
          sourceAttemptId: sourceAttemptId,
          resolvedContext: resolvedContext,
          attemptId: attemptId,
          attemptNumber: attemptNumber
        )
      case .diagnosisTest:
        return await verifyTest(
          run: run,
          sourceAttemptId: sourceAttemptId,
          resolvedContext: resolvedContext,
          attemptId: attemptId,
          attemptNumber: attemptNumber
        )
      case .diagnosisStart:
        throw DiagnosisVerifyWorkflowError(
          status: .failed,
          field: .run,
          classification: .invalidRunState,
          message:
            "Run \(run.runId) has not completed a build or test diagnosis yet, so there is no validation path to rerun."
        )
      case .diagnosisRuntime:
        throw DiagnosisVerifyWorkflowError(
          status: .failed,
          field: .run,
          classification: .invalidRunState,
          message:
            "Run \(run.runId) is in diagnosis_runtime; verification reruns are currently limited to build and test diagnosis phases."
        )
      }
    } catch let error as DiagnosisVerifyWorkflowError {
      return DiagnosisVerifyResult(
        phase: nil,
        status: error.status,
        outcome: nil,
        runId: request.runId,
        attemptId: nil,
        sourceAttemptId: nil,
        resolvedContext: nil,
        summary: nil,
        buildSummary: nil,
        testSummary: nil,
        evidence: [],
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
      return DiagnosisVerifyResult(
        phase: nil,
        status: .failed,
        outcome: nil,
        runId: request.runId,
        attemptId: nil,
        sourceAttemptId: nil,
        resolvedContext: nil,
        summary: nil,
        buildSummary: nil,
        testSummary: nil,
        evidence: [],
        failure: WorkflowFailure(
          field: .workflow,
          classification: .executionFailed,
          message: "\(error)",
          observed: ObservedFailureEvidence(summary: "\(error)"),
          inferred: InferredFailureConclusion(
            summary:
              "An unexpected error occurred during verification; the underlying issue may be transient or environmental."
          ),
          recoverability: .retryAfterFix
        ),
        persistedRunPath: nil
      )
    }
  }

  private func verifyBuild(
    run: WorkflowRunRecord,
    sourceAttemptId: String,
    resolvedContext: ResolvedWorkflowContext,
    attemptId: String,
    attemptNumber: Int
  ) async -> DiagnosisVerifyResult {
    let sourceSummary = run.diagnosisSummary

    do {
      let execution = try await executeBuild(resolvedContext)
      let summary = DiagnosisBuildWorkflow.buildSummary(from: execution)
      let status: WorkflowStatus = execution.succeeded ? .succeeded : .failed
      let timestamp = now()
      let attempt = WorkflowAttemptRecord(
        attemptId: attemptId,
        attemptNumber: attemptNumber,
        rerunOfAttemptId: sourceAttemptId,
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
        attempt: attempt,
        resolvedContext: resolvedContext,
        diagnosisSummary: summary,
        testDiagnosisSummary: run.testDiagnosisSummary,
        environmentPreflight: run.environmentPreflight,
        evidence: run.evidence
          + DiagnosisBuildWorkflow.evidence(
            for: execution,
            attempt: attempt,
            phase: .diagnosisBuild
          ),
        attemptHistory: run.backfilledAttemptHistory + [
          WorkflowAttemptSnapshot(
            attempt: attempt,
            phase: .diagnosisBuild,
            status: status,
            resolvedContext: resolvedContext,
            diagnosisSummary: summary,
            testDiagnosisSummary: run.testDiagnosisSummary,
            recordedAt: timestamp
          )
        ],
        actionHistory: run.actionHistory + [
          WorkflowActionRecord(
            kind: .verifyStarted,
            phase: .diagnosisBuild,
            attemptId: attempt.attemptId,
            timestamp: attempt.startedAt
          ),
          WorkflowActionRecord(
            kind: .buildCompleted,
            phase: .diagnosisBuild,
            attemptId: attempt.attemptId,
            timestamp: timestamp,
            detail: status == .succeeded ? "Verify build succeeded" : "Verify build failed"
          ),
          WorkflowActionRecord(
            kind: .evidenceCaptured,
            phase: .diagnosisBuild,
            attemptId: attempt.attemptId,
            timestamp: timestamp,
            detail: "Verification build evidence captured"
          ),
          WorkflowActionRecord(
            kind: .verifyCompleted,
            phase: .diagnosisBuild,
            attemptId: attempt.attemptId,
            timestamp: timestamp
          ),
        ]
      )
      return persistedVerifyResult(
        updatedRun: updatedRun,
        sourceAttemptId: sourceAttemptId,
        outcome: classifyBuildOutcome(
          status: status,
          sourceSummary: sourceSummary,
          rerunSummary: summary,
          evidence: updatedRun.evidence(forAttemptId: attemptId)
        )
      )
    } catch {
      let classifiedFailure = Self.classifyBuildExecutionFailure(message: "\(error)")
      let timestamp = now()
      let attempt = WorkflowAttemptRecord(
        attemptId: attemptId,
        attemptNumber: attemptNumber,
        rerunOfAttemptId: sourceAttemptId,
        phase: .diagnosisBuild,
        startedAt: timestamp,
        status: classifiedFailure.status
      )
      let updatedRun = WorkflowRunRecord(
        schemaVersion: WorkflowRunRecord.currentSchemaVersion,
        runId: run.runId,
        workflow: run.workflow,
        phase: .diagnosisBuild,
        status: classifiedFailure.status,
        createdAt: run.createdAt,
        updatedAt: timestamp,
        attempt: attempt,
        resolvedContext: resolvedContext,
        diagnosisSummary: nil,
        testDiagnosisSummary: run.testDiagnosisSummary,
        environmentPreflight: run.environmentPreflight,
        evidence: run.evidence
          + DiagnosisBuildWorkflow.unavailableEvidence(
            for: attempt,
            phase: .diagnosisBuild
          ),
        attemptHistory: run.backfilledAttemptHistory + [
          WorkflowAttemptSnapshot(
            attempt: attempt,
            phase: .diagnosisBuild,
            status: classifiedFailure.status,
            resolvedContext: resolvedContext,
            testDiagnosisSummary: run.testDiagnosisSummary,
            recordedAt: timestamp
          )
        ],
        actionHistory: run.actionHistory + [
          WorkflowActionRecord(
            kind: .verifyStarted,
            phase: .diagnosisBuild,
            attemptId: attempt.attemptId,
            timestamp: attempt.startedAt
          ),
          WorkflowActionRecord(
            kind: .buildCompleted,
            phase: .diagnosisBuild,
            attemptId: attempt.attemptId,
            timestamp: timestamp,
            detail: "Verify build execution failed"
          ),
          WorkflowActionRecord(
            kind: .verifyCompleted,
            phase: .diagnosisBuild,
            attemptId: attempt.attemptId,
            timestamp: timestamp,
            detail: "Verification failed"
          ),
        ]
      )
      return persistedVerifyResult(
        updatedRun: updatedRun,
        sourceAttemptId: sourceAttemptId,
        outcome: classifiedFailure.status == .unsupported ? .blocked : .failed,
        failure: WorkflowFailure(
          field: classifiedFailure.field,
          classification: classifiedFailure.classification,
          message: classifiedFailure.message,
          observed: ObservedFailureEvidence(summary: classifiedFailure.message),
          inferred: InferredFailureConclusion(
            summary:
              "Build execution failed during verification rerun; the build environment or project configuration may need attention."
          ),
          recoverability: classifiedFailure.classification.recoverability
        )
      )
    }
  }

  private func verifyTest(
    run: WorkflowRunRecord,
    sourceAttemptId: String,
    resolvedContext: ResolvedWorkflowContext,
    attemptId: String,
    attemptNumber: Int
  ) async -> DiagnosisVerifyResult {
    let sourceSummary = run.testDiagnosisSummary

    do {
      let execution = try await executeTest(resolvedContext)
      let timestamp = now()

      if let blocker = Self.classifyExecutionBlocker(execution) {
        let attempt = WorkflowAttemptRecord(
          attemptId: attemptId,
          attemptNumber: attemptNumber,
          rerunOfAttemptId: sourceAttemptId,
          phase: .diagnosisTest,
          startedAt: timestamp,
          status: blocker.status
        )
        let summary = DiagnosisTestWorkflow.buildSummary(from: execution)
        let updatedRun = WorkflowRunRecord(
          schemaVersion: WorkflowRunRecord.currentSchemaVersion,
          runId: run.runId,
          workflow: run.workflow,
          phase: .diagnosisTest,
          status: blocker.status,
          createdAt: run.createdAt,
          updatedAt: timestamp,
          attempt: attempt,
          resolvedContext: resolvedContext,
          diagnosisSummary: run.diagnosisSummary,
          testDiagnosisSummary: summary,
          environmentPreflight: run.environmentPreflight,
          evidence: run.evidence
            + DiagnosisTestWorkflow.evidence(
              for: execution,
              attempt: attempt,
              phase: .diagnosisTest
            ),
          attemptHistory: run.backfilledAttemptHistory + [
            WorkflowAttemptSnapshot(
              attempt: attempt,
              phase: .diagnosisTest,
              status: blocker.status,
              resolvedContext: resolvedContext,
              diagnosisSummary: run.diagnosisSummary,
              testDiagnosisSummary: summary,
              recordedAt: timestamp
            )
          ],
          actionHistory: run.actionHistory + [
            WorkflowActionRecord(
              kind: .verifyStarted,
              phase: .diagnosisTest,
              attemptId: attempt.attemptId,
              timestamp: attempt.startedAt
            ),
            WorkflowActionRecord(
              kind: .testCompleted,
              phase: .diagnosisTest,
              attemptId: attempt.attemptId,
              timestamp: timestamp,
              detail: "Verify test execution blocked"
            ),
            WorkflowActionRecord(
              kind: .evidenceCaptured,
              phase: .diagnosisTest,
              attemptId: attempt.attemptId,
              timestamp: timestamp,
              detail: "Verification test evidence captured"
            ),
            WorkflowActionRecord(
              kind: .verifyCompleted,
              phase: .diagnosisTest,
              attemptId: attempt.attemptId,
              timestamp: timestamp,
              detail: "Verification blocked"
            ),
          ]
        )
        return persistedVerifyResult(
          updatedRun: updatedRun,
          sourceAttemptId: sourceAttemptId,
          outcome: .blocked,
          failure: WorkflowFailure(
            field: blocker.field,
            classification: blocker.classification,
            message: blocker.message,
            options: blocker.options,
            observed: ObservedFailureEvidence(summary: blocker.message),
            inferred: InferredFailureConclusion(
              summary:
                "Test execution was blocked before any test results could be collected; the test environment or configuration may need attention."
            ),
            recoverability: blocker.classification.recoverability
          )
        )
      }

      let summary = DiagnosisTestWorkflow.buildSummary(from: execution)
      let status: WorkflowStatus = execution.succeeded ? .succeeded : .failed
      let attempt = WorkflowAttemptRecord(
        attemptId: attemptId,
        attemptNumber: attemptNumber,
        rerunOfAttemptId: sourceAttemptId,
        phase: .diagnosisTest,
        startedAt: timestamp,
        status: status
      )
      let updatedRun = WorkflowRunRecord(
        schemaVersion: WorkflowRunRecord.currentSchemaVersion,
        runId: run.runId,
        workflow: run.workflow,
        phase: .diagnosisTest,
        status: status,
        createdAt: run.createdAt,
        updatedAt: timestamp,
        attempt: attempt,
        resolvedContext: resolvedContext,
        diagnosisSummary: run.diagnosisSummary,
        testDiagnosisSummary: summary,
        environmentPreflight: run.environmentPreflight,
        evidence: run.evidence
          + DiagnosisTestWorkflow.evidence(
            for: execution,
            attempt: attempt,
            phase: .diagnosisTest
          ),
        attemptHistory: run.backfilledAttemptHistory + [
          WorkflowAttemptSnapshot(
            attempt: attempt,
            phase: .diagnosisTest,
            status: status,
            resolvedContext: resolvedContext,
            diagnosisSummary: run.diagnosisSummary,
            testDiagnosisSummary: summary,
            recordedAt: timestamp
          )
        ],
        actionHistory: run.actionHistory + [
          WorkflowActionRecord(
            kind: .verifyStarted,
            phase: .diagnosisTest,
            attemptId: attempt.attemptId,
            timestamp: attempt.startedAt
          ),
          WorkflowActionRecord(
            kind: .testCompleted,
            phase: .diagnosisTest,
            attemptId: attempt.attemptId,
            timestamp: timestamp,
            detail: status == .succeeded ? "Verify tests succeeded" : "Verify tests failed"
          ),
          WorkflowActionRecord(
            kind: .evidenceCaptured,
            phase: .diagnosisTest,
            attemptId: attempt.attemptId,
            timestamp: timestamp,
            detail: "Verification test evidence captured"
          ),
          WorkflowActionRecord(
            kind: .verifyCompleted,
            phase: .diagnosisTest,
            attemptId: attempt.attemptId,
            timestamp: timestamp
          ),
        ]
      )
      return persistedVerifyResult(
        updatedRun: updatedRun,
        sourceAttemptId: sourceAttemptId,
        outcome: classifyTestOutcome(
          status: status,
          sourceSummary: sourceSummary,
          rerunSummary: summary,
          evidence: updatedRun.evidence(forAttemptId: attemptId)
        )
      )
    } catch {
      let classifiedFailure = Self.classifyExecutionFailure(message: "\(error)")
      let timestamp = now()
      let attempt = WorkflowAttemptRecord(
        attemptId: attemptId,
        attemptNumber: attemptNumber,
        rerunOfAttemptId: sourceAttemptId,
        phase: .diagnosisTest,
        startedAt: timestamp,
        status: classifiedFailure.status
      )
      let updatedRun = WorkflowRunRecord(
        schemaVersion: WorkflowRunRecord.currentSchemaVersion,
        runId: run.runId,
        workflow: run.workflow,
        phase: .diagnosisTest,
        status: classifiedFailure.status,
        createdAt: run.createdAt,
        updatedAt: timestamp,
        attempt: attempt,
        resolvedContext: resolvedContext,
        diagnosisSummary: run.diagnosisSummary,
        testDiagnosisSummary: nil,
        environmentPreflight: run.environmentPreflight,
        evidence: run.evidence
          + DiagnosisTestWorkflow.unavailableEvidence(
            for: attempt,
            phase: .diagnosisTest,
            failureMessage: classifiedFailure.message
          ),
        attemptHistory: run.backfilledAttemptHistory + [
          WorkflowAttemptSnapshot(
            attempt: attempt,
            phase: .diagnosisTest,
            status: classifiedFailure.status,
            resolvedContext: resolvedContext,
            diagnosisSummary: run.diagnosisSummary,
            recordedAt: timestamp
          )
        ],
        actionHistory: run.actionHistory + [
          WorkflowActionRecord(
            kind: .verifyStarted,
            phase: .diagnosisTest,
            attemptId: attempt.attemptId,
            timestamp: attempt.startedAt
          ),
          WorkflowActionRecord(
            kind: .testCompleted,
            phase: .diagnosisTest,
            attemptId: attempt.attemptId,
            timestamp: timestamp,
            detail: "Verify test execution failed"
          ),
          WorkflowActionRecord(
            kind: .verifyCompleted,
            phase: .diagnosisTest,
            attemptId: attempt.attemptId,
            timestamp: timestamp,
            detail: "Verification failed"
          ),
        ]
      )
      return persistedVerifyResult(
        updatedRun: updatedRun,
        sourceAttemptId: sourceAttemptId,
        outcome: classifiedFailure.status == .unsupported ? .blocked : .failed,
        failure: WorkflowFailure(
          field: classifiedFailure.field,
          classification: classifiedFailure.classification,
          message: classifiedFailure.message,
          options: classifiedFailure.options,
          observed: ObservedFailureEvidence(summary: classifiedFailure.message),
          inferred: InferredFailureConclusion(
            summary:
              "Test execution failed during verification rerun; the test environment or project configuration may need attention."
          ),
          recoverability: classifiedFailure.classification.recoverability
        )
      )
    }
  }

  private func persistedVerifyResult(
    updatedRun: WorkflowRunRecord,
    sourceAttemptId: String,
    outcome: DiagnosisVerifyOutcome,
    failure: WorkflowFailure? = nil
  ) -> DiagnosisVerifyResult {
    do {
      let persistedURL = try persistRun(updatedRun)
      return DiagnosisVerifyResult(
        phase: updatedRun.phase,
        status: updatedRun.status,
        outcome: outcome,
        runId: updatedRun.runId,
        attemptId: updatedRun.attempt.attemptId,
        sourceAttemptId: sourceAttemptId,
        resolvedContext: updatedRun.resolvedContext,
        summary: DiagnosisStatusWorkflow.summary(for: updatedRun),
        buildSummary: updatedRun.diagnosisSummary,
        testSummary: updatedRun.testDiagnosisSummary,
        evidence: updatedRun.evidence(forAttemptId: updatedRun.attempt.attemptId),
        failure: failure,
        persistedRunPath: persistedURL.path
      )
    } catch {
      return DiagnosisVerifyResult(
        phase: updatedRun.phase,
        status: updatedRun.status,
        outcome: outcome,
        runId: updatedRun.runId,
        attemptId: updatedRun.attempt.attemptId,
        sourceAttemptId: sourceAttemptId,
        resolvedContext: updatedRun.resolvedContext,
        summary: DiagnosisStatusWorkflow.summary(for: updatedRun),
        buildSummary: updatedRun.diagnosisSummary,
        testSummary: updatedRun.testDiagnosisSummary,
        evidence: updatedRun.evidence(forAttemptId: updatedRun.attempt.attemptId),
        failure: WorkflowFailure(
          field: .workflow,
          classification: .executionFailed,
          message: "Verification reran, but xcforge could not persist the new attempt: \(error)",
          observed: ObservedFailureEvidence(
            summary: "Verification reran, but xcforge could not persist the new attempt.",
            detail: "\(error)"
          ),
          inferred: InferredFailureConclusion(
            summary:
              "The verification completed but its results could not be saved; a filesystem or permissions issue may be preventing persistence."
          ),
          recoverability: .retryAfterFix
        ),
        persistedRunPath: nil
      )
    }
  }

  private func resolveContext(
    for run: WorkflowRunRecord,
    request: DiagnosisVerifyRequest
  ) async throws -> ResolvedWorkflowContext {
    let base = run.resolvedContext
    let effectiveProject =
      try Self.resolveOverride(request.project, field: .project) ?? base.project
    let effectiveScheme = try Self.resolveOverride(request.scheme, field: .scheme) ?? base.scheme
    let effectiveSimulator =
      try Self.resolveOverride(request.simulator, field: .simulator) ?? base.simulator
    let effectiveConfiguration =
      try Self.resolveOverride(request.configuration, field: .build) ?? base.configuration

    let changed =
      effectiveProject != base.project
      || effectiveScheme != base.scheme
      || effectiveSimulator != base.simulator
      || effectiveConfiguration != base.configuration

    guard changed else {
      return base
    }

    do {
      let app = try await resolveAppContext(
        effectiveProject,
        effectiveScheme,
        effectiveSimulator,
        effectiveConfiguration
      )
      return ResolvedWorkflowContext(
        project: effectiveProject,
        scheme: effectiveScheme,
        simulator: effectiveSimulator,
        configuration: effectiveConfiguration,
        app: app
      )
    } catch {
      let classification = Self.classifyAppContextError(error)
      throw DiagnosisVerifyWorkflowError(
        status: classification == .unsupportedContext ? .unsupported : .failed,
        field: .app,
        classification: classification,
        message: "\(error)"
      )
    }
  }

  private func classifyBuildOutcome(
    status: WorkflowStatus,
    sourceSummary: BuildDiagnosisSummary?,
    rerunSummary: BuildDiagnosisSummary?,
    evidence: [WorkflowEvidenceRecord]
  ) -> DiagnosisVerifyOutcome {
    if status == .succeeded {
      return hasSupportingEvidence(evidence, summaryAvailable: rerunSummary != nil)
        ? .verified : .partial
    }
    if status == .failed, Self.sameBuildFailure(sourceSummary, rerunSummary) {
      return .unchanged
    }
    return .failed
  }

  private func classifyTestOutcome(
    status: WorkflowStatus,
    sourceSummary: TestDiagnosisSummary?,
    rerunSummary: TestDiagnosisSummary?,
    evidence: [WorkflowEvidenceRecord]
  ) -> DiagnosisVerifyOutcome {
    if status == .succeeded {
      return hasSupportingEvidence(evidence, summaryAvailable: rerunSummary != nil)
        ? .verified : .partial
    }
    if status == .failed, Self.sameTestFailure(sourceSummary, rerunSummary) {
      return .unchanged
    }
    return .failed
  }

  private func hasSupportingEvidence(
    _ evidence: [WorkflowEvidenceRecord],
    summaryAvailable: Bool
  ) -> Bool {
    guard summaryAvailable else {
      return false
    }
    return evidence.contains { record in
      record.availability == .available && record.kind != .buildSummary
        && record.kind != .testSummary
    }
  }

  private static func validate(_ run: WorkflowRunRecord) throws {
    guard run.workflow == .diagnosis else {
      throw DiagnosisVerifyWorkflowError(
        status: .failed,
        field: .run,
        classification: .invalidRunState,
        message: "Run \(run.runId) is not a diagnosis workflow run."
      )
    }

    guard run.phase == .diagnosisBuild || run.phase == .diagnosisTest else {
      throw DiagnosisVerifyWorkflowError(
        status: .failed,
        field: .run,
        classification: .invalidRunState,
        message:
          "Run \(run.runId) is in phase \(run.phase.rawValue); rerun validation requires a persisted build or test diagnosis."
      )
    }

    guard run.status == .failed || run.status == .partial || run.status == .unsupported else {
      throw DiagnosisVerifyWorkflowError(
        status: .failed,
        field: .run,
        classification: .invalidRunState,
        message:
          "Run \(run.runId) has status \(run.status.rawValue); rerun validation currently requires a failed, partial, or unsupported diagnosis result."
      )
    }
  }

  private static func sameBuildFailure(
    _ lhs: BuildDiagnosisSummary?,
    _ rhs: BuildDiagnosisSummary?
  ) -> Bool {
    guard let lhsObserved = lhs?.observedEvidence,
      let rhsObserved = rhs?.observedEvidence
    else {
      return false
    }
    return lhsObserved.primarySignal == rhsObserved.primarySignal
      && lhsObserved.additionalIssueCount == rhsObserved.additionalIssueCount
      && lhsObserved.errorCount == rhsObserved.errorCount
      && lhsObserved.warningCount == rhsObserved.warningCount
      && lhsObserved.analyzerWarningCount == rhsObserved.analyzerWarningCount
  }

  private static func sameTestFailure(
    _ lhs: TestDiagnosisSummary?,
    _ rhs: TestDiagnosisSummary?
  ) -> Bool {
    guard let lhsObserved = lhs?.observedEvidence,
      let rhsObserved = rhs?.observedEvidence
    else {
      return false
    }
    return lhsObserved.primaryFailure == rhsObserved.primaryFailure
      && lhsObserved.additionalFailureCount == rhsObserved.additionalFailureCount
      && lhsObserved.totalTestCount == rhsObserved.totalTestCount
      && lhsObserved.failedTestCount == rhsObserved.failedTestCount
      && lhsObserved.passedTestCount == rhsObserved.passedTestCount
      && lhsObserved.skippedTestCount == rhsObserved.skippedTestCount
      && lhsObserved.expectedFailureCount == rhsObserved.expectedFailureCount
  }

  private static func classifyBuildExecutionFailure(message: String) -> DiagnosisVerifyWorkflowError
  {
    let lowercaseMessage = message.lowercased()
    let unsupportedPatterns = [
      "unable to find a destination matching",
      "unsupported destination",
      "no available devices",
      "platform not currently installed",
      "failed to boot",
      "simulator device returned an error",
      "destination specifier",
      "destination is unavailable",
    ]
    let isUnsupported = unsupportedPatterns.contains { lowercaseMessage.contains($0) }

    return DiagnosisVerifyWorkflowError(
      status: isUnsupported ? .unsupported : .failed,
      field: isUnsupported ? .simulator : .build,
      classification: isUnsupported ? .unsupportedContext : .executionFailed,
      message: message
    )
  }

  private static func classifyExecutionFailure(message: String) -> DiagnosisVerifyWorkflowError {
    let lowercaseMessage = message.lowercased()
    let unsupportedPatterns = [
      "unable to find a destination matching",
      "unsupported destination",
      "no available devices",
      "platform not currently installed",
      "failed to boot",
      "simulator device returned an error",
      "destination specifier",
      "destination is unavailable",
    ]
    let isUnsupported = unsupportedPatterns.contains { lowercaseMessage.contains($0) }

    return DiagnosisVerifyWorkflowError(
      status: isUnsupported ? .unsupported : .failed,
      field: isUnsupported ? .simulator : .test,
      classification: isUnsupported ? .unsupportedContext : .executionFailed,
      message: message
    )
  }

  private static func classifyExecutionBlocker(
    _ execution: TestTools.TestDiagnosisExecution
  ) -> DiagnosisVerifyWorkflowError? {
    guard !execution.succeeded, execution.failures.isEmpty else {
      return nil
    }

    return classifyExecutionFailure(
      message: execution.executionFailureMessage
        ?? "Test execution failed before xcforge could extract a primary failing test."
    )
  }

  private static func classifyAppContextError(_ error: Error) -> WorkflowFailureClassification {
    let message = "\(error)".lowercased()
    if message.contains("unsupported")
      || message.contains("did not contain product_bundle_identifier")
      || message.contains("did not contain an app product path")
    {
      return .unsupportedContext
    }
    return .resolutionFailed
  }

  private func persistResolutionFailure(
    run: WorkflowRunRecord,
    sourceAttemptId: String,
    attemptId: String,
    attemptNumber: Int,
    failure: DiagnosisVerifyWorkflowError
  ) -> DiagnosisVerifyResult {
    let timestamp = now()
    let attempt = WorkflowAttemptRecord(
      attemptId: attemptId,
      attemptNumber: attemptNumber,
      rerunOfAttemptId: sourceAttemptId,
      phase: run.phase,
      startedAt: timestamp,
      status: failure.status
    )
    let updatedRun = WorkflowRunRecord(
      schemaVersion: WorkflowRunRecord.currentSchemaVersion,
      runId: run.runId,
      workflow: run.workflow,
      phase: run.phase,
      status: failure.status,
      createdAt: run.createdAt,
      updatedAt: timestamp,
      attempt: attempt,
      resolvedContext: run.resolvedContext,
      diagnosisSummary: run.phase == .diagnosisBuild ? nil : run.diagnosisSummary,
      testDiagnosisSummary: run.phase == .diagnosisTest ? nil : run.testDiagnosisSummary,
      environmentPreflight: run.environmentPreflight,
      evidence: run.phase == .diagnosisBuild
        ? run.evidence
          + DiagnosisBuildWorkflow.unavailableEvidence(for: attempt, phase: .diagnosisBuild)
        : run.evidence
          + DiagnosisTestWorkflow.unavailableEvidence(
            for: attempt,
            phase: .diagnosisTest,
            failureMessage: failure.message
          ),
      attemptHistory: run.backfilledAttemptHistory + [
        WorkflowAttemptSnapshot(
          attempt: attempt,
          phase: run.phase,
          status: failure.status,
          resolvedContext: run.resolvedContext,
          diagnosisSummary: run.phase == .diagnosisBuild ? nil : run.diagnosisSummary,
          testDiagnosisSummary: run.phase == .diagnosisTest ? nil : run.testDiagnosisSummary,
          recordedAt: timestamp
        )
      ],
      actionHistory: run.actionHistory + [
        WorkflowActionRecord(
          kind: .verifyStarted,
          phase: run.phase,
          attemptId: attempt.attemptId,
          timestamp: attempt.startedAt
        ),
        WorkflowActionRecord(
          kind: .verifyCompleted,
          phase: run.phase,
          attemptId: attempt.attemptId,
          timestamp: timestamp,
          detail: "Verification resolution failed: \(failure.message)"
        ),
      ]
    )
    return persistedVerifyResult(
      updatedRun: updatedRun,
      sourceAttemptId: sourceAttemptId,
      outcome: failure.status == .unsupported ? .blocked : .failed,
      failure: WorkflowFailure(
        field: failure.field,
        classification: failure.classification,
        message: failure.message,
        options: failure.options,
        observed: ObservedFailureEvidence(summary: failure.message),
        inferred: nil,
        recoverability: failure.classification.recoverability
      )
    )
  }

  private static func resolveOverride(
    _ rawValue: String?,
    field: ContextField
  ) throws -> String? {
    guard let rawValue else {
      return nil
    }
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw DiagnosisVerifyWorkflowError(
        status: .failed,
        field: field,
        classification: .resolutionFailed,
        message: "Override for \(field.rawValue) must not be empty."
      )
    }
    return trimmed
  }
}

private struct DiagnosisVerifyWorkflowError: Error {
  let status: WorkflowStatus
  let field: ContextField
  let classification: WorkflowFailureClassification
  let message: String
  let options: [String]

  init(
    status: WorkflowStatus,
    field: ContextField,
    classification: WorkflowFailureClassification,
    message: String,
    options: [String] = []
  ) {
    self.status = status
    self.field = field
    self.classification = classification
    self.message = message
    self.options = options
  }
}

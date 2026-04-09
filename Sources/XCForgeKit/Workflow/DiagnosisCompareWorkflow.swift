import Foundation

public struct DiagnosisCompareWorkflow: Sendable {
  typealias RunPath = @Sendable (String) -> URL

  private let resolver: RunResolver
  private let runPath: RunPath

  public init() {
    self.init(
      resolver: RunResolver(
        strategy: .activeOrRecent,
        loadRun: { runId in try RunStore().load(runId: runId) },
        loadLatestActiveRun: { try RunStore().latestActiveDiagnosisRun() },
        loadLatestRun: { try RunStore().latestDiagnosisRun() }
      ),
      runPath: { runId in RunStore().runFileURL(runId: runId) }
    )
  }

  init(
    resolver: RunResolver,
    runPath: @escaping RunPath
  ) {
    self.resolver = resolver
    self.runPath = runPath
  }

  public func compare(request: DiagnosisCompareRequest) async -> DiagnosisCompareResult {
    do {
      let run = try resolveRun(for: request)
      try Self.validate(run)

      let currentPhase = run.phase
      let currentSnapshot =
        run.attemptSnapshot(forAttemptId: run.attempt.attemptId, phase: currentPhase)
        ?? run.latestSnapshot

      guard
        let sourceSnapshot = resolveSourceSnapshot(
          for: currentSnapshot,
          in: run
        )
      else {
        throw DiagnosisCompareWorkflowError(
          field: .run,
          classification: .invalidRunState,
          message: "Run \(run.runId) does not include a linked rerun attempt to compare."
        )
      }

      let priorAttempt = makeSnapshot(
        from: sourceSnapshot,
        evidence: run.evidence(forAttemptId: sourceSnapshot.attempt.attemptId)
      )
      let currentAttempt = makeSnapshot(
        from: currentSnapshot,
        evidence: run.evidence(forAttemptId: currentSnapshot.attempt.attemptId)
      )

      guard currentAttempt.phase == priorAttempt.phase else {
        throw DiagnosisCompareWorkflowError(
          field: .run,
          classification: .invalidRunState,
          message:
            "Run \(run.runId) compares phase \(priorAttempt.phase.rawValue) against \(currentAttempt.phase.rawValue); comparison requires a matched build or test rerun."
        )
      }

      let comparison = compare(
        priorAttempt: priorAttempt,
        currentAttempt: currentAttempt
      )

      return DiagnosisCompareResult(
        phase: currentAttempt.phase,
        status: currentAttempt.status,
        outcome: comparison.outcome,
        runId: run.runId,
        attemptId: currentAttempt.attemptId,
        sourceAttemptId: priorAttempt.attemptId,
        priorAttempt: priorAttempt,
        currentAttempt: currentAttempt,
        changedEvidence: comparison.changedEvidence,
        unchangedBlockers: comparison.unchangedBlockers,
        failure: nil,
        persistedRunPath: runPath(run.runId).path
      )
    } catch let error as DiagnosisCompareWorkflowError {
      return DiagnosisCompareResult(
        phase: nil,
        status: nil,
        outcome: nil,
        runId: request.runId,
        attemptId: nil,
        sourceAttemptId: nil,
        priorAttempt: nil,
        currentAttempt: nil,
        changedEvidence: [],
        unchangedBlockers: [],
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
      return DiagnosisCompareResult(
        phase: nil,
        status: nil,
        outcome: nil,
        runId: request.runId,
        attemptId: nil,
        sourceAttemptId: nil,
        priorAttempt: nil,
        currentAttempt: nil,
        changedEvidence: [],
        unchangedBlockers: [],
        failure: WorkflowFailure(
          field: .workflow,
          classification: .executionFailed,
          message: "\(error)",
          observed: ObservedFailureEvidence(summary: "\(error)"),
          inferred: InferredFailureConclusion(
            summary:
              "An unexpected error occurred during comparison; the underlying issue may be transient or environmental."
          ),
          recoverability: .retryAfterFix
        ),
        persistedRunPath: nil
      )
    }
  }

  private func resolveSourceSnapshot(
    for currentSnapshot: WorkflowAttemptSnapshot,
    in run: WorkflowRunRecord
  ) -> WorkflowAttemptSnapshot? {
    guard
      let sourceAttemptId = currentSnapshot.attempt.rerunOfAttemptId?.trimmingCharacters(
        in: .whitespacesAndNewlines),
      !sourceAttemptId.isEmpty
    else {
      return nil
    }

    guard
      var sourceSnapshot = run.attemptSnapshot(
        forAttemptId: sourceAttemptId,
        phase: currentSnapshot.phase
      )
    else {
      return nil
    }

    while let parentAttemptId = sourceSnapshot.attempt.rerunOfAttemptId?.trimmingCharacters(
      in: .whitespacesAndNewlines),
      !parentAttemptId.isEmpty,
      let parentSnapshot = run.attemptSnapshot(
        forAttemptId: parentAttemptId,
        phase: currentSnapshot.phase
      )
    {
      sourceSnapshot = parentSnapshot
    }

    return sourceSnapshot
  }

  private func resolveRun(for request: DiagnosisCompareRequest) throws -> WorkflowRunRecord {
    switch resolver.resolve(request.runId) {
    case .success(let run):
      return run
    case .failure(let failure):
      throw Self.mapResolutionFailure(failure)
    }
  }

  private static func mapResolutionFailure(_ failure: RunResolutionFailure) -> Error {
    switch failure {
    case .emptyRunId:
      return DiagnosisCompareWorkflowError(
        field: .run, classification: .notFound, message: "Run ID must not be empty.")
    case .notFound(let runId):
      return DiagnosisCompareWorkflowError(
        field: .run, classification: .notFound,
        message: "No diagnosis run was found for run ID \(runId).")
    case .noRunsAvailable:
      return DiagnosisCompareWorkflowError(
        field: .run, classification: .notFound,
        message: "No diagnosis runs are available to compare.")
    case .runStillInProgress(let runId):
      return DiagnosisCompareWorkflowError(
        field: .run, classification: .invalidRunState,
        message: "Run \(runId) is still in progress; final results require a completed diagnosis.")
    case .loadFailed(let error):
      return DiagnosisCompareWorkflowError(
        field: .run, classification: .executionFailed, message: "\(error)")
    }
  }

  private static func validate(_ run: WorkflowRunRecord) throws {
    guard run.workflow == .diagnosis else {
      throw DiagnosisCompareWorkflowError(
        field: .run,
        classification: .invalidRunState,
        message: "Run \(run.runId) is not a diagnosis workflow run."
      )
    }

    guard
      run.phase == .diagnosisBuild || run.phase == .diagnosisTest || run.phase == .diagnosisRuntime
    else {
      throw DiagnosisCompareWorkflowError(
        field: .run,
        classification: .invalidRunState,
        message:
          "Run \(run.runId) is in phase \(run.phase.rawValue); comparison requires a completed build, test, or runtime diagnosis."
      )
    }

    guard run.status != .inProgress else {
      throw DiagnosisCompareWorkflowError(
        field: .run,
        classification: .invalidRunState,
        message: "Run \(run.runId) is still in progress; comparison requires a completed rerun."
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
        headline:
          "Diagnosis run is in phase \(snapshot.phase.rawValue) with status \(snapshot.status.rawValue).",
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
        headline:
          "Diagnosis run is in phase \(snapshot.phase.rawValue) with status \(snapshot.status.rawValue).",
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
        headline:
          "Diagnosis run is in phase \(snapshot.phase.rawValue) with status \(snapshot.status.rawValue).",
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
        headline:
          "Diagnosis run is in phase \(snapshot.phase.rawValue) with status \(snapshot.status.rawValue).",
        detail: "No persisted runtime diagnosis summary is available for this attempt."
      )
    }
  }

  private func compare(
    priorAttempt: DiagnosisCompareAttemptSnapshot,
    currentAttempt: DiagnosisCompareAttemptSnapshot
  ) -> (
    outcome: DiagnosisCompareOutcome, changedEvidence: [DiagnosisComparisonChange],
    unchangedBlockers: [String]
  ) {
    switch currentAttempt.phase {
    case .diagnosisBuild:
      return compareBuild(
        priorStatus: priorAttempt.status,
        currentStatus: currentAttempt.status,
        priorSummary: priorAttempt.diagnosisSummary,
        currentSummary: currentAttempt.diagnosisSummary,
        currentLabel: currentAttempt.summary,
        priorEvidence: priorAttempt.evidence,
        currentEvidence: currentAttempt.evidence
      )
    case .diagnosisTest:
      return compareTest(
        priorStatus: priorAttempt.status,
        currentStatus: currentAttempt.status,
        priorSummary: priorAttempt.testDiagnosisSummary,
        currentSummary: currentAttempt.testDiagnosisSummary,
        currentLabel: currentAttempt.summary,
        priorEvidence: priorAttempt.evidence,
        currentEvidence: currentAttempt.evidence
      )
    case .diagnosisStart:
      return (
        .unchanged,
        [
          DiagnosisComparisonChange(
            field: "Overall status",
            priorValue: priorAttempt.status.rawValue,
            currentValue: currentAttempt.status.rawValue
          )
        ],
        [currentAttempt.summary.detail ?? currentAttempt.summary.headline]
      )
    case .diagnosisRuntime:
      return (
        .unchanged,
        [
          DiagnosisComparisonChange(
            field: "Runtime status",
            priorValue: priorAttempt.status.rawValue,
            currentValue: currentAttempt.status.rawValue
          )
        ],
        [currentAttempt.summary.detail ?? currentAttempt.summary.headline]
      )
    }
  }

  private func compareBuild(
    priorStatus: WorkflowStatus,
    currentStatus: WorkflowStatus,
    priorSummary: BuildDiagnosisSummary?,
    currentSummary: BuildDiagnosisSummary?,
    currentLabel: DiagnosisStatusSummary,
    priorEvidence: [WorkflowEvidenceRecord],
    currentEvidence: [WorkflowEvidenceRecord]
  ) -> (
    outcome: DiagnosisCompareOutcome, changedEvidence: [DiagnosisComparisonChange],
    unchangedBlockers: [String]
  ) {
    let changes =
      buildComparisonChanges(
        priorStatus: priorStatus,
        currentStatus: currentStatus,
        priorSummary: priorSummary,
        currentSummary: currentSummary
      ) + evidenceComparisonChanges(priorEvidence: priorEvidence, currentEvidence: currentEvidence)
    let outcome = classifyComparison(
      priorStatus: priorStatus,
      currentStatus: currentStatus,
      priorSummary: priorSummary,
      currentSummary: currentSummary,
      hasMeaningfulChanges: !changes.isEmpty
    )
    let blockers = buildBlockers(
      priorStatus: priorStatus,
      currentStatus: currentStatus,
      priorSummary: priorSummary,
      from: currentSummary,
      fallback: currentLabel
    )
    return (outcome, changes, blockers)
  }

  private func compareTest(
    priorStatus: WorkflowStatus,
    currentStatus: WorkflowStatus,
    priorSummary: TestDiagnosisSummary?,
    currentSummary: TestDiagnosisSummary?,
    currentLabel: DiagnosisStatusSummary,
    priorEvidence: [WorkflowEvidenceRecord],
    currentEvidence: [WorkflowEvidenceRecord]
  ) -> (
    outcome: DiagnosisCompareOutcome, changedEvidence: [DiagnosisComparisonChange],
    unchangedBlockers: [String]
  ) {
    let changes =
      testComparisonChanges(
        priorStatus: priorStatus,
        currentStatus: currentStatus,
        priorSummary: priorSummary,
        currentSummary: currentSummary
      ) + evidenceComparisonChanges(priorEvidence: priorEvidence, currentEvidence: currentEvidence)
    let outcome = classifyComparison(
      priorStatus: priorStatus,
      currentStatus: currentStatus,
      priorSummary: priorSummary,
      currentSummary: currentSummary,
      hasMeaningfulChanges: !changes.isEmpty
    )
    let blockers = testBlockers(
      priorStatus: priorStatus,
      currentStatus: currentStatus,
      priorSummary: priorSummary,
      from: currentSummary,
      fallback: currentLabel
    )
    return (outcome, changes, blockers)
  }

  private func classifyComparison(
    priorStatus: WorkflowStatus,
    currentStatus: WorkflowStatus,
    priorSummary: BuildDiagnosisSummary?,
    currentSummary: BuildDiagnosisSummary?,
    hasMeaningfulChanges: Bool
  ) -> DiagnosisCompareOutcome {
    let priorRank = statusRank(priorStatus)
    let currentRank = statusRank(currentStatus)

    if currentStatus == .partial, priorRank < currentRank {
      return .partial
    }
    if currentRank > priorRank {
      return .improved
    }
    if currentRank < priorRank {
      return .regressed
    }

    if priorStatus == currentStatus,
      let priorSummary,
      let currentSummary,
      priorSummary == currentSummary
    {
      return .unchanged
    }

    guard hasMeaningfulChanges else {
      return .unchanged
    }

    if currentSummary == nil && priorSummary != nil {
      return .partial
    }

    let improved = buildImprovementDetected(
      priorSummary: priorSummary, currentSummary: currentSummary)
    let regressed = buildRegressionDetected(
      priorSummary: priorSummary, currentSummary: currentSummary, priorStatus: priorStatus)

    if improved && !regressed {
      return .partial
    }
    if regressed && !improved {
      return .regressed
    }
    return .partial
  }

  private func classifyComparison(
    priorStatus: WorkflowStatus,
    currentStatus: WorkflowStatus,
    priorSummary: TestDiagnosisSummary?,
    currentSummary: TestDiagnosisSummary?,
    hasMeaningfulChanges: Bool
  ) -> DiagnosisCompareOutcome {
    let priorRank = statusRank(priorStatus)
    let currentRank = statusRank(currentStatus)

    if currentStatus == .partial, priorRank < currentRank {
      return .partial
    }
    if currentRank > priorRank {
      return .improved
    }
    if currentRank < priorRank {
      return .regressed
    }

    if priorStatus == currentStatus,
      let priorSummary,
      let currentSummary,
      priorSummary == currentSummary
    {
      return .unchanged
    }

    guard hasMeaningfulChanges else {
      return .unchanged
    }

    if currentSummary == nil && priorSummary != nil {
      return .partial
    }

    let improved = testImprovementDetected(
      priorSummary: priorSummary, currentSummary: currentSummary)
    let regressed = testRegressionDetected(
      priorSummary: priorSummary, currentSummary: currentSummary)

    if improved && !regressed {
      return .partial
    }
    if regressed && !improved {
      return .regressed
    }
    return .partial
  }

  private func statusRank(_ status: WorkflowStatus) -> Int {
    switch status {
    case .succeeded:
      return 3
    case .partial:
      return 2
    case .failed:
      return 1
    case .unsupported:
      return 0
    case .canceled:
      return 0
    case .inProgress:
      return -1
    }
  }

  private func buildComparisonChanges(
    priorStatus: WorkflowStatus,
    currentStatus: WorkflowStatus,
    priorSummary: BuildDiagnosisSummary?,
    currentSummary: BuildDiagnosisSummary?
  ) -> [DiagnosisComparisonChange] {
    var changes: [DiagnosisComparisonChange] = []

    if priorStatus != currentStatus {
      changes.append(
        DiagnosisComparisonChange(
          field: "Overall status",
          priorValue: priorStatus.rawValue,
          currentValue: currentStatus.rawValue
        )
      )
    }

    appendChange(
      field: "Observed summary",
      priorValue: priorSummary?.observedEvidence.summary,
      currentValue: currentSummary?.observedEvidence.summary,
      into: &changes
    )
    appendChange(
      field: "Primary signal",
      priorValue: renderBuildSignal(priorSummary?.observedEvidence.primarySignal),
      currentValue: renderBuildSignal(currentSummary?.observedEvidence.primarySignal),
      into: &changes
    )
    appendChange(
      field: "Additional issue count",
      priorValue: priorSummary?.observedEvidence.additionalIssueCount,
      currentValue: currentSummary?.observedEvidence.additionalIssueCount,
      into: &changes
    )
    appendChange(
      field: "Error count",
      priorValue: priorSummary?.observedEvidence.errorCount,
      currentValue: currentSummary?.observedEvidence.errorCount,
      into: &changes
    )
    appendChange(
      field: "Warning count",
      priorValue: priorSummary?.observedEvidence.warningCount,
      currentValue: currentSummary?.observedEvidence.warningCount,
      into: &changes
    )
    // Annotate warning-count increases when the prior build failed early.
    if let priorWarnings = priorSummary?.observedEvidence.warningCount,
      let currentWarnings = currentSummary?.observedEvidence.warningCount,
      currentWarnings > priorWarnings, priorStatus == .failed
    {
      if let idx = changes.lastIndex(where: { $0.field == "Warning count" }) {
        changes[idx].annotation =
          "Warning count increase is expected when a prior build failed before full compilation."
      }
    }
    appendChange(
      field: "Analyzer warning count",
      priorValue: priorSummary?.observedEvidence.analyzerWarningCount,
      currentValue: currentSummary?.observedEvidence.analyzerWarningCount,
      into: &changes
    )
    appendChange(
      field: "Inferred conclusion",
      priorValue: priorSummary?.inferredConclusion?.summary,
      currentValue: currentSummary?.inferredConclusion?.summary,
      into: &changes
    )

    return changes
  }

  private func testComparisonChanges(
    priorStatus: WorkflowStatus,
    currentStatus: WorkflowStatus,
    priorSummary: TestDiagnosisSummary?,
    currentSummary: TestDiagnosisSummary?
  ) -> [DiagnosisComparisonChange] {
    var changes: [DiagnosisComparisonChange] = []

    if priorStatus != currentStatus {
      changes.append(
        DiagnosisComparisonChange(
          field: "Overall status",
          priorValue: priorStatus.rawValue,
          currentValue: currentStatus.rawValue
        )
      )
    }

    appendChange(
      field: "Observed summary",
      priorValue: priorSummary?.observedEvidence.summary,
      currentValue: currentSummary?.observedEvidence.summary,
      into: &changes
    )
    appendChange(
      field: "Primary failing test",
      priorValue: renderTestFailure(priorSummary?.observedEvidence.primaryFailure),
      currentValue: renderTestFailure(currentSummary?.observedEvidence.primaryFailure),
      into: &changes
    )
    appendChange(
      field: "Additional failure count",
      priorValue: priorSummary?.observedEvidence.additionalFailureCount,
      currentValue: currentSummary?.observedEvidence.additionalFailureCount,
      into: &changes
    )
    appendChange(
      field: "Total test count",
      priorValue: priorSummary?.observedEvidence.totalTestCount,
      currentValue: currentSummary?.observedEvidence.totalTestCount,
      into: &changes
    )
    appendChange(
      field: "Failed test count",
      priorValue: priorSummary?.observedEvidence.failedTestCount,
      currentValue: currentSummary?.observedEvidence.failedTestCount,
      into: &changes
    )
    appendChange(
      field: "Passed test count",
      priorValue: priorSummary?.observedEvidence.passedTestCount,
      currentValue: currentSummary?.observedEvidence.passedTestCount,
      into: &changes
    )
    appendChange(
      field: "Skipped test count",
      priorValue: priorSummary?.observedEvidence.skippedTestCount,
      currentValue: currentSummary?.observedEvidence.skippedTestCount,
      into: &changes
    )
    appendChange(
      field: "Expected failure count",
      priorValue: priorSummary?.observedEvidence.expectedFailureCount,
      currentValue: currentSummary?.observedEvidence.expectedFailureCount,
      into: &changes
    )
    appendChange(
      field: "Inferred conclusion",
      priorValue: priorSummary?.inferredConclusion?.summary,
      currentValue: currentSummary?.inferredConclusion?.summary,
      into: &changes
    )

    return changes
  }

  private func buildBlockers(
    priorStatus: WorkflowStatus,
    currentStatus: WorkflowStatus,
    priorSummary: BuildDiagnosisSummary?,
    from summary: BuildDiagnosisSummary?,
    fallback: DiagnosisStatusSummary
  ) -> [String] {
    guard currentStatus != .succeeded else {
      return []
    }

    guard let summary else {
      return [fallback.detail ?? fallback.headline]
    }

    var blockers: [String] = []

    if let signal = summary.observedEvidence.primarySignal,
      buildSignalKey(priorSummary?.observedEvidence.primarySignal) == buildSignalKey(signal)
    {
      blockers.append("Primary build signal remains: \(signal.message)")
    }

    if let priorSummary,
      priorSummary.observedEvidence.errorCount > 0,
      summary.observedEvidence.errorCount > 0,
      priorSummary.observedEvidence.errorCount == summary.observedEvidence.errorCount
    {
      blockers.append("Build still reports \(summary.observedEvidence.errorCount) error(s).")
    }

    if blockers.isEmpty, priorStatus != .succeeded, summary.observedEvidence.primarySignal == nil {
      blockers.append(fallback.detail ?? fallback.headline)
    }

    return blockers
  }

  private func testBlockers(
    priorStatus: WorkflowStatus,
    currentStatus: WorkflowStatus,
    priorSummary: TestDiagnosisSummary?,
    from summary: TestDiagnosisSummary?,
    fallback: DiagnosisStatusSummary
  ) -> [String] {
    guard currentStatus != .succeeded else {
      return []
    }

    guard let summary else {
      return [fallback.detail ?? fallback.headline]
    }

    var blockers: [String] = []

    if let failure = summary.observedEvidence.primaryFailure,
      testFailureKey(priorSummary?.observedEvidence.primaryFailure) == testFailureKey(failure)
    {
      blockers.append("Primary test remains: \(failure.testIdentifier) - \(failure.message)")
    }

    if let priorSummary,
      priorSummary.observedEvidence.failedTestCount > 0,
      summary.observedEvidence.failedTestCount > 0,
      priorSummary.observedEvidence.failedTestCount == summary.observedEvidence.failedTestCount
    {
      blockers.append(
        "Test still reports \(summary.observedEvidence.failedTestCount) failing test(s).")
    }

    if blockers.isEmpty, priorStatus != .succeeded, summary.observedEvidence.primaryFailure == nil {
      blockers.append(fallback.detail ?? fallback.headline)
    }

    return blockers
  }

  private func evidenceComparisonChanges(
    priorEvidence: [WorkflowEvidenceRecord],
    currentEvidence: [WorkflowEvidenceRecord]
  ) -> [DiagnosisComparisonChange] {
    var changes: [DiagnosisComparisonChange] = []

    appendChange(
      field: "Available artifact count",
      priorValue: priorEvidence.filter { $0.availability == .available }.count,
      currentValue: currentEvidence.filter { $0.availability == .available }.count,
      into: &changes
    )
    appendChange(
      field: "Unavailable artifact count",
      priorValue: priorEvidence.filter { $0.availability == .unavailable }.count,
      currentValue: currentEvidence.filter { $0.availability == .unavailable }.count,
      into: &changes
    )

    let priorAvailable = Set(
      priorEvidence.filter { $0.availability == .available }.map(evidenceKey))
    let currentAvailable = Set(
      currentEvidence.filter { $0.availability == .available }.map(evidenceKey))
    let priorUnavailable = Set(
      priorEvidence.filter { $0.availability == .unavailable }.map(evidenceKey))
    let currentUnavailable = Set(
      currentEvidence.filter { $0.availability == .unavailable }.map(evidenceKey))

    appendChange(
      field: "Newly available artifacts",
      priorValue: renderEvidenceKeys([]),
      currentValue: renderEvidenceKeys(currentAvailable.subtracting(priorAvailable)),
      into: &changes
    )
    appendChange(
      field: "Newly missing artifacts",
      priorValue: renderEvidenceKeys([]),
      currentValue: renderEvidenceKeys(currentUnavailable.subtracting(priorUnavailable)),
      into: &changes
    )

    return changes
  }

  private func buildImprovementDetected(
    priorSummary: BuildDiagnosisSummary?,
    currentSummary: BuildDiagnosisSummary?
  ) -> Bool {
    guard let priorSummary, let currentSummary else {
      return false
    }

    let prior = priorSummary.observedEvidence
    let current = currentSummary.observedEvidence
    if prior.primarySignal != nil, current.primarySignal == nil {
      return true
    }
    return current.additionalIssueCount < prior.additionalIssueCount
      || current.errorCount < prior.errorCount
      || current.warningCount < prior.warningCount
      || current.analyzerWarningCount < prior.analyzerWarningCount
  }

  private func buildRegressionDetected(
    priorSummary: BuildDiagnosisSummary?,
    currentSummary: BuildDiagnosisSummary?,
    priorStatus: WorkflowStatus
  ) -> Bool {
    guard let priorSummary, let currentSummary else {
      return false
    }

    let prior = priorSummary.observedEvidence
    let current = currentSummary.observedEvidence
    if prior.primarySignal == nil, current.primarySignal != nil {
      return true
    }
    // When the prior build failed early, warning/analyzer-warning increases are expected
    // (the current build simply got further in compilation). Only count error-level deltas.
    let warningRegressed =
      priorStatus != .failed
      && (current.warningCount > prior.warningCount
        || current.analyzerWarningCount > prior.analyzerWarningCount)
    return current.additionalIssueCount > prior.additionalIssueCount
      || current.errorCount > prior.errorCount
      || warningRegressed
  }

  private func testImprovementDetected(
    priorSummary: TestDiagnosisSummary?,
    currentSummary: TestDiagnosisSummary?
  ) -> Bool {
    guard let priorSummary, let currentSummary else {
      return false
    }

    let prior = priorSummary.observedEvidence
    let current = currentSummary.observedEvidence
    if prior.primaryFailure != nil, current.primaryFailure == nil {
      return true
    }
    return current.additionalFailureCount < prior.additionalFailureCount
      || current.totalTestCount > prior.totalTestCount
        && current.failedTestCount < prior.failedTestCount
      || current.failedTestCount < prior.failedTestCount
      || current.passedTestCount > prior.passedTestCount
      || current.skippedTestCount < prior.skippedTestCount
      || current.expectedFailureCount < prior.expectedFailureCount
  }

  private func testRegressionDetected(
    priorSummary: TestDiagnosisSummary?,
    currentSummary: TestDiagnosisSummary?
  ) -> Bool {
    guard let priorSummary, let currentSummary else {
      return false
    }

    let prior = priorSummary.observedEvidence
    let current = currentSummary.observedEvidence
    if prior.primaryFailure == nil, current.primaryFailure != nil {
      return true
    }
    return current.additionalFailureCount > prior.additionalFailureCount
      || current.failedTestCount > prior.failedTestCount
      || current.passedTestCount < prior.passedTestCount
      || current.skippedTestCount > prior.skippedTestCount
      || current.expectedFailureCount > prior.expectedFailureCount
  }

  private func appendChange<Value: Equatable & CustomStringConvertible>(
    field: String,
    priorValue: Value?,
    currentValue: Value?,
    into changes: inout [DiagnosisComparisonChange]
  ) {
    let priorText = priorValue.map { String(describing: $0) } ?? "not recorded"
    let currentText = currentValue.map { String(describing: $0) } ?? "not recorded"
    guard priorText != currentText else {
      return
    }
    changes.append(
      DiagnosisComparisonChange(
        field: field,
        priorValue: priorText,
        currentValue: currentText
      )
    )
  }

  private func renderBuildSignal(_ signal: BuildIssueSummary?) -> String {
    guard let signal else {
      return "No primary signal recorded."
    }
    var rendered = signal.message
    if let location = signal.location {
      rendered += " @ \(renderLocation(location))"
    }
    return rendered
  }

  private func renderTestFailure(_ failure: TestFailureSummary?) -> String {
    guard let failure else {
      return "No primary failing test recorded."
    }
    return "\(failure.testIdentifier) - \(failure.message)"
  }

  private func renderLocation(_ location: SourceLocation) -> String {
    var rendered = location.filePath
    if let line = location.line {
      rendered += ":\(line)"
      if let column = location.column {
        rendered += ":\(column)"
      }
    }
    return rendered
  }

  private func buildSignalKey(_ signal: BuildIssueSummary?) -> String? {
    signal.map { "\($0.message)|\($0.severity.rawValue)" }
  }

  private func testFailureKey(_ failure: TestFailureSummary?) -> String? {
    failure.map { "\($0.testIdentifier)|\($0.message)" }
  }

  private func evidenceKey(_ record: WorkflowEvidenceRecord) -> String {
    "\(record.kind.rawValue):\(record.availability.rawValue)"
  }

  private func renderEvidenceKeys(_ keys: Set<String>) -> String {
    guard !keys.isEmpty else {
      return "none"
    }
    return keys.sorted().joined(separator: ", ")
  }
}

private struct DiagnosisCompareWorkflowError: Error {
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

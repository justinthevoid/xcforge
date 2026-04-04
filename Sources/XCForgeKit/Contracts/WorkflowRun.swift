import Foundation

public enum WorkflowName: String, Codable, Sendable, Equatable {
  case diagnosis
}

public enum WorkflowPhase: String, Codable, Sendable, Equatable {
  case diagnosisStart = "diagnosis_start"
  case diagnosisBuild = "diagnosis_build"
  case diagnosisTest = "diagnosis_test"
  case diagnosisRuntime = "diagnosis_runtime"
}

public enum WorkflowStatus: String, Codable, Sendable, Equatable {
  case inProgress = "in_progress"
  case succeeded
  case partial
  case failed
  case canceled
  case unsupported
}

public enum WorkflowFailureClassification: String, Codable, Sendable, Equatable {
  case resolutionFailed = "resolution_failed"
  case unsupportedContext = "unsupported_context"
  case notFound = "not_found"
  case invalidRunState = "invalid_run_state"
  case executionFailed = "execution_failed"
}

public enum ContextField: String, Codable, Sendable, Equatable {
  case workflow
  case tooling
  case run
  case project
  case scheme
  case simulator
  case app
  case build
  case test
  case runtime
}

public enum BuildIssueSeverity: String, Codable, Sendable, Equatable {
  case error
  case warning
  case analyzerWarning = "analyzer_warning"
}

public struct SourceLocation: Codable, Sendable, Equatable {
  public let filePath: String
  public let line: Int?
  public let column: Int?

  public init(filePath: String, line: Int? = nil, column: Int? = nil) {
    self.filePath = filePath
    self.line = line
    self.column = column
  }
}

public struct EvidenceReference: Codable, Sendable, Equatable {
  public let kind: String
  public let path: String
  public let source: String

  public init(kind: String, path: String, source: String) {
    self.kind = kind
    self.path = path
    self.source = source
  }
}

public enum WorkflowEvidenceKind: String, Codable, Sendable, Equatable {
  case buildSummary = "build_summary"
  case testSummary = "test_summary"
  case runtimeSummary = "runtime_summary"
  case consoleLog = "console_log"
  case screenshot
  case xcresult
  case stderr
}

public enum WorkflowEvidenceAvailability: String, Codable, Sendable, Equatable {
  case available
  case unavailable
}

public enum WorkflowEvidenceUnavailableReason: String, Codable, Sendable, Equatable {
  case notCaptured = "not_captured"
  case executionFailed = "execution_failed"
  case missingOnDisk = "missing_on_disk"
  case unsupported
}

public enum WorkflowContextValueSource: String, Codable, Sendable, Equatable {
  case explicit
  case reusedRun = "reused_run"
  case sessionDefault = "session_default"
  case workflowDefault = "workflow_default"
  case autoDetected = "auto_detected"
  case derived
}

public struct WorkflowContextFieldProvenance: Codable, Sendable, Equatable {
  public let field: ContextField
  public let source: WorkflowContextValueSource
  public let sourceRunId: String?
  public let sourceAttemptId: String?
  public let detail: String?

  public init(
    field: ContextField,
    source: WorkflowContextValueSource,
    sourceRunId: String? = nil,
    sourceAttemptId: String? = nil,
    detail: String? = nil
  ) {
    self.field = field
    self.source = source
    self.sourceRunId = sourceRunId
    self.sourceAttemptId = sourceAttemptId
    self.detail = detail
  }
}

public struct WorkflowContextProvenance: Codable, Sendable, Equatable {
  public let sourceRunId: String?
  public let sourceAttemptId: String?
  public let fields: [WorkflowContextFieldProvenance]

  public init(
    sourceRunId: String? = nil,
    sourceAttemptId: String? = nil,
    fields: [WorkflowContextFieldProvenance]
  ) {
    self.sourceRunId = sourceRunId
    self.sourceAttemptId = sourceAttemptId
    self.fields = fields
  }
}

public enum WorkflowRecoveryIssue: String, Codable, Sendable, Equatable {
  case staleSimulatorState = "stale_simulator_state"
  case brokenLaunchContinuity = "broken_launch_continuity"
}

public enum WorkflowRecoveryAction: String, Codable, Sendable, Equatable {
  case resetLaunchContinuity = "reset_launch_continuity"
  case retryRuntimeCapture = "retry_runtime_capture"
}

public struct WorkflowRecoveryRecord: Codable, Sendable, Equatable {
  public let recoveryId: String
  public let sourceAttemptId: String
  public let sourceAttemptNumber: Int
  public let triggeringAttemptId: String
  public let triggeringAttemptNumber: Int
  public let recoveryAttemptId: String
  public let recoveryAttemptNumber: Int
  public let issue: WorkflowRecoveryIssue
  public let detectedIssue: String
  public let action: WorkflowRecoveryAction
  public let status: WorkflowStatus
  public let resumed: Bool
  public let summary: String
  public let detail: String?
  public let recordedAt: Date

  public init(
    recoveryId: String,
    sourceAttemptId: String,
    sourceAttemptNumber: Int,
    triggeringAttemptId: String,
    triggeringAttemptNumber: Int,
    recoveryAttemptId: String,
    recoveryAttemptNumber: Int,
    issue: WorkflowRecoveryIssue,
    detectedIssue: String,
    action: WorkflowRecoveryAction,
    status: WorkflowStatus,
    resumed: Bool,
    summary: String,
    detail: String? = nil,
    recordedAt: Date
  ) {
    self.recoveryId = recoveryId
    self.sourceAttemptId = sourceAttemptId
    self.sourceAttemptNumber = sourceAttemptNumber
    self.triggeringAttemptId = triggeringAttemptId
    self.triggeringAttemptNumber = triggeringAttemptNumber
    self.recoveryAttemptId = recoveryAttemptId
    self.recoveryAttemptNumber = recoveryAttemptNumber
    self.issue = issue
    self.detectedIssue = detectedIssue
    self.action = action
    self.status = status
    self.resumed = resumed
    self.summary = summary
    self.detail = detail
    self.recordedAt = recordedAt
  }
}

public struct WorkflowEvidenceRecord: Codable, Sendable, Equatable {
  public let kind: WorkflowEvidenceKind
  public let phase: WorkflowPhase
  public let attemptId: String
  public let attemptNumber: Int
  public let availability: WorkflowEvidenceAvailability
  public let unavailableReason: WorkflowEvidenceUnavailableReason?
  public let reference: String?
  public let source: String
  public let detail: String?

  public init(
    kind: WorkflowEvidenceKind,
    phase: WorkflowPhase,
    attemptId: String,
    attemptNumber: Int,
    availability: WorkflowEvidenceAvailability,
    unavailableReason: WorkflowEvidenceUnavailableReason? = nil,
    reference: String?,
    source: String,
    detail: String? = nil
  ) {
    self.kind = kind
    self.phase = phase
    self.attemptId = attemptId
    self.attemptNumber = attemptNumber
    self.availability = availability
    self.unavailableReason = unavailableReason
    self.reference = reference
    self.source = source
    self.detail = detail
  }
}

public struct BuildIssueSummary: Codable, Sendable, Equatable {
  public let severity: BuildIssueSeverity
  public let message: String
  public let location: SourceLocation?
  public let source: String

  public init(
    severity: BuildIssueSeverity,
    message: String,
    location: SourceLocation? = nil,
    source: String
  ) {
    self.severity = severity
    self.message = message
    self.location = location
    self.source = source
  }
}

public struct ObservedBuildEvidence: Codable, Sendable, Equatable {
  public let summary: String
  public let primarySignal: BuildIssueSummary?
  public let additionalIssueCount: Int
  public let errorCount: Int
  public let warningCount: Int
  public let analyzerWarningCount: Int

  public init(
    summary: String,
    primarySignal: BuildIssueSummary?,
    additionalIssueCount: Int,
    errorCount: Int,
    warningCount: Int,
    analyzerWarningCount: Int
  ) {
    self.summary = summary
    self.primarySignal = primarySignal
    self.additionalIssueCount = additionalIssueCount
    self.errorCount = errorCount
    self.warningCount = warningCount
    self.analyzerWarningCount = analyzerWarningCount
  }
}

public struct InferredBuildConclusion: Codable, Sendable, Equatable {
  public let summary: String

  public init(summary: String) {
    self.summary = summary
  }
}

public struct BuildDiagnosisSummary: Codable, Sendable, Equatable {
  public let observedEvidence: ObservedBuildEvidence
  public let inferredConclusion: InferredBuildConclusion?
  public let supportingEvidence: [EvidenceReference]

  public init(
    observedEvidence: ObservedBuildEvidence,
    inferredConclusion: InferredBuildConclusion?,
    supportingEvidence: [EvidenceReference]
  ) {
    self.observedEvidence = observedEvidence
    self.inferredConclusion = inferredConclusion
    self.supportingEvidence = supportingEvidence
  }
}

public struct TestFailureSummary: Codable, Sendable, Equatable {
  public let testName: String
  public let testIdentifier: String
  public let message: String
  public let source: String

  public init(
    testName: String,
    testIdentifier: String,
    message: String,
    source: String
  ) {
    self.testName = testName
    self.testIdentifier = testIdentifier
    self.message = message
    self.source = source
  }
}

public struct ObservedTestEvidence: Codable, Sendable, Equatable {
  public let summary: String
  public let primaryFailure: TestFailureSummary?
  public let additionalFailureCount: Int
  public let totalTestCount: Int
  public let failedTestCount: Int
  public let passedTestCount: Int
  public let skippedTestCount: Int
  public let expectedFailureCount: Int

  public init(
    summary: String,
    primaryFailure: TestFailureSummary?,
    additionalFailureCount: Int,
    totalTestCount: Int,
    failedTestCount: Int,
    passedTestCount: Int,
    skippedTestCount: Int,
    expectedFailureCount: Int
  ) {
    self.summary = summary
    self.primaryFailure = primaryFailure
    self.additionalFailureCount = additionalFailureCount
    self.totalTestCount = totalTestCount
    self.failedTestCount = failedTestCount
    self.passedTestCount = passedTestCount
    self.skippedTestCount = skippedTestCount
    self.expectedFailureCount = expectedFailureCount
  }
}

public struct InferredTestConclusion: Codable, Sendable, Equatable {
  public let summary: String

  public init(summary: String) {
    self.summary = summary
  }
}

public struct TestDiagnosisSummary: Codable, Sendable, Equatable {
  public let observedEvidence: ObservedTestEvidence
  public let inferredConclusion: InferredTestConclusion?
  public let supportingEvidence: [EvidenceReference]

  public init(
    observedEvidence: ObservedTestEvidence,
    inferredConclusion: InferredTestConclusion?,
    supportingEvidence: [EvidenceReference]
  ) {
    self.observedEvidence = observedEvidence
    self.inferredConclusion = inferredConclusion
    self.supportingEvidence = supportingEvidence
  }
}

public enum RuntimeSignalStream: String, Codable, Sendable, Equatable {
  case stdout
  case stderr
}

public struct RuntimeSignalSummary: Codable, Sendable, Equatable {
  public let stream: RuntimeSignalStream
  public let message: String
  public let source: String

  public init(stream: RuntimeSignalStream, message: String, source: String) {
    self.stream = stream
    self.message = message
    self.source = source
  }
}

public struct ObservedRuntimeEvidence: Codable, Sendable, Equatable {
  public let summary: String
  public let launchedApp: Bool
  public let appRunning: Bool
  public let relaunchedApp: Bool
  public let primarySignal: RuntimeSignalSummary?
  public let additionalSignalCount: Int
  public let stdoutLineCount: Int
  public let stderrLineCount: Int

  public init(
    summary: String,
    launchedApp: Bool,
    appRunning: Bool,
    relaunchedApp: Bool,
    primarySignal: RuntimeSignalSummary?,
    additionalSignalCount: Int,
    stdoutLineCount: Int,
    stderrLineCount: Int
  ) {
    self.summary = summary
    self.launchedApp = launchedApp
    self.appRunning = appRunning
    self.relaunchedApp = relaunchedApp
    self.primarySignal = primarySignal
    self.additionalSignalCount = additionalSignalCount
    self.stdoutLineCount = stdoutLineCount
    self.stderrLineCount = stderrLineCount
  }
}

public struct InferredRuntimeConclusion: Codable, Sendable, Equatable {
  public let summary: String

  public init(summary: String) {
    self.summary = summary
  }
}

public struct RuntimeDiagnosisSummary: Codable, Sendable, Equatable {
  public let observedEvidence: ObservedRuntimeEvidence
  public let inferredConclusion: InferredRuntimeConclusion?
  public let supportingEvidence: [EvidenceReference]

  public init(
    observedEvidence: ObservedRuntimeEvidence,
    inferredConclusion: InferredRuntimeConclusion?,
    supportingEvidence: [EvidenceReference]
  ) {
    self.observedEvidence = observedEvidence
    self.inferredConclusion = inferredConclusion
    self.supportingEvidence = supportingEvidence
  }
}

public enum DiagnosisStatusSummarySource: String, Codable, Sendable, Equatable {
  case start
  case build
  case test
  case runtime
}

public struct DiagnosisStatusSummary: Codable, Sendable, Equatable {
  public let source: DiagnosisStatusSummarySource
  public let headline: String
  public let detail: String?

  public init(
    source: DiagnosisStatusSummarySource,
    headline: String,
    detail: String? = nil
  ) {
    self.source = source
    self.headline = headline
    self.detail = detail
  }
}

public struct AppContext: Codable, Sendable, Equatable {
  public let bundleId: String
  public let appPath: String

  public init(bundleId: String, appPath: String) {
    self.bundleId = bundleId
    self.appPath = appPath
  }
}

public struct ResolvedWorkflowContext: Codable, Sendable, Equatable {
  public let project: String
  public let scheme: String
  public let simulator: String
  public let configuration: String
  public let app: AppContext
  public let simulatorPreparation: WorkflowSimulatorPreparation?

  public init(
    project: String,
    scheme: String,
    simulator: String,
    configuration: String = "Debug",
    app: AppContext,
    simulatorPreparation: WorkflowSimulatorPreparation? = nil
  ) {
    self.project = project
    self.scheme = scheme
    self.simulator = simulator
    self.configuration = configuration
    self.app = app
    self.simulatorPreparation = simulatorPreparation
  }

  enum CodingKeys: String, CodingKey {
    case project
    case scheme
    case simulator
    case configuration
    case app
    case simulatorPreparation
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.project = try container.decode(String.self, forKey: .project)
    self.scheme = try container.decode(String.self, forKey: .scheme)
    self.simulator = try container.decode(String.self, forKey: .simulator)
    self.configuration =
      try container.decodeIfPresent(String.self, forKey: .configuration) ?? "Debug"
    self.app = try container.decode(AppContext.self, forKey: .app)
    self.simulatorPreparation = try container.decodeIfPresent(
      WorkflowSimulatorPreparation.self, forKey: .simulatorPreparation)
  }
}

public struct WorkflowSimulatorPreparation: Codable, Sendable, Equatable {
  public enum Action: String, Codable, Sendable, Equatable {
    case reusedBooted = "reused_booted"
    case bootedForWorkflow = "booted_for_workflow"
  }

  public let requested: String
  public let selected: String
  public let displayName: String
  public let runtime: String
  public let initialState: String
  public let state: String
  public let action: Action
  public let summary: String

  public init(
    requested: String,
    selected: String,
    displayName: String,
    runtime: String,
    initialState: String,
    state: String,
    action: Action,
    summary: String
  ) {
    self.requested = requested
    self.selected = selected
    self.displayName = displayName
    self.runtime = runtime
    self.initialState = initialState
    self.state = state
    self.action = action
    self.summary = summary
  }

  enum CodingKeys: String, CodingKey {
    case requested
    case selected
    case displayName
    case runtime
    case initialState
    case state
    case action
    case summary
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.requested = try container.decode(String.self, forKey: .requested)
    self.selected = try container.decode(String.self, forKey: .selected)
    self.displayName = try container.decode(String.self, forKey: .displayName)
    self.runtime = try container.decode(String.self, forKey: .runtime)
    let finalState = try container.decode(String.self, forKey: .state)
    self.initialState =
      try container.decodeIfPresent(String.self, forKey: .initialState) ?? finalState
    self.state = finalState
    self.action =
      try container.decodeIfPresent(Action.self, forKey: .action)
      ?? (self.initialState == "Booted" ? .reusedBooted : .bootedForWorkflow)
    self.summary = try container.decode(String.self, forKey: .summary)
  }
}

public enum WorkflowEnvironmentPreflightStatus: String, Codable, Sendable, Equatable {
  case passed
  case failed
  case unsupported
}

public enum WorkflowEnvironmentCheckKind: String, Codable, Sendable, Equatable {
  case project
  case scheme
  case simulator
  case tooling
  case appContext = "app_context"
}

public struct WorkflowEnvironmentCheck: Codable, Sendable, Equatable {
  public let kind: WorkflowEnvironmentCheckKind
  public let field: ContextField
  public let status: WorkflowEnvironmentPreflightStatus
  public let message: String

  public init(
    kind: WorkflowEnvironmentCheckKind,
    field: ContextField,
    status: WorkflowEnvironmentPreflightStatus,
    message: String
  ) {
    self.kind = kind
    self.field = field
    self.status = status
    self.message = message
  }
}

public struct WorkflowEnvironmentPreflight: Codable, Sendable, Equatable {
  public let status: WorkflowEnvironmentPreflightStatus
  public let summary: String
  public let checks: [WorkflowEnvironmentCheck]
  public let validatedAt: Date

  public init(
    status: WorkflowEnvironmentPreflightStatus,
    summary: String,
    checks: [WorkflowEnvironmentCheck],
    validatedAt: Date
  ) {
    self.status = status
    self.summary = summary
    self.checks = checks
    self.validatedAt = validatedAt
  }
}

public enum WorkflowActionKind: String, Codable, Sendable, Equatable {
  case runCreated = "run_created"
  case contextResolved = "context_resolved"
  case buildStarted = "build_started"
  case buildCompleted = "build_completed"
  case testStarted = "test_started"
  case testCompleted = "test_completed"
  case runtimeStarted = "runtime_started"
  case runtimeCompleted = "runtime_completed"
  case verifyStarted = "verify_started"
  case verifyCompleted = "verify_completed"
  case evidenceCaptured = "evidence_captured"
}

public struct WorkflowActionRecord: Codable, Sendable, Equatable {
  public let kind: WorkflowActionKind
  public let phase: WorkflowPhase
  public let attemptId: String
  public let timestamp: Date
  public let detail: String?

  public init(
    kind: WorkflowActionKind,
    phase: WorkflowPhase,
    attemptId: String,
    timestamp: Date,
    detail: String? = nil
  ) {
    self.kind = kind
    self.phase = phase
    self.attemptId = attemptId
    self.timestamp = timestamp
    self.detail = detail
  }
}

public struct WorkflowAttemptRecord: Codable, Sendable, Equatable {
  public let attemptId: String
  public let attemptNumber: Int
  public let rerunOfAttemptId: String?
  public let phase: WorkflowPhase
  public let startedAt: Date
  public let status: WorkflowStatus

  public init(
    attemptId: String,
    attemptNumber: Int,
    rerunOfAttemptId: String? = nil,
    phase: WorkflowPhase,
    startedAt: Date,
    status: WorkflowStatus
  ) {
    self.attemptId = attemptId
    self.attemptNumber = attemptNumber
    self.rerunOfAttemptId = rerunOfAttemptId
    self.phase = phase
    self.startedAt = startedAt
    self.status = status
  }

  enum CodingKeys: String, CodingKey {
    case attemptId
    case attemptNumber
    case rerunOfAttemptId
    case phase
    case startedAt
    case status
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.attemptId = try container.decode(String.self, forKey: .attemptId)
    self.attemptNumber = try container.decode(Int.self, forKey: .attemptNumber)
    self.rerunOfAttemptId = try container.decodeIfPresent(String.self, forKey: .rerunOfAttemptId)
    self.phase = try container.decode(WorkflowPhase.self, forKey: .phase)
    self.startedAt = try container.decode(Date.self, forKey: .startedAt)
    self.status = try container.decode(WorkflowStatus.self, forKey: .status)
  }
}

public struct WorkflowAttemptSnapshot: Codable, Sendable, Equatable {
  public let attempt: WorkflowAttemptRecord
  public let phase: WorkflowPhase
  public let status: WorkflowStatus
  public let resolvedContext: ResolvedWorkflowContext
  public let diagnosisSummary: BuildDiagnosisSummary?
  public let testDiagnosisSummary: TestDiagnosisSummary?
  public let runtimeSummary: RuntimeDiagnosisSummary?
  public let recordedAt: Date

  public init(
    attempt: WorkflowAttemptRecord,
    phase: WorkflowPhase,
    status: WorkflowStatus,
    resolvedContext: ResolvedWorkflowContext,
    diagnosisSummary: BuildDiagnosisSummary? = nil,
    testDiagnosisSummary: TestDiagnosisSummary? = nil,
    runtimeSummary: RuntimeDiagnosisSummary? = nil,
    recordedAt: Date
  ) {
    self.attempt = attempt
    self.phase = phase
    self.status = status
    self.resolvedContext = resolvedContext
    self.diagnosisSummary = diagnosisSummary
    self.testDiagnosisSummary = testDiagnosisSummary
    self.runtimeSummary = runtimeSummary
    self.recordedAt = recordedAt
  }
}

public struct WorkflowRunRecord: Codable, Sendable, Equatable {
  public static let currentSchemaVersion = "1.11.0"

  public let schemaVersion: String
  public let runId: String
  public let workflow: WorkflowName
  public let phase: WorkflowPhase
  public let status: WorkflowStatus
  public let createdAt: Date
  public let updatedAt: Date
  public let attempt: WorkflowAttemptRecord
  public let resolvedContext: ResolvedWorkflowContext
  public let diagnosisSummary: BuildDiagnosisSummary?
  public let testDiagnosisSummary: TestDiagnosisSummary?
  public let runtimeSummary: RuntimeDiagnosisSummary?
  public let environmentPreflight: WorkflowEnvironmentPreflight?
  public let contextProvenance: WorkflowContextProvenance?
  public let recoveryHistory: [WorkflowRecoveryRecord]
  public let evidence: [WorkflowEvidenceRecord]
  public let attemptHistory: [WorkflowAttemptSnapshot]
  public let actionHistory: [WorkflowActionRecord]

  public init(
    schemaVersion: String = Self.currentSchemaVersion,
    runId: String,
    workflow: WorkflowName,
    phase: WorkflowPhase,
    status: WorkflowStatus,
    createdAt: Date,
    updatedAt: Date,
    attempt: WorkflowAttemptRecord,
    resolvedContext: ResolvedWorkflowContext,
    diagnosisSummary: BuildDiagnosisSummary? = nil,
    testDiagnosisSummary: TestDiagnosisSummary? = nil,
    runtimeSummary: RuntimeDiagnosisSummary? = nil,
    environmentPreflight: WorkflowEnvironmentPreflight? = nil,
    contextProvenance: WorkflowContextProvenance? = nil,
    recoveryHistory: [WorkflowRecoveryRecord] = [],
    evidence: [WorkflowEvidenceRecord] = [],
    attemptHistory: [WorkflowAttemptSnapshot] = [],
    actionHistory: [WorkflowActionRecord] = []
  ) {
    self.schemaVersion = schemaVersion
    self.runId = runId
    self.workflow = workflow
    self.phase = phase
    self.status = status
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.attempt = attempt
    self.resolvedContext = resolvedContext
    self.diagnosisSummary = diagnosisSummary
    self.testDiagnosisSummary = testDiagnosisSummary
    self.runtimeSummary = runtimeSummary
    self.environmentPreflight = environmentPreflight
    self.contextProvenance = contextProvenance
    self.recoveryHistory = recoveryHistory
    self.evidence = evidence
    self.attemptHistory = attemptHistory
    self.actionHistory = actionHistory
  }

  enum CodingKeys: String, CodingKey {
    case schemaVersion
    case runId
    case workflow
    case phase
    case status
    case createdAt
    case updatedAt
    case attempt
    case resolvedContext
    case diagnosisSummary
    case testDiagnosisSummary
    case runtimeSummary
    case environmentPreflight
    case contextProvenance
    case recoveryHistory
    case evidence
    case attemptHistory
    case actionHistory
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.schemaVersion = try container.decode(String.self, forKey: .schemaVersion)
    self.runId = try container.decode(String.self, forKey: .runId)
    self.workflow = try container.decode(WorkflowName.self, forKey: .workflow)
    self.phase = try container.decode(WorkflowPhase.self, forKey: .phase)
    self.status = try container.decode(WorkflowStatus.self, forKey: .status)
    self.createdAt = try container.decode(Date.self, forKey: .createdAt)
    self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    self.attempt = try container.decode(WorkflowAttemptRecord.self, forKey: .attempt)
    self.resolvedContext = try container.decode(
      ResolvedWorkflowContext.self, forKey: .resolvedContext)
    self.diagnosisSummary = try container.decodeIfPresent(
      BuildDiagnosisSummary.self, forKey: .diagnosisSummary)
    self.testDiagnosisSummary = try container.decodeIfPresent(
      TestDiagnosisSummary.self, forKey: .testDiagnosisSummary)
    self.runtimeSummary = try container.decodeIfPresent(
      RuntimeDiagnosisSummary.self, forKey: .runtimeSummary)
    self.environmentPreflight = try container.decodeIfPresent(
      WorkflowEnvironmentPreflight.self, forKey: .environmentPreflight)
    self.contextProvenance = try container.decodeIfPresent(
      WorkflowContextProvenance.self, forKey: .contextProvenance)
    self.recoveryHistory =
      try container.decodeIfPresent([WorkflowRecoveryRecord].self, forKey: .recoveryHistory) ?? []
    self.evidence =
      try container.decodeIfPresent([WorkflowEvidenceRecord].self, forKey: .evidence) ?? []
    self.attemptHistory =
      try container.decodeIfPresent([WorkflowAttemptSnapshot].self, forKey: .attemptHistory) ?? []
    self.actionHistory =
      try container.decodeIfPresent([WorkflowActionRecord].self, forKey: .actionHistory) ?? []
  }
}

public enum FailureRecoverability: String, Codable, Sendable, Equatable {
  case retryAfterFix = "retry_after_fix"
  case actionRequired = "action_required"
  case stop
  case unknown
}

extension WorkflowFailureClassification {
  public var recoverability: FailureRecoverability {
    switch self {
    case .resolutionFailed, .unsupportedContext:
      return .actionRequired
    case .notFound, .invalidRunState:
      return .stop
    case .executionFailed:
      return .retryAfterFix
    }
  }
}

public struct ObservedFailureEvidence: Codable, Sendable, Equatable {
  public let summary: String
  public let detail: String?

  public init(summary: String, detail: String? = nil) {
    self.summary = summary
    self.detail = detail
  }
}

public struct InferredFailureConclusion: Codable, Sendable, Equatable {
  public let summary: String

  public init(summary: String) {
    self.summary = summary
  }
}

public struct WorkflowFailure: Codable, Sendable, Equatable {
  public let field: ContextField
  public let classification: WorkflowFailureClassification
  public let message: String
  public let options: [String]
  public let observed: ObservedFailureEvidence?
  public let inferred: InferredFailureConclusion?
  public let recoverability: FailureRecoverability?
  public let evidenceReferences: [EvidenceReference]?

  public init(
    field: ContextField,
    classification: WorkflowFailureClassification,
    message: String,
    options: [String] = [],
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
}

public struct DiagnosisStartRequest: Sendable, Equatable {
  public let project: String?
  public let scheme: String?
  public let simulator: String?
  public let reuseRunId: String?
  public let configuration: String?

  public init(
    project: String? = nil,
    scheme: String? = nil,
    simulator: String? = nil,
    reuseRunId: String? = nil,
    configuration: String? = nil
  ) {
    self.project = project
    self.scheme = scheme
    self.simulator = simulator
    self.reuseRunId = reuseRunId
    self.configuration = configuration
  }
}

public struct DiagnosisStartResult: Codable, Sendable, Equatable {
  public let schemaVersion: String
  public let workflow: WorkflowName
  public let phase: WorkflowPhase
  public let status: WorkflowStatus
  public let runId: String?
  public let attemptId: String?
  public let resolvedContext: ResolvedWorkflowContext?
  public let contextProvenance: WorkflowContextProvenance?
  public let environmentPreflight: WorkflowEnvironmentPreflight?
  public let failure: WorkflowFailure?
  public let persistedRunPath: String?

  public init(
    schemaVersion: String = WorkflowRunRecord.currentSchemaVersion,
    workflow: WorkflowName = .diagnosis,
    phase: WorkflowPhase = .diagnosisStart,
    status: WorkflowStatus,
    runId: String?,
    attemptId: String?,
    resolvedContext: ResolvedWorkflowContext?,
    contextProvenance: WorkflowContextProvenance? = nil,
    environmentPreflight: WorkflowEnvironmentPreflight? = nil,
    failure: WorkflowFailure?,
    persistedRunPath: String?
  ) {
    self.schemaVersion = schemaVersion
    self.workflow = workflow
    self.phase = phase
    self.status = status
    self.runId = runId
    self.attemptId = attemptId
    self.resolvedContext = resolvedContext
    self.contextProvenance = contextProvenance
    self.environmentPreflight = environmentPreflight
    self.failure = failure
    self.persistedRunPath = persistedRunPath
  }

  public var isSuccessfulStart: Bool {
    status == .inProgress && runId != nil && attemptId != nil && resolvedContext != nil
  }
}

public struct DiagnosisBuildRequest: Sendable, Equatable {
  public let runId: String

  public init(runId: String) {
    self.runId = runId
  }
}

public struct DiagnosisBuildResult: Codable, Sendable, Equatable {
  public let schemaVersion: String
  public let workflow: WorkflowName
  public let phase: WorkflowPhase
  public let status: WorkflowStatus
  public let runId: String?
  public let attemptId: String?
  public let resolvedContext: ResolvedWorkflowContext?
  public let summary: BuildDiagnosisSummary?
  public let failure: WorkflowFailure?
  public let persistedRunPath: String?

  public init(
    schemaVersion: String = WorkflowRunRecord.currentSchemaVersion,
    workflow: WorkflowName = .diagnosis,
    phase: WorkflowPhase = .diagnosisBuild,
    status: WorkflowStatus,
    runId: String?,
    attemptId: String?,
    resolvedContext: ResolvedWorkflowContext?,
    summary: BuildDiagnosisSummary?,
    failure: WorkflowFailure?,
    persistedRunPath: String?
  ) {
    self.schemaVersion = schemaVersion
    self.workflow = workflow
    self.phase = phase
    self.status = status
    self.runId = runId
    self.attemptId = attemptId
    self.resolvedContext = resolvedContext
    self.summary = summary
    self.failure = failure
    self.persistedRunPath = persistedRunPath
  }

  public var isSuccessfulDiagnosis: Bool {
    status == .succeeded && runId != nil && attemptId != nil && resolvedContext != nil
      && summary != nil
  }
}

public struct DiagnosisTestRequest: Sendable, Equatable {
  public let runId: String

  public init(runId: String) {
    self.runId = runId
  }
}

public struct DiagnosisTestResult: Codable, Sendable, Equatable {
  public let schemaVersion: String
  public let workflow: WorkflowName
  public let phase: WorkflowPhase
  public let status: WorkflowStatus
  public let runId: String?
  public let attemptId: String?
  public let resolvedContext: ResolvedWorkflowContext?
  public let summary: TestDiagnosisSummary?
  public let failure: WorkflowFailure?
  public let persistedRunPath: String?

  public init(
    schemaVersion: String = WorkflowRunRecord.currentSchemaVersion,
    workflow: WorkflowName = .diagnosis,
    phase: WorkflowPhase = .diagnosisTest,
    status: WorkflowStatus,
    runId: String?,
    attemptId: String?,
    resolvedContext: ResolvedWorkflowContext?,
    summary: TestDiagnosisSummary?,
    failure: WorkflowFailure?,
    persistedRunPath: String?
  ) {
    self.schemaVersion = schemaVersion
    self.workflow = workflow
    self.phase = phase
    self.status = status
    self.runId = runId
    self.attemptId = attemptId
    self.resolvedContext = resolvedContext
    self.summary = summary
    self.failure = failure
    self.persistedRunPath = persistedRunPath
  }

  public var isSuccessfulDiagnosis: Bool {
    status == .succeeded && runId != nil && attemptId != nil && resolvedContext != nil
      && summary != nil
  }
}

public struct DiagnosisRuntimeRequest: Sendable, Equatable {
  public let runId: String
  public let captureScreenshot: Bool

  public init(runId: String, captureScreenshot: Bool = false) {
    self.runId = runId
    self.captureScreenshot = captureScreenshot
  }
}

public struct DiagnosisRuntimeResult: Codable, Sendable, Equatable {
  public let schemaVersion: String
  public let workflow: WorkflowName
  public let phase: WorkflowPhase
  public let status: WorkflowStatus
  public let runId: String?
  public let attemptId: String?
  public let resolvedContext: ResolvedWorkflowContext?
  public let summary: RuntimeDiagnosisSummary?
  public let recoveryHistory: [WorkflowRecoveryRecord]
  public let evidence: [WorkflowEvidenceRecord]
  public let failure: WorkflowFailure?
  public let persistedRunPath: String?

  public init(
    schemaVersion: String = WorkflowRunRecord.currentSchemaVersion,
    workflow: WorkflowName = .diagnosis,
    phase: WorkflowPhase = .diagnosisRuntime,
    status: WorkflowStatus,
    runId: String?,
    attemptId: String?,
    resolvedContext: ResolvedWorkflowContext?,
    summary: RuntimeDiagnosisSummary?,
    recoveryHistory: [WorkflowRecoveryRecord] = [],
    evidence: [WorkflowEvidenceRecord] = [],
    failure: WorkflowFailure?,
    persistedRunPath: String?
  ) {
    self.schemaVersion = schemaVersion
    self.workflow = workflow
    self.phase = phase
    self.status = status
    self.runId = runId
    self.attemptId = attemptId
    self.resolvedContext = resolvedContext
    self.summary = summary
    self.recoveryHistory = recoveryHistory
    self.evidence = evidence
    self.failure = failure
    self.persistedRunPath = persistedRunPath
  }

  public var isSuccessfulDiagnosis: Bool {
    status == .succeeded && runId != nil && attemptId != nil && resolvedContext != nil
      && summary != nil
  }
}

public struct DiagnosisStatusRequest: Sendable, Equatable {
  public let runId: String?

  public init(runId: String? = nil) {
    self.runId = runId
  }
}

public struct DiagnosisStatusResult: Codable, Sendable, Equatable {
  public let schemaVersion: String
  public let workflow: WorkflowName
  public let phase: WorkflowPhase?
  public let status: WorkflowStatus?
  public let runId: String?
  public let attemptId: String?
  public let resolvedContext: ResolvedWorkflowContext?
  public let summary: DiagnosisStatusSummary?
  public let recoveryHistory: [WorkflowRecoveryRecord]
  public let actionHistory: [WorkflowActionRecord]
  public let failure: WorkflowFailure?
  public let persistedRunPath: String?

  public init(
    schemaVersion: String = WorkflowRunRecord.currentSchemaVersion,
    workflow: WorkflowName = .diagnosis,
    phase: WorkflowPhase?,
    status: WorkflowStatus?,
    runId: String?,
    attemptId: String?,
    resolvedContext: ResolvedWorkflowContext?,
    summary: DiagnosisStatusSummary?,
    recoveryHistory: [WorkflowRecoveryRecord] = [],
    actionHistory: [WorkflowActionRecord] = [],
    failure: WorkflowFailure?,
    persistedRunPath: String?
  ) {
    self.schemaVersion = schemaVersion
    self.workflow = workflow
    self.phase = phase
    self.status = status
    self.runId = runId
    self.attemptId = attemptId
    self.resolvedContext = resolvedContext
    self.summary = summary
    self.recoveryHistory = recoveryHistory
    self.actionHistory = actionHistory
    self.failure = failure
    self.persistedRunPath = persistedRunPath
  }

  enum CodingKeys: String, CodingKey {
    case schemaVersion
    case workflow
    case phase
    case status
    case runId
    case attemptId
    case resolvedContext
    case summary
    case recoveryHistory
    case actionHistory
    case failure
    case persistedRunPath
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.schemaVersion = try container.decode(String.self, forKey: .schemaVersion)
    self.workflow = try container.decode(WorkflowName.self, forKey: .workflow)
    self.phase = try container.decodeIfPresent(WorkflowPhase.self, forKey: .phase)
    self.status = try container.decodeIfPresent(WorkflowStatus.self, forKey: .status)
    self.runId = try container.decodeIfPresent(String.self, forKey: .runId)
    self.attemptId = try container.decodeIfPresent(String.self, forKey: .attemptId)
    self.resolvedContext = try container.decodeIfPresent(
      ResolvedWorkflowContext.self, forKey: .resolvedContext)
    self.summary = try container.decodeIfPresent(DiagnosisStatusSummary.self, forKey: .summary)
    self.recoveryHistory =
      try container.decodeIfPresent([WorkflowRecoveryRecord].self, forKey: .recoveryHistory) ?? []
    self.actionHistory =
      try container.decodeIfPresent([WorkflowActionRecord].self, forKey: .actionHistory) ?? []
    self.failure = try container.decodeIfPresent(WorkflowFailure.self, forKey: .failure)
    self.persistedRunPath = try container.decodeIfPresent(String.self, forKey: .persistedRunPath)
  }

  public var isSuccessfulInspection: Bool {
    runId != nil && phase != nil && status != nil && failure == nil
  }
}

public struct DiagnosisEvidenceRequest: Sendable, Equatable {
  public let runId: String?

  public init(runId: String? = nil) {
    self.runId = runId
  }
}

public struct DiagnosisVerifyRequest: Sendable, Equatable {
  public let runId: String
  public let project: String?
  public let scheme: String?
  public let simulator: String?
  public let configuration: String?

  public init(
    runId: String,
    project: String? = nil,
    scheme: String? = nil,
    simulator: String? = nil,
    configuration: String? = nil
  ) {
    self.runId = runId
    self.project = project
    self.scheme = scheme
    self.simulator = simulator
    self.configuration = configuration
  }
}

public enum DiagnosisVerifyOutcome: String, Codable, Sendable, Equatable {
  case verified
  case blocked
  case unchanged
  case partial
  case failed
}

public struct DiagnosisVerifyResult: Codable, Sendable, Equatable {
  public let schemaVersion: String
  public let workflow: WorkflowName
  public let phase: WorkflowPhase?
  public let status: WorkflowStatus?
  public let outcome: DiagnosisVerifyOutcome?
  public let runId: String?
  public let attemptId: String?
  public let sourceAttemptId: String?
  public let resolvedContext: ResolvedWorkflowContext?
  public let summary: DiagnosisStatusSummary?
  public let buildSummary: BuildDiagnosisSummary?
  public let testSummary: TestDiagnosisSummary?
  public let evidence: [WorkflowEvidenceRecord]
  public let failure: WorkflowFailure?
  public let persistedRunPath: String?

  public init(
    schemaVersion: String = WorkflowRunRecord.currentSchemaVersion,
    workflow: WorkflowName = .diagnosis,
    phase: WorkflowPhase?,
    status: WorkflowStatus?,
    outcome: DiagnosisVerifyOutcome?,
    runId: String?,
    attemptId: String?,
    sourceAttemptId: String?,
    resolvedContext: ResolvedWorkflowContext?,
    summary: DiagnosisStatusSummary?,
    buildSummary: BuildDiagnosisSummary?,
    testSummary: TestDiagnosisSummary?,
    evidence: [WorkflowEvidenceRecord],
    failure: WorkflowFailure?,
    persistedRunPath: String?
  ) {
    self.schemaVersion = schemaVersion
    self.workflow = workflow
    self.phase = phase
    self.status = status
    self.outcome = outcome
    self.runId = runId
    self.attemptId = attemptId
    self.sourceAttemptId = sourceAttemptId
    self.resolvedContext = resolvedContext
    self.summary = summary
    self.buildSummary = buildSummary
    self.testSummary = testSummary
    self.evidence = evidence
    self.failure = failure
    self.persistedRunPath = persistedRunPath
  }

  public var isSuccessfulVerification: Bool {
    outcome == .verified
      && status == .succeeded
      && runId != nil
      && phase != nil
      && attemptId != nil
      && failure == nil
  }
}

public struct DiagnosisCompareRequest: Sendable, Equatable {
  public let runId: String?

  public init(runId: String? = nil) {
    self.runId = runId
  }
}

public enum DiagnosisCompareOutcome: String, Codable, Sendable, Equatable {
  case improved
  case unchanged
  case regressed
  case partial
}

public struct DiagnosisComparisonChange: Codable, Sendable, Equatable {
  public let field: String
  public let priorValue: String
  public let currentValue: String

  public init(field: String, priorValue: String, currentValue: String) {
    self.field = field
    self.priorValue = priorValue
    self.currentValue = currentValue
  }
}

public struct DiagnosisCompareAttemptSnapshot: Codable, Sendable, Equatable {
  public let attemptId: String
  public let attemptNumber: Int
  public let phase: WorkflowPhase
  public let status: WorkflowStatus
  public let resolvedContext: ResolvedWorkflowContext
  public let summary: DiagnosisStatusSummary
  public let diagnosisSummary: BuildDiagnosisSummary?
  public let testDiagnosisSummary: TestDiagnosisSummary?
  public let runtimeSummary: RuntimeDiagnosisSummary?
  public let evidence: [WorkflowEvidenceRecord]
  public let recordedAt: Date

  public init(
    attemptId: String,
    attemptNumber: Int,
    phase: WorkflowPhase,
    status: WorkflowStatus,
    resolvedContext: ResolvedWorkflowContext,
    summary: DiagnosisStatusSummary,
    diagnosisSummary: BuildDiagnosisSummary? = nil,
    testDiagnosisSummary: TestDiagnosisSummary? = nil,
    runtimeSummary: RuntimeDiagnosisSummary? = nil,
    evidence: [WorkflowEvidenceRecord] = [],
    recordedAt: Date
  ) {
    self.attemptId = attemptId
    self.attemptNumber = attemptNumber
    self.phase = phase
    self.status = status
    self.resolvedContext = resolvedContext
    self.summary = summary
    self.diagnosisSummary = diagnosisSummary
    self.testDiagnosisSummary = testDiagnosisSummary
    self.runtimeSummary = runtimeSummary
    self.evidence = evidence
    self.recordedAt = recordedAt
  }

  public var availableEvidence: [WorkflowEvidenceRecord] {
    evidence.filter { $0.availability == .available }
  }

  public var unavailableEvidence: [WorkflowEvidenceRecord] {
    evidence.filter { $0.availability == .unavailable }
  }
}

public struct DiagnosisCompareResult: Codable, Sendable, Equatable {
  public let schemaVersion: String
  public let workflow: WorkflowName
  public let phase: WorkflowPhase?
  public let status: WorkflowStatus?
  public let outcome: DiagnosisCompareOutcome?
  public let runId: String?
  public let attemptId: String?
  public let sourceAttemptId: String?
  public let priorAttempt: DiagnosisCompareAttemptSnapshot?
  public let currentAttempt: DiagnosisCompareAttemptSnapshot?
  public let changedEvidence: [DiagnosisComparisonChange]
  public let unchangedBlockers: [String]
  public let failure: WorkflowFailure?
  public let persistedRunPath: String?

  public init(
    schemaVersion: String = WorkflowRunRecord.currentSchemaVersion,
    workflow: WorkflowName = .diagnosis,
    phase: WorkflowPhase?,
    status: WorkflowStatus?,
    outcome: DiagnosisCompareOutcome?,
    runId: String?,
    attemptId: String?,
    sourceAttemptId: String?,
    priorAttempt: DiagnosisCompareAttemptSnapshot?,
    currentAttempt: DiagnosisCompareAttemptSnapshot?,
    changedEvidence: [DiagnosisComparisonChange],
    unchangedBlockers: [String],
    failure: WorkflowFailure?,
    persistedRunPath: String?
  ) {
    self.schemaVersion = schemaVersion
    self.workflow = workflow
    self.phase = phase
    self.status = status
    self.outcome = outcome
    self.runId = runId
    self.attemptId = attemptId
    self.sourceAttemptId = sourceAttemptId
    self.priorAttempt = priorAttempt
    self.currentAttempt = currentAttempt
    self.changedEvidence = changedEvidence
    self.unchangedBlockers = unchangedBlockers
    self.failure = failure
    self.persistedRunPath = persistedRunPath
  }

  public var isSuccessfulComparison: Bool {
    runId != nil
      && attemptId != nil
      && sourceAttemptId != nil
      && priorAttempt != nil
      && currentAttempt != nil
      && failure == nil
  }
}

public struct DiagnosisFinalResultRequest: Sendable, Equatable {
  public let runId: String?

  public init(runId: String? = nil) {
    self.runId = runId
  }
}

public struct DiagnosisFinalComparison: Codable, Sendable, Equatable {
  public let outcome: DiagnosisCompareOutcome
  public let changedEvidence: [DiagnosisComparisonChange]
  public let unchangedBlockers: [String]

  public init(
    outcome: DiagnosisCompareOutcome,
    changedEvidence: [DiagnosisComparisonChange],
    unchangedBlockers: [String]
  ) {
    self.outcome = outcome
    self.changedEvidence = changedEvidence
    self.unchangedBlockers = unchangedBlockers
  }
}

public enum FollowOnConfidence: String, Codable, Sendable, Equatable {
  case evidenceSupported = "evidence_supported"
  case inferred
}

public struct WorkflowFollowOnAction: Codable, Sendable, Equatable {
  public let action: String
  public let rationale: String
  public let confidence: FollowOnConfidence

  public init(action: String, rationale: String, confidence: FollowOnConfidence) {
    self.action = action
    self.rationale = rationale
    self.confidence = confidence
  }
}

public struct DiagnosisFinalResult: Codable, Sendable, Equatable {
  public let schemaVersion: String
  public let workflow: WorkflowName
  public let phase: WorkflowPhase?
  public let status: WorkflowStatus?
  public let runId: String?
  public let attemptId: String?
  public let sourceAttemptId: String?
  public let summary: DiagnosisStatusSummary?
  public let recoveryHistory: [WorkflowRecoveryRecord]
  public let currentAttempt: DiagnosisCompareAttemptSnapshot?
  public let sourceAttempt: DiagnosisCompareAttemptSnapshot?
  public let comparison: DiagnosisFinalComparison?
  public let comparisonNote: String?
  public var followOnAction: WorkflowFollowOnAction?
  public let failure: WorkflowFailure?
  public let persistedRunPath: String?

  public init(
    schemaVersion: String = WorkflowRunRecord.currentSchemaVersion,
    workflow: WorkflowName = .diagnosis,
    phase: WorkflowPhase?,
    status: WorkflowStatus?,
    runId: String?,
    attemptId: String?,
    sourceAttemptId: String?,
    summary: DiagnosisStatusSummary?,
    recoveryHistory: [WorkflowRecoveryRecord] = [],
    currentAttempt: DiagnosisCompareAttemptSnapshot?,
    sourceAttempt: DiagnosisCompareAttemptSnapshot?,
    comparison: DiagnosisFinalComparison?,
    comparisonNote: String? = nil,
    followOnAction: WorkflowFollowOnAction? = nil,
    failure: WorkflowFailure?,
    persistedRunPath: String?
  ) {
    self.schemaVersion = schemaVersion
    self.workflow = workflow
    self.phase = phase
    self.status = status
    self.runId = runId
    self.attemptId = attemptId
    self.sourceAttemptId = sourceAttemptId
    self.summary = summary
    self.recoveryHistory = recoveryHistory
    self.currentAttempt = currentAttempt
    self.sourceAttempt = sourceAttempt
    self.comparison = comparison
    self.comparisonNote = comparisonNote
    self.followOnAction = followOnAction
    self.failure = failure
    self.persistedRunPath = persistedRunPath
  }

  public var isSuccessfulFinalResult: Bool {
    runId != nil
      && phase != nil
      && status != nil
      && attemptId != nil
      && summary != nil
      && currentAttempt != nil
      && failure == nil
  }
}

public enum DiagnosisEvidenceState: String, Codable, Sendable, Equatable {
  case complete
  case partial
  case empty
}

public struct DiagnosisEvidenceResult: Codable, Sendable, Equatable {
  public let schemaVersion: String
  public let workflow: WorkflowName
  public let phase: WorkflowPhase?
  public let status: WorkflowStatus?
  public let evidenceState: DiagnosisEvidenceState?
  public let runId: String?
  public let attemptId: String?
  public let resolvedContext: ResolvedWorkflowContext?
  public let buildSummary: BuildDiagnosisSummary?
  public let testSummary: TestDiagnosisSummary?
  public let runtimeSummary: RuntimeDiagnosisSummary?
  public let recoveryHistory: [WorkflowRecoveryRecord]
  public let evidence: [WorkflowEvidenceRecord]
  public let failure: WorkflowFailure?
  public let persistedRunPath: String?

  public init(
    schemaVersion: String = WorkflowRunRecord.currentSchemaVersion,
    workflow: WorkflowName = .diagnosis,
    phase: WorkflowPhase?,
    status: WorkflowStatus?,
    evidenceState: DiagnosisEvidenceState?,
    runId: String?,
    attemptId: String?,
    resolvedContext: ResolvedWorkflowContext?,
    buildSummary: BuildDiagnosisSummary?,
    testSummary: TestDiagnosisSummary?,
    runtimeSummary: RuntimeDiagnosisSummary?,
    recoveryHistory: [WorkflowRecoveryRecord] = [],
    evidence: [WorkflowEvidenceRecord],
    failure: WorkflowFailure?,
    persistedRunPath: String?
  ) {
    self.schemaVersion = schemaVersion
    self.workflow = workflow
    self.phase = phase
    self.status = status
    self.evidenceState = evidenceState
    self.runId = runId
    self.attemptId = attemptId
    self.resolvedContext = resolvedContext
    self.buildSummary = buildSummary
    self.testSummary = testSummary
    self.runtimeSummary = runtimeSummary
    self.recoveryHistory = recoveryHistory
    self.evidence = evidence
    self.failure = failure
    self.persistedRunPath = persistedRunPath
  }

  public var isSuccessfulInspection: Bool {
    runId != nil && phase != nil && status != nil && failure == nil
  }

  public var availableEvidence: [WorkflowEvidenceRecord] {
    evidence.filter { $0.availability == .available }
  }

  public var unavailableEvidence: [WorkflowEvidenceRecord] {
    evidence.filter { $0.availability == .unavailable }
  }

  public var hasAnyEvidence: Bool {
    buildSummary != nil || testSummary != nil || runtimeSummary != nil || !evidence.isEmpty
  }
}

// MARK: - Diagnosis Inspect

public struct DiagnosisInspectRequest: Sendable, Equatable {
  public let runId: String?

  public init(runId: String? = nil) {
    self.runId = runId
  }
}

public enum DiagnosisInspectEvidenceCompleteness: String, Codable, Sendable, Equatable {
  case complete
  case partial
  case empty
  case unknown
}

public struct DiagnosisInspectResult: Codable, Sendable, Equatable {
  public let schemaVersion: String
  public let workflow: WorkflowName
  public let phase: WorkflowPhase?
  public let status: WorkflowStatus?
  public let runId: String?
  public let attemptId: String?
  public let resolvedContext: ResolvedWorkflowContext?
  public let contextProvenance: WorkflowContextProvenance?
  public let actionHistory: [WorkflowActionRecord]
  public let evidence: [WorkflowEvidenceRecord]
  public let evidenceCompleteness: DiagnosisInspectEvidenceCompleteness?
  public let failure: WorkflowFailure?
  public let followOnAction: WorkflowFollowOnAction?
  public let persistedRunPath: String?

  public init(
    schemaVersion: String = WorkflowRunRecord.currentSchemaVersion,
    workflow: WorkflowName = .diagnosis,
    phase: WorkflowPhase?,
    status: WorkflowStatus?,
    runId: String?,
    attemptId: String?,
    resolvedContext: ResolvedWorkflowContext?,
    contextProvenance: WorkflowContextProvenance?,
    actionHistory: [WorkflowActionRecord] = [],
    evidence: [WorkflowEvidenceRecord] = [],
    evidenceCompleteness: DiagnosisInspectEvidenceCompleteness?,
    failure: WorkflowFailure?,
    followOnAction: WorkflowFollowOnAction? = nil,
    persistedRunPath: String?
  ) {
    self.schemaVersion = schemaVersion
    self.workflow = workflow
    self.phase = phase
    self.status = status
    self.runId = runId
    self.attemptId = attemptId
    self.resolvedContext = resolvedContext
    self.contextProvenance = contextProvenance
    self.actionHistory = actionHistory
    self.evidence = evidence
    self.evidenceCompleteness = evidenceCompleteness
    self.failure = failure
    self.followOnAction = followOnAction
    self.persistedRunPath = persistedRunPath
  }

  enum CodingKeys: String, CodingKey {
    case schemaVersion
    case workflow
    case phase
    case status
    case runId
    case attemptId
    case resolvedContext
    case contextProvenance
    case actionHistory
    case evidence
    case evidenceCompleteness
    case failure
    case followOnAction
    case persistedRunPath
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.schemaVersion = try container.decode(String.self, forKey: .schemaVersion)
    self.workflow = try container.decode(WorkflowName.self, forKey: .workflow)
    self.phase = try container.decodeIfPresent(WorkflowPhase.self, forKey: .phase)
    self.status = try container.decodeIfPresent(WorkflowStatus.self, forKey: .status)
    self.runId = try container.decodeIfPresent(String.self, forKey: .runId)
    self.attemptId = try container.decodeIfPresent(String.self, forKey: .attemptId)
    self.resolvedContext = try container.decodeIfPresent(
      ResolvedWorkflowContext.self, forKey: .resolvedContext)
    self.contextProvenance = try container.decodeIfPresent(
      WorkflowContextProvenance.self, forKey: .contextProvenance)
    self.actionHistory =
      try container.decodeIfPresent([WorkflowActionRecord].self, forKey: .actionHistory) ?? []
    self.evidence =
      try container.decodeIfPresent([WorkflowEvidenceRecord].self, forKey: .evidence) ?? []
    self.evidenceCompleteness = try container.decodeIfPresent(
      DiagnosisInspectEvidenceCompleteness.self, forKey: .evidenceCompleteness)
    self.failure = try container.decodeIfPresent(WorkflowFailure.self, forKey: .failure)
    self.followOnAction = try container.decodeIfPresent(
      WorkflowFollowOnAction.self, forKey: .followOnAction)
    self.persistedRunPath = try container.decodeIfPresent(String.self, forKey: .persistedRunPath)
  }

  public var isSuccessfulInspection: Bool {
    runId != nil && phase != nil && status != nil && failure == nil
  }

  public var availableEvidence: [WorkflowEvidenceRecord] {
    evidence.filter { $0.availability == .available }
  }

  public var unavailableEvidence: [WorkflowEvidenceRecord] {
    evidence.filter { $0.availability == .unavailable }
  }
}

extension WorkflowEvidenceRecord {
  public var producingWorkflowStep: String {
    switch phase {
    case .diagnosisStart:
      return "diagnosis start"
    case .diagnosisBuild:
      return "build diagnosis"
    case .diagnosisTest:
      return "test diagnosis"
    case .diagnosisRuntime:
      return "runtime diagnosis"
    }
  }

  public var availabilityLabel: String {
    availability.rawValue.replacingOccurrences(of: "_", with: " ")
  }

  public var unavailableReasonLabel: String? {
    guard let unavailableReason else {
      return nil
    }

    switch unavailableReason {
    case .notCaptured:
      return "not captured"
    case .executionFailed:
      return "execution failed"
    case .missingOnDisk:
      return "missing on disk"
    case .unsupported:
      return "unsupported"
    }
  }
}

extension WorkflowRunRecord {
  public var latestSnapshot: WorkflowAttemptSnapshot {
    WorkflowAttemptSnapshot(
      attempt: attempt,
      phase: phase,
      status: status,
      resolvedContext: resolvedContext,
      diagnosisSummary: diagnosisSummary,
      testDiagnosisSummary: testDiagnosisSummary,
      runtimeSummary: runtimeSummary,
      recordedAt: updatedAt
    )
  }

  public var latestRecoveryRecord: WorkflowRecoveryRecord? {
    recoveryHistory.last
  }

  public var backfilledAttemptHistory: [WorkflowAttemptSnapshot] {
    var history = attemptHistory
    let latest = latestSnapshot
    let hasLatest = history.contains { snapshot in
      snapshot.attempt.attemptId == latest.attempt.attemptId
        && snapshot.phase == latest.phase
        && snapshot.recordedAt == latest.recordedAt
    }
    if !hasLatest {
      history.append(latest)
    }
    return history.sorted { lhs, rhs in
      if lhs.recordedAt != rhs.recordedAt {
        return lhs.recordedAt < rhs.recordedAt
      }
      if lhs.attempt.attemptNumber != rhs.attempt.attemptNumber {
        return lhs.attempt.attemptNumber < rhs.attempt.attemptNumber
      }
      return lhs.phase.rawValue < rhs.phase.rawValue
    }
  }

  public func evidence(forAttemptId attemptId: String) -> [WorkflowEvidenceRecord] {
    evidence.filter { $0.attemptId == attemptId }
  }

  public func attemptSnapshot(forAttemptId attemptId: String, phase: WorkflowPhase? = nil)
    -> WorkflowAttemptSnapshot?
  {
    backfilledAttemptHistory.reversed().first { snapshot in
      snapshot.attempt.attemptId == attemptId
        && (phase == nil || snapshot.phase == phase)
    }
  }
}

extension WorkflowRecoveryIssue {
  public var label: String {
    rawValue.replacingOccurrences(of: "_", with: " ")
  }
}

extension WorkflowRecoveryAction {
  public var label: String {
    rawValue.replacingOccurrences(of: "_", with: " ")
  }
}

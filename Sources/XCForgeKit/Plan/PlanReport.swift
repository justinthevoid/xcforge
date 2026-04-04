import Foundation

// MARK: - Step Outcome

public enum StepStatus: String, Codable, Sendable {
  case passed
  case failed
  case skipped
  case suspended
}

public struct StepResult: Codable, Sendable {
  public let index: Int
  public let type: String
  public let status: StepStatus
  public let detail: String?
  public let durationMs: Int
  public let screenshotBase64: String?

  public init(
    index: Int, type: String, status: StepStatus, detail: String?, durationMs: Int,
    screenshotBase64: String? = nil
  ) {
    self.index = index
    self.type = type
    self.status = status
    self.detail = detail
    self.durationMs = durationMs
    self.screenshotBase64 = screenshotBase64
  }
}

// MARK: - Plan Report

public struct PlanReport: Codable, Sendable {
  public let totalSteps: Int
  public let passed: Int
  public let failed: Int
  public let skipped: Int
  public let suspended: Bool
  public let sessionId: String?
  public let suspendQuestion: String?
  public let totalDurationMs: Int
  public let steps: [StepResult]

  public init(steps: [StepResult], sessionId: String? = nil, suspendQuestion: String? = nil) {
    self.steps = steps
    self.totalSteps = steps.count
    self.passed = steps.filter { $0.status == .passed }.count
    self.failed = steps.filter { $0.status == .failed }.count
    self.skipped = steps.filter { $0.status == .skipped }.count
    self.suspended = steps.contains { $0.status == .suspended }
    self.sessionId = sessionId
    self.suspendQuestion = suspendQuestion
    self.totalDurationMs = steps.reduce(0) { $0 + $1.durationMs }
  }

  /// Merge a continuation report (from resume) with prior results.
  public static func merge(prior: [StepResult], continuation: PlanReport) -> PlanReport {
    let merged = prior + continuation.steps
    return PlanReport(
      steps: merged, sessionId: continuation.sessionId,
      suspendQuestion: continuation.suspendQuestion)
  }
}

// MARK: - Suspend Info

public struct SuspendedPlan: Sendable {
  public let steps: [PlanStep]
  public let pauseIndex: Int
  public let question: String
  public let completedResults: [StepResult]
  public let variableBindings: [String: VariableStore.ElementBinding]
  public let errorStrategy: ErrorStrategy
  public let timeoutSeconds: Double
  public let startTime: CFAbsoluteTime
  public let screenshotBase64: String?

  public init(
    steps: [PlanStep],
    pauseIndex: Int,
    question: String,
    completedResults: [StepResult],
    variableBindings: [String: VariableStore.ElementBinding],
    errorStrategy: ErrorStrategy,
    timeoutSeconds: Double,
    startTime: CFAbsoluteTime,
    screenshotBase64: String?
  ) {
    self.steps = steps
    self.pauseIndex = pauseIndex
    self.question = question
    self.completedResults = completedResults
    self.variableBindings = variableBindings
    self.errorStrategy = errorStrategy
    self.timeoutSeconds = timeoutSeconds
    self.startTime = startTime
    self.screenshotBase64 = screenshotBase64
  }
}

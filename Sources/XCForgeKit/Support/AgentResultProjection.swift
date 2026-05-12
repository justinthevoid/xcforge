import Foundation

/// Slim 10-field projection of a test run designed for agent consumption.
/// Encoded JSON omits screenshots, slowest-test arrays, build diagnostics,
/// xcresult paths, and other context-burning fields. `knownFailures` is
/// omitted when nil or empty to keep the wire shape tight.
public struct AgentTestResult: Codable, Sendable, Equatable {
  public let succeeded: Bool
  public let buildOk: Bool
  public let total: Int
  public let passed: Int
  public let failed: Int
  public let skipped: Int
  public let timedOut: Bool
  public let knownFailures: [String]?
  public let failures: [AgentFailure]

  public struct AgentFailure: Codable, Sendable, Equatable {
    public let id: String
    public let message: String
  }

  enum CodingKeys: String, CodingKey {
    case succeeded, buildOk, total, passed, failed, skipped, timedOut, knownFailures, failures
  }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(succeeded, forKey: .succeeded)
    try c.encode(buildOk, forKey: .buildOk)
    try c.encode(total, forKey: .total)
    try c.encode(passed, forKey: .passed)
    try c.encode(failed, forKey: .failed)
    try c.encode(skipped, forKey: .skipped)
    try c.encode(timedOut, forKey: .timedOut)
    if let known = knownFailures, !known.isEmpty {
      try c.encode(known, forKey: .knownFailures)
    }
    try c.encode(failures, forKey: .failures)
  }

  public init(
    succeeded: Bool,
    buildOk: Bool,
    total: Int,
    passed: Int,
    failed: Int,
    skipped: Int,
    timedOut: Bool,
    knownFailures: [String]?,
    failures: [AgentFailure]
  ) {
    self.succeeded = succeeded
    self.buildOk = buildOk
    self.total = total
    self.passed = passed
    self.failed = failed
    self.skipped = skipped
    self.timedOut = timedOut
    self.knownFailures = knownFailures
    self.failures = failures
  }
}

public enum AgentResultProjection {
  /// First non-empty line of a multi-line message, trimmed. Empty input
  /// yields an empty string.
  public static func firstLine(_ message: String) -> String {
    let normalized =
      message
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
    for line in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if !trimmed.isEmpty { return trimmed }
    }
    return ""
  }

  public static func project(_ e: TestTools.TestExecution) -> AgentTestResult {
    let knownSet = Set(e.knownFailures ?? [])
    let visibleFailures = e.failures.filter { !knownSet.contains($0.testIdentifier) }
    let agentFailures = visibleFailures.map {
      AgentTestResult.AgentFailure(id: $0.testIdentifier, message: firstLine($0.message))
    }
    return AgentTestResult(
      succeeded: e.succeeded,
      buildOk: !e.buildFailed,
      total: e.totalTestCount,
      passed: e.passedTestCount,
      failed: agentFailures.count,
      skipped: e.skippedTestCount,
      timedOut: e.xcforgeTimedOut,
      knownFailures: e.knownFailures,
      failures: agentFailures
    )
  }

  public static func project(_ b: TestTools.BuildAndTestResult) -> AgentTestResult {
    if let test = b.testResult {
      var projected = project(test)
      if !b.buildSucceeded {
        projected = AgentTestResult(
          succeeded: false,
          buildOk: false,
          total: projected.total,
          passed: projected.passed,
          failed: projected.failed,
          skipped: projected.skipped,
          timedOut: b.xcforgeTimedOut || projected.timedOut,
          knownFailures: projected.knownFailures,
          failures: projected.failures
        )
      }
      return projected
    }
    // No testResult means tests-were-supposed-to-run-but-didn't (e.g. build failed,
    // test infrastructure failed). Conservatively report `succeeded: false`:
    // a missing test signal must never project as green, regardless of buildOk.
    let known = b.knownFailures
    return AgentTestResult(
      succeeded: false,
      buildOk: b.buildSucceeded,
      total: 0,
      passed: 0,
      failed: 0,
      skipped: 0,
      timedOut: b.xcforgeTimedOut,
      knownFailures: known,
      failures: []
    )
  }
}

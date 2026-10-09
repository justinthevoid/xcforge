import Foundation

/// Slim projection of a test run designed for agent consumption.
/// Encoded JSON omits slowest-test arrays, build diagnostics, xcresult paths,
/// and other context-burning fields. `knownFailures`, `flaky` and `reason` are
/// omitted when empty to keep the wire shape tight.
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
  /// Tests that failed and then passed on a retry. Omitted when empty.
  public let flaky: [String]?
  /// Why the run failed when `failures` can't say: nothing ran, or the runner died.
  public let reason: String?

  /// One failing test. `message` is the first line of its first message; `file` and
  /// `line` locate it, `moreMessages` counts the rest.
  public struct AgentFailure: Codable, Sendable, Equatable {
    public let id: String
    public let message: String
    public let file: String?
    public let line: Int?
    public let moreMessages: Int?
    public let attachments: [String]?

    public init(
      id: String, message: String, file: String? = nil, line: Int? = nil, moreMessages: Int? = nil,
      attachments: [String]? = nil
    ) {
      self.id = id
      self.message = message
      self.file = file
      self.line = line
      self.moreMessages = moreMessages
      self.attachments = attachments
    }
  }

  enum CodingKeys: String, CodingKey {
    case succeeded, buildOk, total, passed, failed, skipped, timedOut, knownFailures, failures, flaky, reason
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
    if let flaky, !flaky.isEmpty {
      try c.encode(flaky, forKey: .flaky)
    }
    try c.encodeIfPresent(reason, forKey: .reason)
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
    failures: [AgentFailure],
    flaky: [String]? = nil,
    reason: String? = nil
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
    self.flaky = flaky
    self.reason = reason
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
    let known = e.knownFailures ?? []
    func isKnown(_ id: String) -> Bool { known.contains { TestIDs.same($0, id) } }
    let visibleFailures = e.failures.filter { !isKnown($0.testIdentifier) }
    let agentFailures = visibleFailures.map { failure -> AgentTestResult.AgentFailure in
      let messages = failure.messages ?? []
      let first = messages.first
      return AgentTestResult.AgentFailure(
        id: failure.testIdentifier,
        message: firstLine(first.map { m in m.label.map { "[\($0)] \(m.text)" } ?? m.text } ?? failure.message),
        file: first?.file,
        line: first?.line,
        moreMessages: messages.count > 1 ? messages.count - 1 : nil,
        attachments: (failure.attachments ?? []).isEmpty ? nil : failure.attachments
      )
    }
    // The real count of failing tests, less the gated ones, even when parsing lost some of them.
    let failed = max(agentFailures.count, e.failedTestCount - known.count)
    var reason: String?
    if !e.succeeded && agentFailures.isEmpty {
      if e.xcforgeTimedOut {
        reason = "timed out before the tests finished"
      } else if e.totalTestCount == 0 {
        reason = "no tests ran: the filter, scheme or test plan selected none"
      } else if failed > 0 {
        reason = "\(failed) tests failed but their details couldn't be read from \(e.xcresultPath)"
      } else {
        reason = e.xcresultParseError ?? "xcodebuild failed without a test failure; see \(e.xcresultPath)"
      }
    }
    return AgentTestResult(
      succeeded: e.succeeded,
      buildOk: !e.buildFailed,
      total: e.totalTestCount,
      passed: e.passedTestCount,
      failed: failed,
      skipped: e.skippedTestCount,
      timedOut: e.xcforgeTimedOut,
      knownFailures: e.knownFailures,
      failures: agentFailures,
      flaky: e.flakyTests.isEmpty ? nil : e.flakyTests,
      reason: reason
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
          failures: projected.failures,
          flaky: projected.flaky,
          reason: projected.reason
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
      failures: [],
      reason: b.buildSucceeded ? "the tests didn't run" : "the build failed"
    )
  }
}

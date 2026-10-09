import Foundation

/// `swift build` / `swift test` output read into the parts agents act on: compiler errors with
/// file and line, failing tests with their messages, and the run summary. The raw output is
/// kept only as a capped tail.
public struct SwiftPMOutput: Codable, Sendable, Equatable {
  public struct Issue: Codable, Sendable, Equatable {
    public let file: String
    public let line: Int
    public let column: Int?
    public let severity: String
    public let message: String

    public var text: String {
      let place = column.map { "\(file):\(line):\($0)" } ?? "\(file):\(line)"
      return "\(place): \(message)"
    }
  }

  public struct TestFailure: Codable, Sendable, Equatable {
    public let test: String
    public let location: String?
    public let message: String
  }

  public var errors: [Issue] = []
  public var warningCount = 0
  public var failures: [TestFailure] = []
  /// Tests executed and failed, from the XCTest and Swift Testing summary lines.
  public var testsRun: Int?
  public var testsFailed: Int?

  /// How many errors and failures a text result lists before giving a count of the rest.
  public static let listLimit = 20
  /// Lines of raw output kept in a result.
  public static let tailLines = 40

  public static func parse(_ output: String) -> SwiftPMOutput {
    var result = SwiftPMOutput()
    var seen = Set<String>()
    var xcTestRun = 0
    var xcTestFailed = 0
    var testingRun: Int?
    var testingFailed = Set<String>()
    for raw in output.split(separator: "\n", omittingEmptySubsequences: true) {
      let line = String(raw).trimmingCharacters(in: .whitespaces)
      if let issue = compilerIssue(line) {
        if issue.severity == "warning" {
          if seen.insert("w:" + issue.text).inserted { result.warningCount += 1 }
        } else if seen.insert(issue.text).inserted {
          result.errors.append(issue)
        }
      } else if let failure = xcTestFailure(line) ?? swiftTestingIssue(line) {
        result.failures.append(failure)
      } else if let counts = xcTestSummary(line) {
        // XCTest prints a summary per suite and a final one; the largest is the total.
        xcTestRun = max(xcTestRun, counts.run)
        xcTestFailed = max(xcTestFailed, counts.failed)
      } else if let run = swiftTestingSummary(line) {
        testingRun = run
      } else if let test = swiftTestingFailedTest(line) {
        testingFailed.insert(test)
      }
    }
    if xcTestRun > 0 || testingRun != nil {
      result.testsRun = xcTestRun + (testingRun ?? 0)
      result.testsFailed = xcTestFailed + testingFailed.count
    }
    return result
  }

  // MARK: - Line shapes

  /// `/path/File.swift:10:5: error: message`
  static func compilerIssue(_ line: String) -> Issue? {
    guard let match = firstMatch(#"^(/[^:]+):(\d+):(\d+): (error|warning): (.*)$"#, in: line), match.count == 6,
      let lineNumber = Int(match[2])
    else { return nil }
    return Issue(file: match[1], line: lineNumber, column: Int(match[3]), severity: match[4], message: match[5])
  }

  /// `/path/FooTests.swift:12: error: -[Module.FooTests testBar] : XCTAssertEqual failed: ...`
  static func xcTestFailure(_ line: String) -> TestFailure? {
    guard let match = firstMatch(#"^(/[^:]+:\d+): error: -\[(\S+) (\S+)\] : (.*)$"#, in: line), match.count == 5
    else { return nil }
    let suite = match[2].split(separator: ".").last.map(String.init) ?? match[2]
    return TestFailure(test: "\(suite)/\(match[3])", location: match[1], message: match[4])
  }

  /// `✘ Test "Name" recorded an issue at FooTests.swift:12:5: Expectation failed: ...`
  /// (the leading symbol differs between terminals, so it isn't matched).
  static func swiftTestingIssue(_ line: String) -> TestFailure? {
    guard let match = firstMatch(#"Test (.+?) recorded an issue at (\S+?:\d+(?::\d+)?): (.*)$"#, in: line),
      match.count == 4
    else { return nil }
    return TestFailure(test: match[1], location: match[2], message: match[3])
  }

  /// `Executed 5 tests, with 1 failure (0 unexpected) in 0.01 (0.02) seconds`
  static func xcTestSummary(_ line: String) -> (run: Int, failed: Int)? {
    guard let match = firstMatch(#"^Executed (\d+) tests?, with (\d+) failures?"#, in: line), match.count == 3,
      let run = Int(match[1]), let failed = Int(match[2])
    else { return nil }
    return (run, failed)
  }

  /// `✘ Test run with 10 tests in 2 suites failed after 0.5 seconds with 3 issues.` / `... passed ...`
  static func swiftTestingSummary(_ line: String) -> Int? {
    guard let match = firstMatch(#"Test run with (\d+) tests?"#, in: line), match.count == 2 else { return nil }
    return Int(match[1])
  }

  /// `✘ Test addsNumbers() failed after 0.001 seconds with 1 issue.`
  static func swiftTestingFailedTest(_ line: String) -> String? {
    guard let match = firstMatch(#"Test (.+?) failed after "#, in: line), match.count == 2 else { return nil }
    return match[1]
  }

  private static func firstMatch(_ pattern: String, in line: String) -> [String]? {
    guard let regex = try? NSRegularExpression(pattern: pattern),
      let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line))
    else { return nil }
    return (0..<match.numberOfRanges).map { index in
      Range(match.range(at: index), in: line).map { String(line[$0]) } ?? ""
    }
  }

  // MARK: - Text

  /// A short account for agents: what failed and where, then the end of the raw output.
  public func summary(action: String, succeeded: Bool, output: String) -> String {
    var lines: [String] = []
    var headline = "\(action) \(succeeded ? "succeeded" : "failed")"
    if let testsRun {
      headline += ": \(testsRun) tests, \(testsFailed ?? 0) failed"
    }
    if warningCount > 0 { headline += " (\(warningCount) warnings)" }
    lines.append(headline)
    if !errors.isEmpty {
      lines.append("Errors (\(errors.count)):")
      lines += errors.prefix(Self.listLimit).map { "  " + $0.text }
      if errors.count > Self.listLimit { lines.append("  ... \(errors.count - Self.listLimit) more") }
    }
    if !failures.isEmpty {
      lines.append("Failed (\(failures.count)):")
      for failure in failures.prefix(Self.listLimit) {
        let place = failure.location.map { " (\($0))" } ?? ""
        lines.append("  \(failure.test)\(place): \(failure.message)")
      }
      if failures.count > Self.listLimit { lines.append("  ... \(failures.count - Self.listLimit) more") }
    }
    // Parsed errors and failures say what matters; a failure with none gets the raw tail.
    if !succeeded && errors.isEmpty && failures.isEmpty {
      let tail = output.split(separator: "\n", omittingEmptySubsequences: true).suffix(Self.tailLines)
      if !tail.isEmpty {
        lines.append("--- last \(tail.count) lines ---")
        lines += tail.map(String.init)
      }
    }
    return CaptureTail.keepEnd(lines.joined(separator: "\n"), limit: 20_000)
  }
}

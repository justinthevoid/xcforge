import MCP
import Testing

@testable import XCForgeKit

// Helper to extract text from a CallTool.Result
private func resultText(_ result: CallTool.Result) -> String {
  guard let first = result.content.first else { return "" }
  if case .text(let text, _, _) = first { return text }
  return ""
}

@Suite("Test Filtering Diagnostics")
struct TestFilteringDiagnosticsTests {

  // MARK: - list_tests filter matching

  private let sampleTests = TestTools.ListTestsResult(
    tests: [
      TestTools.TestIdentifier(
        target: "AppTests", className: "LoginTests", methodName: "testValidLogin",
        fullIdentifier: "AppTests/LoginTests/testValidLogin"),
      TestTools.TestIdentifier(
        target: "AppTests", className: "LoginTests", methodName: "testInvalidLogin",
        fullIdentifier: "AppTests/LoginTests/testInvalidLogin"),
      TestTools.TestIdentifier(
        target: "AppTests", className: "BackfillTests", methodName: "testBackfillCritiques",
        fullIdentifier: "AppTests/BackfillTests/testBackfillCritiques"),
      TestTools.TestIdentifier(
        target: "AppTests", className: "BackfillTests", methodName: "testBackfillPhotos",
        fullIdentifier: "AppTests/BackfillTests/testBackfillPhotos"),
      TestTools.TestIdentifier(
        target: "CoreTests", className: "NetworkTests", methodName: "testFetch",
        fullIdentifier: "CoreTests/NetworkTests/testFetch"),
    ],
    targetCount: 2,
    classCount: 3,
    testCount: 5
  )

  @Test("list_tests without filter shows all tests")
  func listTestsNoFilter() {
    let result = TestTools.formatListTests(sampleTests)
    let text = resultText(result)
    #expect(text.contains("Found 5 tests"))
    #expect(result.isError != true)
  }

  @Test("list_tests with matching filter shows subset")
  func listTestsWithMatchingFilter() {
    let result = TestTools.formatListTests(sampleTests, filter: "Backfill")
    let text = resultText(result)
    #expect(text.contains("Showing 2 of 5 tests matching \"Backfill\""))
    #expect(text.contains("testBackfillCritiques"))
    #expect(text.contains("testBackfillPhotos"))
    #expect(!text.contains("testValidLogin"))
    #expect(result.isError != true)
  }

  @Test("list_tests with filter is case-insensitive")
  func listTestsFilterCaseInsensitive() {
    let result = TestTools.formatListTests(sampleTests, filter: "backfill")
    let text = resultText(result)
    #expect(text.contains("Showing 2 of 5 tests"))
  }

  @Test("list_tests with non-matching filter returns error with suggestions")
  func listTestsFilterNoMatch() {
    let result = TestTools.formatListTests(sampleTests, filter: "NonExistent")
    let text = resultText(result)
    #expect(text.contains("0 tests matched filter \"NonExistent\""))
    #expect(text.contains("out of 5 total tests"))
    #expect(result.isError == true)
  }

  @Test("list_tests with partial class match suggests similar classes")
  func listTestsFilterPartialClassMatch() {
    let result = TestTools.formatListTests(sampleTests, filter: "Login")
    let text = resultText(result)
    #expect(text.contains("Showing 2 of 5 tests matching \"Login\""))
    #expect(text.contains("testValidLogin"))
  }

  // MARK: - formatBuildAndTest testplan display

  private func makeTestResult(totalCount: Int = 3, passedCount: Int = 3, failedCount: Int = 0)
    -> TestTools.BuildAndTestResult
  {
    TestTools.BuildAndTestResult(
      phase: "test",
      buildSucceeded: true,
      buildElapsed: "5.0",
      buildDiagnostics: nil,
      testResult: TestTools.TestExecution(
        succeeded: failedCount == 0,
        elapsed: "2.0",
        xcresultPath: "/tmp/test.xcresult",
        scheme: "App",
        simulator: "iPhone 16",
        totalTestCount: totalCount,
        passedTestCount: passedCount,
        failedTestCount: failedCount,
        skippedTestCount: 0,
        expectedFailureCount: 0,
        failures: [],
        deviceName: nil,
        osVersion: nil,
        screenshotPaths: [],
        hasStructuredSummary: true,
        buildFailed: false,
        buildDiagnostics: nil
      )
    )
  }

  @Test("formatBuildAndTest shows testplan name when provided")
  func buildAndTestShowsTestplan() {
    let result = TestTools.formatBuildAndTest(makeTestResult(), testplan: "quick")
    let text = resultText(result)
    #expect(text.contains("Testplan: quick"))
  }

  @Test("formatBuildAndTest shows 'none' when no testplan")
  func buildAndTestShowsNoTestplan() {
    let result = TestTools.formatBuildAndTest(makeTestResult())
    let text = resultText(result)
    #expect(text.contains("Testplan: (none"))
  }

  @Test("formatBuildAndTest shows filter+testplan warning when both set")
  func buildAndTestFilterTestplanWarning() {
    let result = TestTools.formatBuildAndTest(
      makeTestResult(), testplan: "quick", filter: "SomeTest")
    let text = resultText(result)
    #expect(text.contains("Note: filter and testplan are both set"))
    #expect(text.contains("-only-testing overrides"))
  }

  @Test("formatBuildAndTest does not show warning when only filter is set")
  func buildAndTestNoWarningFilterOnly() {
    let result = TestTools.formatBuildAndTest(makeTestResult(), filter: "SomeTest")
    let text = resultText(result)
    #expect(!text.contains("Note: filter and testplan"))
  }

  @Test("formatBuildAndTest does not show warning when only testplan is set")
  func buildAndTestNoWarningTestplanOnly() {
    let result = TestTools.formatBuildAndTest(makeTestResult(), testplan: "quick")
    let text = resultText(result)
    #expect(!text.contains("Note: filter and testplan"))
  }

  @Test("formatBuildAndTest appends suffix for zero-match hint")
  func buildAndTestZeroMatchSuffix() {
    let result = TestTools.formatBuildAndTest(
      makeTestResult(totalCount: 0, passedCount: 0),
      suffix: "\n\n0 tests matched filter \"Foo\""
    )
    let text = resultText(result)
    #expect(text.contains("0 tests matched filter \"Foo\""))
  }

  // MARK: - Build failure does not show testplan header

  @Test("formatBuildAndTest on build failure does not show testplan")
  func buildFailureNoTestplanHeader() {
    let result = TestTools.formatBuildAndTest(
      TestTools.BuildAndTestResult(
        phase: "build",
        buildSucceeded: false,
        buildElapsed: "10.0",
        buildDiagnostics: [],
        testResult: nil
      ),
      testplan: "quick"
    )
    let text = resultText(result)
    #expect(text.contains("BUILD FAILED"))
    #expect(!text.contains("Testplan:"))
  }

  // MARK: - Test target build failure surfaces diagnostics

  @Test("formatBuildAndTest surfaces test-target build diagnostics when buildFailed is true")
  func testTargetBuildFailureSurfacesDiagnostics() {
    let diagnostics = [
      TestTools.BuildIssueObservation(
        severity: .error,
        message: "Cannot find type 'UIImage' in scope",
        location: SourceLocation(filePath: "Tests/AppTests/ImageTests.swift", line: 12),
        source: "xcresult"
      ),
      TestTools.BuildIssueObservation(
        severity: .warning,
        message: "Variable 'x' was never used",
        location: SourceLocation(filePath: "Tests/AppTests/ImageTests.swift", line: 8),
        source: "xcresult"
      ),
    ]
    let result = TestTools.formatBuildAndTest(
      TestTools.BuildAndTestResult(
        phase: "test",
        buildSucceeded: true,
        buildElapsed: "5.0",
        buildDiagnostics: nil,
        testResult: TestTools.TestExecution(
          succeeded: false,
          elapsed: "3.0",
          xcresultPath: "/tmp/test.xcresult",
          scheme: "App",
          simulator: "iPhone 16",
          totalTestCount: 0,
          passedTestCount: 0,
          failedTestCount: 0,
          skippedTestCount: 0,
          expectedFailureCount: 0,
          failures: [],
          deviceName: nil,
          osVersion: nil,
          screenshotPaths: [],
          hasStructuredSummary: false,
          buildFailed: true,
          buildDiagnostics: diagnostics
        )
      )
    )
    let text = resultText(result)
    #expect(text.contains("TEST TARGET BUILD FAILED"))
    #expect(text.contains("Cannot find type 'UIImage' in scope"))
    #expect(text.contains("Tests/AppTests/ImageTests.swift:12"))
    #expect(text.contains("Errors (1):"))
    #expect(result.isError == true)
  }

  @Test("formatBuildAndTest with buildFailed false shows normal test output")
  func buildNotFailedShowsNormalOutput() {
    let result = TestTools.formatBuildAndTest(
      TestTools.BuildAndTestResult(
        phase: "test",
        buildSucceeded: true,
        buildElapsed: "5.0",
        buildDiagnostics: nil,
        testResult: TestTools.TestExecution(
          succeeded: true,
          elapsed: "2.0",
          xcresultPath: "/tmp/test.xcresult",
          scheme: "App",
          simulator: "iPhone 16",
          totalTestCount: 3,
          passedTestCount: 3,
          failedTestCount: 0,
          skippedTestCount: 0,
          expectedFailureCount: 0,
          failures: [],
          deviceName: nil,
          osVersion: nil,
          screenshotPaths: [],
          hasStructuredSummary: true,
          buildFailed: false,
          buildDiagnostics: nil
        )
      )
    )
    let text = resultText(result)
    #expect(!text.contains("TEST TARGET BUILD FAILED"))
    #expect(text.contains("Tests PASSED"))
    #expect(result.isError != true)
  }
}

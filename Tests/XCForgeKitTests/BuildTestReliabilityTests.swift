import Foundation
import Testing

@testable import XCForgeKit

@Suite("Build and test reliability: errors, runner retries, test listing, test plans")
struct BuildTestReliabilityTests {

  // MARK: - Error extraction

  @Test("duplicate compiler diagnostics collapse to one, keeping order")
  func fallbackIssuesDeduplicate() {
    let output = """
      /src/A.swift:3:5: error: cannot find 'x' in scope
          x += 1
          ^
      /src/A.swift:3:5: error: cannot find 'x' in scope
      /src/B.swift:9:1: error: missing return
      /src/A.swift:3:5: warning: unused value
      """
    let issues = TestTools.fallbackBuildIssues(stderr: output)
    #expect(issues.map(\.message) == ["cannot find 'x' in scope", "missing return", "unused value"])
    #expect(issues.filter { $0.severity == .error }.count == 2)
  }

  @Test("combined output reads compiler errors xcodebuild printed on stdout")
  func combinedOutputIncludesStdout() {
    let result = ShellResult(
      stdout: "/src/A.swift:1:1: error: boom", stderr: "** BUILD FAILED **", exitCode: 65)
    let issues = TestTools.fallbackBuildIssues(stderr: Xcodebuild.combinedOutput(result))
    #expect(issues.count == 1)
    #expect(issues.first?.location?.filePath == "/src/A.swift")
  }

  // MARK: - Runner launch failures

  @Test("runner launch failures are recognised only when no test started")
  func runnerLaunchFailureDetection() {
    #expect(
      TestTools.runnerLaunchFailure(
        "Testing failed:\n\tTest runner hung before establishing connection.") != nil)
    #expect(
      TestTools.runnerLaunchFailure(
        "Early unexpected exit, operation never finished bootstrapping - no restart will be attempted")
        != nil)
    #expect(
      TestTools.runnerLaunchFailure(
        "Test case 'A.b()' passed on 'iPhone'\nFailed to launch app with identifier") == nil)
    #expect(TestTools.runnerLaunchFailure("Testing failed: XCTAssertEqual failed") == nil)
  }

  // MARK: - Test enumeration JSON

  @Test("enumeration JSON yields enabled and disabled identifiers in any nesting")
  func enumerationJSON() throws {
    let json = """
      {"values": [{"testPlan": "Unit",
        "enabledTests": [{"identifier": "AppTests/LoginTests/testLogin"},
                         {"identifier": "AppTests/Parser/Nested/parsesDates()"}],
        "disabledTests": [{"identifier": "AppTests/SlowTests/testSlow"}]}]}
      """
    let parsed = try #require(TestTools.parseTestEnumerationJSON(Data(json.utf8)))
    #expect(parsed.enabled == ["AppTests/LoginTests/testLogin", "AppTests/Parser/Nested/parsesDates()"])
    #expect(parsed.disabled == ["AppTests/SlowTests/testSlow"])
  }

  @Test("identifiers split into target, suite and test, keeping the exact form")
  func identifierSplitting() throws {
    let swiftTesting = try #require(TestTools.testIdentifier(from: "AppTests/Parser/Nested/parsesDates()"))
    #expect(swiftTesting.target == "AppTests")
    #expect(swiftTesting.className == "Parser/Nested")
    #expect(swiftTesting.methodName == "parsesDates")
    #expect(swiftTesting.fullIdentifier == "AppTests/Parser/Nested/parsesDates()")
    let suiteOnly = try #require(TestTools.testIdentifier(from: "AppTests/Parser"))
    #expect(suiteOnly.className == "Parser")
    #expect(TestTools.testIdentifier(from: "AppTests") == nil)
  }

  // MARK: - Test plans

  @Test("Xcode's string skippedTests and missing sections decode")
  func testPlanXcodeFormat() throws {
    let json = """
      {
        "configurations": [{"id": "1", "name": "Config 1", "options": {}}],
        "defaultOptions": {},
        "testTargets": [{
          "skippedTests": ["SlowTests", "LoginTests/testFlaky()"],
          "target": {"containerPath": "container:App.xcodeproj", "identifier": "X", "name": "AppTests"}
        }],
        "version": 1
      }
      """
    let plan = try JSONDecoder().decode(XCTestPlan.self, from: Data(json.utf8))
    #expect(plan.testTargets.first?.skippedTests?.map(\.identifier) == ["SlowTests", "LoginTests/testFlaky()"])
    let minimal = try JSONDecoder().decode(XCTestPlan.self, from: Data(#"{"version": 1}"#.utf8))
    #expect(minimal.testTargets.isEmpty)
  }

  @Test("tag settings are reported verbatim and multi-tag filters are flagged")
  func testPlanTags() throws {
    let json = """
      {"defaultOptions": {"testTags": {"included": ["fast", "unit"], "matchAll": true}},
       "testTargets": [{"target": {"name": "AppTests"}, "skippedTags": ["slow"]}]}
      """
    let raw = try JSONSerialization.jsonObject(with: Data(json.utf8))
    let settings = TestPlanInspector.tagSettings(in: raw)
    #expect(settings.contains { $0.hasPrefix("defaultOptions.testTags:") && $0.contains("fast") })
    #expect(settings.contains { $0.hasPrefix("testTargets[0].skippedTags:") })
    #expect(TestPlanInspector.hasMultiTagFilter(settings))
    #expect(!TestPlanInspector.hasMultiTagFilter(["testTargets[0].skippedTags: [\"slow\"]"]))
  }

  @Test("shared plans inside the .xcodeproj bundle are found")
  func testPlanInsideProjectBundle() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("xcforge-plan-\(UUID().uuidString)")
    let project = root.appendingPathComponent("App.xcodeproj")
    let plans = project.appendingPathComponent("xcshareddata/xctestplans", isDirectory: true)
    try FileManager.default.createDirectory(at: plans, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try #"{"version": 1, "testTargets": [{"target": {"name": "AppTests"}}]}"#.write(
      to: plans.appendingPathComponent("Unit.xctestplan"), atomically: true, encoding: .utf8)

    let summary = try await TestPlanInspector.inspectTestPlan(
      name: "Unit", project: project.path, env: .live)
    #expect(summary.contains("AppTests"))
  }
}

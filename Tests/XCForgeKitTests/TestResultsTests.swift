import Foundation
import Testing

@testable import XCForgeKit

@Suite("Test results: IDs, messages, reruns and output", .serialized)
struct TestResultsTests {

  private func json(_ text: String) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]) ?? [:]
  }

  private func tempDir() -> String {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("xcforge-results-\(UUID().uuidString)", isDirectory: true).path
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    return dir
  }

  // MARK: - One ID format

  @Test("canonical IDs carry the target once, and doubled parens are collapsed")
  func canonicalIDs() {
    #expect(TestIDs.canonical(target: "AppTests", identifier: "Parser/parses()") == "AppTests/Parser/parses()")
    #expect(TestIDs.canonical(target: "AppTests", identifier: "AppTests/Parser/parses()") == "AppTests/Parser/parses()")
    #expect(TestIDs.canonical(target: nil, identifier: "Parser/parses()()") == "Parser/parses()")
  }

  @Test("same() accepts short forms but never a different test with a common prefix")
  func sameTest() {
    #expect(TestIDs.same("AppTests/Parser/parses()", "Parser/parses()"))
    #expect(TestIDs.same("AppTests/Parser/parses()", "Parser/parses"))
    #expect(TestIDs.same("AppTests/Parser/parses()()", "AppTests/Parser/parses()"))
    #expect(!TestIDs.same("AppTests/Parser/testFoo", "AppTests/Parser/testFoo2"))
    #expect(!TestIDs.same("AppTests/Parser/testFoo", "Foo"))
    #expect(!TestIDs.same("", "Foo"))
  }

  @Test("the -only-testing spelling doubles () once, only for target-qualified IDs")
  func onlyTestingSpelling() {
    #expect(TestIDs.onlyTestingArgument("AppTests/Parser/parses()") == "AppTests/Parser/parses()()")
    #expect(TestIDs.onlyTestingArgument("AppTests/Parser/parses()()") == "AppTests/Parser/parses()()")
    #expect(TestIDs.onlyTestingArgument("Parser/parses()") == "Parser/parses()")
    #expect(TestIDs.onlyTestingArgument("AppTests/Parser/testFoo") == "AppTests/Parser/testFoo")
  }

  @Test("components ignore slashes inside arguments")
  func idComponents() {
    #expect(TestIDs.components("T/Suite/test(path: \"a/b\")").count == 3)
    #expect(TestIDs.components("T/Suite/test[a/b]").count == 3)
  }

  @Test("short filters get the target; nested suites too when the target list is exact")
  func qualifyFilters() {
    #expect(TestTools.qualify("Parser/parses()", targets: ["AppTests"]) == "AppTests/Parser/parses()")
    #expect(TestTools.qualify("AppTests/Parser", targets: ["AppTests"]) == "AppTests/Parser")
    #expect(TestTools.qualify("Outer/Inner/test()", targets: ["AppTests"]) == "AppTests/Outer/Inner/test()")
    // A guessed target list never rewrites an ID that may already be complete.
    #expect(TestTools.qualify("Other/Suite/test()", targets: ["AppTests"], exact: false) == "Other/Suite/test()")
    #expect(TestTools.qualify("Parser/parses()", targets: ["A", "B"]) == "Parser/parses()")
    #expect(TestTools.qualify("Parser/parses()", targets: []) == "Parser/parses()")
  }

  // MARK: - Test targets from the scheme

  @Test("scheme test targets come from enabled testables")
  func schemeTestables() {
    let xml = """
      <Scheme><BuildAction><BuildActionEntries><BuildActionEntry><BuildableReference
         BlueprintName = "App"></BuildableReference></BuildActionEntry></BuildActionEntries></BuildAction>
      <TestAction buildConfiguration = "Debug">
        <Testables>
          <TestableReference
             skipped = "NO"
             parallelizable = "YES">
             <BuildableReference
                BuildableIdentifier = "primary"
                BlueprintName = "AppTests">
             </BuildableReference>
          </TestableReference>
          <TestableReference
             skipped = "YES">
             <BuildableReference
                BlueprintName = "SlowTests">
             </BuildableReference>
          </TestableReference>
          <TestableReference
             skipped = "NO">
             <BuildableReference
                BlueprintName = "AppUITests">
             </BuildableReference>
          </TestableReference>
        </Testables>
      </TestAction>
      </Scheme>
      """
    #expect(SchemeFile.testTargets(schemeXML: xml, projectDirectory: "/tmp") == ["AppTests", "AppUITests"])
  }

  @Test("scheme test targets come from its test plan when it has one")
  func schemeTestPlan() throws {
    let dir = tempDir()
    defer { try? FileManager.default.removeItem(atPath: dir) }
    let plan = """
      {"version": 1, "testTargets": [
        {"target": {"name": "AppTests", "containerPath": "container:App.xcodeproj"}},
        {"enabled": false, "target": {"name": "OffTests"}}
      ]}
      """
    try plan.write(toFile: "\(dir)/Quick.xctestplan", atomically: true, encoding: .utf8)
    let xml = """
      <Scheme><TestAction><TestPlans>
        <TestPlanReference reference = "container:Quick.xctestplan" default = "YES"></TestPlanReference>
      </TestPlans></TestAction></Scheme>
      """
    #expect(SchemeFile.testTargets(schemeXML: xml, projectDirectory: dir) == ["AppTests"])
  }

  // MARK: - Every message, with location

  private let detailsJSON = """
    {"testNodes": [{"nodeType": "Test Plan", "name": "Quick", "children": [
      {"nodeType": "Unit test bundle", "name": "AppTests", "children": [
        {"nodeType": "Test Suite", "name": "Outer", "children": [
          {"nodeType": "Test Suite", "name": "Inner", "children": [
            {"nodeType": "Test Case", "name": "parses(input:)", "nodeIdentifier": "Outer/Inner/parses(input:)",
             "result": "Failed", "children": [
              {"nodeType": "Arguments", "name": "\\"a\\"", "result": "Passed", "children": []},
              {"nodeType": "Arguments", "name": "\\"b\\"", "result": "Failed", "children": [
                {"nodeType": "Failure Message", "name": "ParserTests.swift:42: Expectation failed: 1 == 2"}
              ]},
              {"nodeType": "Arguments", "name": "\\"c\\"", "result": "Failed", "children": [
                {"nodeType": "Failure Message", "name": "ParserTests.swift:43: Expectation failed: x"}
              ]}
            ]}
          ]},
          {"nodeType": "Test Case", "name": "retried()", "nodeIdentifier": "Outer/retried()", "result": "Passed",
           "children": [
            {"nodeType": "Repetition", "name": "Retry 1", "result": "Failed", "children": []},
            {"nodeType": "Repetition", "name": "Retry 2", "result": "Passed", "children": []}
          ]},
          {"nodeType": "Test Case", "name": "noMessage()", "nodeIdentifier": "Outer/noMessage()", "result": "Failed"}
        ]}
      ]}
    ]}]}
    """

  @Test("failures carry the full ID and every message with file, line and argument")
  func failureMessages() {
    let failures = TestTools.parseTestFailures(json(detailsJSON))
    #expect(failures.count == 2)
    let parameterized = failures[0]
    #expect(parameterized.testIdentifier == "AppTests/Outer/Inner/parses(input:)")
    let messages = parameterized.messages ?? []
    #expect(messages.count == 2)
    #expect(messages.first?.file == "ParserTests.swift")
    #expect(messages.first?.line == 42)
    #expect(messages.first?.label == "\"b\"")
    #expect(messages.first?.text == "Expectation failed: 1 == 2")
    #expect(parameterized.message.contains("[\"c\"] ParserTests.swift:43: Expectation failed: x"))
    #expect(failures[1].testIdentifier == "AppTests/Outer/noMessage()")
    #expect(failures[1].messages == nil)
  }

  @Test("tests that passed on a retry are reported as flaky")
  func flakyTests() {
    #expect(TestTools.parseFlakyTests(json(detailsJSON)) == ["AppTests/Outer/retried()"])
  }

  @Test("message locations are split out only when present")
  func messageParsing() {
    let located = FailureMessage.parse("Sources/Thing.swift:7: XCTAssertEqual failed: (\"1\") is not equal to (\"2\")")
    #expect(located.file == "Sources/Thing.swift")
    #expect(located.line == 7)
    #expect(located.text.hasPrefix("XCTAssertEqual failed"))
    let plain = FailureMessage.parse("Test crashed with signal SEGV")
    #expect(plain.file == nil)
    #expect(plain.text == "Test crashed with signal SEGV")
    #expect(FailureMessage(text: "boom", file: "A.swift", line: 3, label: "x").display == "[x] A.swift:3: boom")
  }

  // MARK: - Test step options

  @Test("test options become test-step arguments")
  func testOptionArguments() throws {
    #expect(
      try TestTools.TestRunOptions(retries: 2).arguments()
        == ["-retry-tests-on-failure", "-test-iterations", "3"])
    #expect(try TestTools.TestRunOptions(iterations: 5).arguments() == ["-test-iterations", "5"])
    #expect(
      try TestTools.TestRunOptions(parallel: false, testTimeoutSeconds: 30).arguments()
        == [
          "-parallel-testing-enabled", "NO", "-test-timeouts-enabled", "YES",
          "-default-test-execution-time-allowance", "30", "-maximum-test-execution-time-allowance", "30",
        ])
    #expect(try TestTools.TestRunOptions().arguments().isEmpty)
    #expect(throws: TestTools.TestRunOptions.InvalidError.self) {
      try TestTools.TestRunOptions(retries: 1, iterations: 3).arguments()
    }
  }

  // MARK: - Console and attachments per failure

  @Test("console output is keyed by test and keeps the last lines whatever they say")
  func consoleTail() {
    let lines = (1...60).map { "line \($0)" }.joined(separator: "\\n")
    let log = """
      {"subsections": [
        {"testDetails": {"testIdentifier": "Parser/parses()", "testName": "parses()",
                         "emittedOutput": "◇ Test parses() started.\\n\(lines)"}},
        {"testDetails": {"testName": "testFoo2", "emittedOutput": "other test"}}
      ]}
      """
    let console = TestTools.parseTestConsole(Data(log.utf8))
    let parses = TestTools.console(for: "AppTests/Parser/parses()", in: console)
    #expect(parses?.hasSuffix("line 60") == true)
    #expect(parses?.contains("line 20") == false)
    #expect(parses?.contains("◇ Test") == false)
    #expect(TestTools.console(for: "AppTests/Suite/testFoo", in: console) == nil)
  }

  @Test("attachments go to their own failure, not to a test with a longer name")
  func attachmentsPerFailure() {
    let failures = [
      TestTools.TestFailureObservation(
        testName: "testFoo", testIdentifier: "AppTests/Suite/testFoo", message: "a", source: "x"),
      TestTools.TestFailureObservation(
        testName: "testFoo2", testIdentifier: "AppTests/Suite/testFoo2", message: "b", source: "x"),
    ]
    let attached = TestTools.attach(
      attachments: [(test: "Suite/testFoo2", path: "/tmp/b.png")], console: [:], to: failures)
    #expect(attached[0].attachments == nil)
    #expect(attached[1].attachments == ["/tmp/b.png"])
  }

  // MARK: - Bounded output

  @Test("text output groups identical messages and caps the list")
  func cappedOutput() {
    var failures = (1...30).map {
      TestTools.TestFailureObservation(
        testName: "t\($0)", testIdentifier: "AppTests/Suite/t\($0)()", message: "distinct \($0)", source: "x")
    }
    failures += (1...3).map {
      TestTools.TestFailureObservation(
        testName: "s\($0)", testIdentifier: "AppTests/Setup/s\($0)()", message: "setUp failed", source: "x")
    }
    let lines = TestFailureText.lines(failures, limit: 20)
    #expect(lines.filter { $0.contains("FAIL:") }.count == 20)
    #expect(lines.last?.contains("+13 more failures") == true)

    let grouped = TestFailureText.lines(Array(failures.suffix(3)))
    #expect(grouped.first?.contains("3 tests, same message") == true)
    #expect(grouped.filter { $0.contains("FAIL:") }.count == 1)
  }

  // MARK: - Agent JSON

  @Test("agent failures carry file and line; counts agree with the summary")
  func agentProjection() throws {
    var failure = TestTools.TestFailureObservation(
      testName: "parses()", testIdentifier: "AppTests/Parser/parses()",
      message: "P.swift:4: first\nP.swift:9: second", source: "x")
    failure.messages = [
      FailureMessage(text: "first", file: "P.swift", line: 4),
      FailureMessage(text: "second", file: "P.swift", line: 9),
    ]
    let execution = TestTools.TestExecution(
      succeeded: false, elapsed: "1", xcresultPath: "/tmp/r.xcresult", scheme: "App", simulator: "iPhone",
      totalTestCount: 5, passedTestCount: 2, failedTestCount: 3, skippedTestCount: 0, expectedFailureCount: 0,
      failures: [failure], deviceName: nil, osVersion: nil, screenshotPaths: [], hasStructuredSummary: true,
      buildFailed: false, buildDiagnostics: nil, flakyTests: ["AppTests/Parser/flaky()"])
    let projected = AgentResultProjection.project(execution)
    #expect(projected.failed == 3)
    #expect(projected.failures[0].file == "P.swift")
    #expect(projected.failures[0].line == 4)
    #expect(projected.failures[0].message == "first")
    #expect(projected.failures[0].moreMessages == 1)
    #expect(projected.flaky == ["AppTests/Parser/flaky()"])
    #expect(projected.reason == nil)
  }

  @Test("a failed run with no failures says why")
  func agentReason() {
    let execution = TestTools.TestExecution(
      succeeded: false, elapsed: "1", xcresultPath: "/tmp/r.xcresult", scheme: "App", simulator: "iPhone",
      totalTestCount: 0, passedTestCount: 0, failedTestCount: 0, skippedTestCount: 0, expectedFailureCount: 0,
      failures: [], deviceName: nil, osVersion: nil, screenshotPaths: [], hasStructuredSummary: true,
      buildFailed: false, buildDiagnostics: nil)
    let projected = AgentResultProjection.project(execution)
    #expect(projected.reason?.contains("no tests ran") == true)
  }

  // MARK: - Reruns

  @Test("a run that failed before any test reported records that, so rerun refuses")
  func infraFailureRecord() {
    let root = tempDir()
    defer { try? FileManager.default.removeItem(atPath: root) }
    _ = LastFailuresStore.write(failures: ["AppTests/Old/test()"], scheme: "S", simulator: "Sim", at: root)
    let crash = TestTools.TestFailureObservation(
      testName: "xcodebuild", testIdentifier: "xcodebuild", message: "Test runner crashed\nmore", source: "stderr")
    TestTools.persistLastFailures(
      failures: [crash], succeeded: false, scheme: "S", simulator: "Sim", repoRoot: root,
      run: LastFailuresStore.RunSettings(project: "/p/App.xcodeproj", testPlan: "Quick", env: ["A=1"]))
    let payload = LastFailuresStore.read(at: root)
    #expect(payload?.failures.isEmpty == true)
    #expect(payload?.infraFailure == "Test runner crashed")
    #expect(payload?.run?.testPlan == "Quick")
    #expect(payload?.run?.env == ["A=1"])
  }

  @Test("an old last-failures file without run settings still reads")
  func legacyPayload() throws {
    let root = tempDir()
    defer { try? FileManager.default.removeItem(atPath: root) }
    let dir = (root as NSString).appendingPathComponent(".xcforge")
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    try #"{"failures": ["A/b"], "scheme": "S", "recordedAt": "2026-10-01T00:00:00Z"}"#
      .write(toFile: LastFailuresStore.path(at: root), atomically: true, encoding: .utf8)
    let payload = LastFailuresStore.read(at: root)
    #expect(payload?.failures == ["A/b"])
    #expect(payload?.run == nil)
    #expect(payload?.infraFailure == nil)
  }

  @Test("a test build is current until a source changes or the settings differ")
  func testBuildFreshness() throws {
    let root = tempDir()
    defer { try? FileManager.default.removeItem(atPath: root) }
    let source = (root as NSString).appendingPathComponent("Thing.swift")
    try "let a = 1".write(toFile: source, atomically: true, encoding: .utf8)
    let old = Date().addingTimeInterval(-120)
    try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: source)
    let project = (root as NSString).appendingPathComponent("App-\(UUID().uuidString).xcodeproj")
    defer { try? FileManager.default.removeItem(atPath: LastResultStore.filePath(for: project)) }

    let key = LastResultStore.testBuildKey(
      scheme: "App", configuration: "Debug", coverage: false, physicalDevice: false)
    LastResultStore.recordTestBuild(project: project, key: key, now: Date().addingTimeInterval(-60))
    #expect(LastResultStore.testBuildIsCurrent(project: project, key: key, sourceRoot: root))

    let other = LastResultStore.testBuildKey(
      scheme: "App", configuration: "Release", coverage: false, physicalDevice: false)
    #expect(!LastResultStore.testBuildIsCurrent(project: project, key: other, sourceRoot: root))

    try "let a = 2".write(toFile: source, atomically: true, encoding: .utf8)
    #expect(!LastResultStore.testBuildIsCurrent(project: project, key: key, sourceRoot: root))
  }
}

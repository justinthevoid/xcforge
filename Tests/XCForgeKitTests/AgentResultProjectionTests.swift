import Foundation
import Testing

@testable import XCForgeKit

@Suite("AgentResultProjection: slim shape contract", .serialized)
struct AgentResultProjectionTests {

  private func makeExecution(
    succeeded: Bool = true,
    total: Int = 10,
    passed: Int = 10,
    failed: Int = 0,
    skipped: Int = 0,
    failures: [TestTools.TestFailureObservation] = [],
    timedOut: Bool = false,
    buildFailed: Bool = false,
    knownFailures: [String]? = nil
  ) -> TestTools.TestExecution {
    TestTools.TestExecution(
      succeeded: succeeded,
      elapsed: "1.2",
      xcresultPath: "/tmp/x.xcresult",
      scheme: "App",
      simulator: "iPhone 16",
      totalTestCount: total,
      passedTestCount: passed,
      failedTestCount: failed,
      skippedTestCount: skipped,
      expectedFailureCount: 0,
      failures: failures,
      deviceName: "iPhone 16",
      osVersion: "18.0",
      screenshotPaths: [
        TestTools.ScreenshotAttachment(testName: "x", path: "/tmp/shot.png")
      ],
      hasStructuredSummary: true,
      buildFailed: buildFailed,
      buildDiagnostics: nil,
      hangDiagnosticPath: nil,
      hangDiagnosticSummary: nil,
      xcresultParseError: nil,
      xcforgeTimedOut: timedOut,
      slowestTests: [TestTools.SlowTest(testName: "x", elapsedSeconds: 9.0)],
      knownFailures: knownFailures
    )
  }

  @Test("green run projects to the locked 8-key shape (no knownFailures)")
  func greenShape() throws {
    let exec = makeExecution()
    let projected = AgentResultProjection.project(exec)
    let json = try WorkflowJSONRenderer.renderJSON(projected)
    let obj = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
    let keys = Set(obj.keys)
    #expect(keys == ["succeeded", "buildOk", "total", "passed", "failed", "skipped", "timedOut", "failures"])
    #expect(keys.count <= 10)
  }

  @Test("encoded JSON has only the locked agent-shape keys at the top level")
  func slimKeys() throws {
    // Locked allowed set per spec — `knownFailures` is optional so the ceiling is 9.
    let allowed: Set<String> = [
      "succeeded", "buildOk", "total", "passed", "failed", "skipped",
      "timedOut", "knownFailures", "failures",
    ]
    let exec = makeExecution(knownFailures: ["Suite/k"])
    let json = try WorkflowJSONRenderer.renderTestJSON(exec, forAgent: true)
    let obj = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
    let keys = Set(obj.keys)
    #expect(keys.isSubset(of: allowed))
    #expect(keys.count <= 9)
  }

  @Test("all failures gated → succeeded preserved, failed:0, knownFailures populated")
  func allKnownGated() throws {
    // Simulates a post-gating execution: input has `succeeded: true` because
    // every failure matched the registry. Projection must keep it green.
    let exec = makeExecution(
      succeeded: true,
      total: 3,
      passed: 2,
      failed: 1,
      failures: [
        TestTools.TestFailureObservation(
          testName: "x", testIdentifier: "Suite/known", message: "expected", source: "x")
      ],
      knownFailures: ["Suite/known"])
    let projected = AgentResultProjection.project(exec)
    #expect(projected.succeeded == true)
    #expect(projected.failed == 0)
    #expect(projected.knownFailures == ["Suite/known"])
    #expect(projected.failures.isEmpty)
  }

  @Test("BuildAndTestResult with testResult == nil projects succeeded:false")
  func nilTestResultIsNotGreen() {
    // Even when buildSucceeded is true, a missing testResult means tests were
    // expected but didn't run — must never project as green.
    let result = TestTools.BuildAndTestResult(
      phase: "test",
      buildSucceeded: true,
      buildElapsed: "1.0",
      buildDiagnostics: nil,
      testResult: nil)
    let projected = AgentResultProjection.project(result)
    #expect(projected.succeeded == false)
    #expect(projected.buildOk == true)
  }

  @Test("failure message is trimmed to the first non-empty line")
  func firstLineTrimming() {
    let multi = "\n\n  first line  \nsecond line\nthird"
    #expect(AgentResultProjection.firstLine(multi) == "first line")
  }

  @Test("failures project to {id, message} pairs with first-line messages")
  func failureProjection() {
    let exec = makeExecution(
      succeeded: false,
      total: 3,
      passed: 2,
      failed: 1,
      failures: [
        TestTools.TestFailureObservation(
          testName: "x",
          testIdentifier: "Suite/testFails",
          message: "expected 1, got 2\nstacktrace line\nmore",
          source: "x")
      ])
    let projected = AgentResultProjection.project(exec)
    #expect(projected.failures.count == 1)
    #expect(projected.failures[0].id == "Suite/testFails")
    #expect(projected.failures[0].message == "expected 1, got 2")
  }

  @Test("knownFailures present when gated; omitted from JSON when empty")
  func knownFailuresOmission() throws {
    let withKnown = makeExecution(knownFailures: ["Suite/known"])
    let projected = AgentResultProjection.project(withKnown)
    #expect(projected.knownFailures == ["Suite/known"])
    let json = try WorkflowJSONRenderer.renderJSON(projected)
    #expect(json.contains("knownFailures"))

    let empty = AgentTestResult(
      succeeded: true, buildOk: true, total: 1, passed: 1, failed: 0,
      skipped: 0, timedOut: false, knownFailures: [], failures: [])
    let emptyJSON = try WorkflowJSONRenderer.renderJSON(empty)
    #expect(!emptyJSON.contains("knownFailures"))
  }

  @Test("buildOk reflects buildFailed inversion")
  func buildOk() {
    let buildFail = makeExecution(succeeded: false, buildFailed: true)
    #expect(AgentResultProjection.project(buildFail).buildOk == false)
    let ok = makeExecution()
    #expect(AgentResultProjection.project(ok).buildOk == true)
  }

  @Test("BuildAndTestResult with build failure projects buildOk:false")
  func buildAndTestProjection() {
    let result = TestTools.BuildAndTestResult(
      phase: "build",
      buildSucceeded: false,
      buildElapsed: "2.0",
      buildDiagnostics: nil,
      testResult: nil)
    let projected = AgentResultProjection.project(result)
    #expect(projected.buildOk == false)
    #expect(projected.succeeded == false)
  }
}

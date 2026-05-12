import Foundation
import Testing

@testable import XCForgeKit

@Suite("TestProvider.applyGating: known-failures gate semantics", .serialized)
struct TestProviderGatingTests {

  private func makeRoot(with contents: String?) -> URL {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("xcforge-gate-\(UUID().uuidString)", isDirectory: true)
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    if let contents {
      let cfgDir = dir.appendingPathComponent(".xcforge")
      try! FileManager.default.createDirectory(at: cfgDir, withIntermediateDirectories: true)
      try! contents.write(
        to: cfgDir.appendingPathComponent("known-failures.yaml"),
        atomically: true, encoding: .utf8)
    }
    return dir
  }

  private func cleanup(_ dir: URL) { try? FileManager.default.removeItem(at: dir) }

  private func failure(_ id: String) -> TestTools.TestFailureObservation {
    TestTools.TestFailureObservation(
      testName: id, testIdentifier: id, message: "boom", source: "x")
  }

  @Test("gate off is a no-op regardless of registry contents")
  func gateOff() {
    let root = makeRoot(with: "- id: A/b\n  reason: r\n  first_seen: 2026-01-01\n")
    defer { cleanup(root) }
    let outcome = TestTools.applyGating(
      gate: false, failures: [failure("A/b")], repoRoot: root.path)
    #expect(outcome.matchedIDs.isEmpty)
    #expect(outcome.allKnown == false)
  }

  @Test("all failures known → allKnown true, matchedIDs populated")
  func allKnown() {
    let root = makeRoot(
      with: """
        - id: A/b
          reason: r
          first_seen: 2026-01-01
        - id: C/d
          reason: r
          first_seen: 2026-01-02
        """)
    defer { cleanup(root) }
    let outcome = TestTools.applyGating(
      gate: true, failures: [failure("A/b"), failure("C/d")], repoRoot: root.path)
    #expect(outcome.matchedIDs == ["A/b", "C/d"])
    #expect(outcome.allKnown)
  }

  @Test("mixed known + unknown → allKnown false but matched still listed")
  func mixed() {
    let root = makeRoot(
      with: "- id: Known/one\n  reason: r\n  first_seen: 2026-01-01\n")
    defer { cleanup(root) }
    let outcome = TestTools.applyGating(
      gate: true, failures: [failure("Known/one"), failure("Unknown/two")],
      repoRoot: root.path)
    #expect(outcome.matchedIDs == ["Known/one"])
    #expect(outcome.allKnown == false)
  }

  @Test("missing registry → gate is a no-op")
  func missingRegistry() {
    let root = makeRoot(with: nil)
    defer { cleanup(root) }
    let outcome = TestTools.applyGating(
      gate: true, failures: [failure("A/b")], repoRoot: root.path)
    #expect(outcome.matchedIDs.isEmpty)
    #expect(outcome.allKnown == false)
    #expect(outcome.warning == nil)
  }

  @Test("xcodebuild infra failures are excluded from gating")
  func xcodebuildExcluded() {
    let root = makeRoot(
      with: "- id: A/b\n  reason: r\n  first_seen: 2026-01-01\n")
    defer { cleanup(root) }
    let infra = TestTools.TestFailureObservation(
      testName: "xcodebuild", testIdentifier: "xcodebuild",
      message: "build err", source: "stderr")
    let outcome = TestTools.applyGating(
      gate: true, failures: [infra, failure("A/b")], repoRoot: root.path)
    #expect(outcome.allKnown)
    #expect(outcome.matchedIDs == ["A/b"])
  }

  @Test("persistLastFailures writes file when failures exist")
  func persistOnRedRun() {
    let root = makeRoot(with: nil)
    defer { cleanup(root) }
    TestTools.persistLastFailures(
      failures: [failure("A/b"), failure("C/d")], succeeded: false,
      scheme: "S", simulator: "Sim", repoRoot: root.path)
    let payload = LastFailuresStore.read(at: root.path)
    #expect(payload?.failures == ["A/b", "C/d"])
    #expect(payload?.scheme == "S")
  }

  @Test("persistLastFailures clears file on green run")
  func clearOnGreen() {
    let root = makeRoot(with: nil)
    defer { cleanup(root) }
    _ = LastFailuresStore.write(
      failures: ["old/test"], scheme: nil, simulator: nil, at: root.path)
    TestTools.persistLastFailures(
      failures: [], succeeded: true,
      scheme: "S", simulator: "Sim", repoRoot: root.path)
    #expect(LastFailuresStore.read(at: root.path) == nil)
  }

  @Test("gating requires matched count to cover failedTestCount (parse-loss guard)")
  func gatingCoversAllFailures() {
    let root = makeRoot(
      with: "- id: A/b\n  reason: r\n  first_seen: 2026-01-01\n")
    defer { cleanup(root) }
    // Registry knows A/b. Observed failures include A/b, but failedTestCount=2
    // (the second was lost during xcresult parse). Gate must NOT rescue this run.
    let outcome = TestTools.applyGating(
      gate: true, failures: [failure("A/b")], failedTestCount: 2, repoRoot: root.path)
    #expect(outcome.matchedIDs == ["A/b"])
    #expect(outcome.allKnown == false)
  }

  @Test("persistLastFailures clears file when gate && allKnown (avoids rerun replay)")
  func gateAllKnownClears() {
    let root = makeRoot(with: nil)
    defer { cleanup(root) }
    // Pre-seed a stale failures file.
    _ = LastFailuresStore.write(
      failures: ["stale/test"], scheme: nil, simulator: nil, at: root.path)
    TestTools.persistLastFailures(
      failures: [failure("Known/one")], succeeded: false,
      scheme: "S", simulator: "Sim", repoRoot: root.path,
      gateAllKnown: true)
    #expect(LastFailuresStore.read(at: root.path) == nil)
  }

  @Test("splitFilterList preserves commas inside parens (Swift Testing arguments)")
  func splitParensAware() {
    let ids = TestTools.splitFilterList("Suite/test(arg1,arg2),Other/x")
    #expect(ids == ["Suite/test(arg1,arg2)", "Other/x"])
  }

  @Test("rerun-failed: two recorded IDs round-trip into exactly two -only-testing args")
  func rerunArgsFromPayload() throws {
    let root = makeRoot(with: nil)
    defer { cleanup(root) }
    _ = LastFailuresStore.write(
      failures: ["TargetA/SuiteA/testOne", "TargetB/SuiteB/test(arg,with,commas)"],
      scheme: "S", simulator: "Sim", at: root.path)
    guard let payload = LastFailuresStore.read(at: root.path) else {
      Issue.record("payload missing")
      return
    }
    #expect(payload.failures.count == 2)

    // Simulate the rerun execution path: failures pass as a list, get rejoined
    // (the executeTest path does `joined(separator: ",")`), then `splitFilterList`
    // reproduces the original IDs verbatim — yielding exactly 2 -only-testing args.
    let joined = payload.failures.joined(separator: ",")
    let split = TestTools.splitFilterList(joined)
    #expect(split.count == 2)
    #expect(split[0] == "TargetA/SuiteA/testOne")
    #expect(split[1] == "TargetB/SuiteB/test(arg,with,commas)")
  }

  @Test("project() with gated execution leaves raw failures[] untouched in human mode")
  func humanModeRawFailures() throws {
    let exec = TestTools.TestExecution(
      succeeded: true,
      elapsed: "1.0", xcresultPath: "/tmp/x.xcresult",
      scheme: "S", simulator: "Sim",
      totalTestCount: 2, passedTestCount: 1, failedTestCount: 1,
      skippedTestCount: 0, expectedFailureCount: 0,
      failures: [failure("Known/one")],
      deviceName: nil, osVersion: nil,
      screenshotPaths: [], hasStructuredSummary: true,
      buildFailed: false, buildDiagnostics: nil,
      knownFailures: ["Known/one"])
    let json = try WorkflowJSONRenderer.renderTestJSON(exec, forAgent: false)
    #expect(json.contains("\"failures\""))
    #expect(json.contains("Known/one"))
    #expect(json.contains("\"knownFailures\""))
  }
}

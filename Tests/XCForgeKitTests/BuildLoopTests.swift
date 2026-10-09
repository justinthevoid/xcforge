import Foundation
import Testing

@testable import XCForgeKit

@Suite("Build loop: simulator lookup, test build scope, reporting", .serialized)
struct BuildLoopTests {

  private typealias Device = AutoDetect.SimulatorDevice

  private func device(
    _ name: String, _ udid: String, runtime: String = "iOS-18-0", state: String = "Shutdown",
    available: Bool = true
  ) -> Device {
    Device(name: name, udid: udid, runtime: runtime, state: state, isAvailable: available)
  }

  private func tempDir() -> String {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("xcforge-loop-\(UUID().uuidString)", isDirectory: true).path
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    return dir
  }

  // MARK: - One simulator lookup

  @Test("a name resolves to the booted match, else the newest OS, never a prefix match")
  func pickSimulator() throws {
    let devices = [
      device("iPhone 16", "OLD", runtime: "iOS-18-2"),
      device("iPhone 16", "NEW", runtime: "iOS-18-10"),
      device("iPhone 16 Pro", "PRO", runtime: "iOS-26-0", state: "Booted"),
      device("iPhone 16", "GONE", runtime: "iOS-27-0", available: false),
    ]
    #expect(try AutoDetect.pickSimulator(named: "iphone 16", from: devices).udid == "NEW")
    #expect(try AutoDetect.pickSimulator(named: "iPhone 16 Pro", from: devices).udid == "PRO")

    let withBooted = devices + [device("iPhone 16", "BOOTED", runtime: "iOS-17-0", state: "Booted")]
    #expect(try AutoDetect.pickSimulator(named: "iPhone 16", from: withBooted).udid == "BOOTED")

    #expect(throws: (any Error).self) { try AutoDetect.pickSimulator(named: "iPhone", from: devices) }
    let tie = [device("iPad", "A"), device("iPad", "B")]
    #expect(throws: MultipleSimulatorMatchError.self) { try AutoDetect.pickSimulator(named: "iPad", from: tie) }
  }

  @Test("runtime versions compare numerically")
  func runtimeVersions() {
    #expect(AutoDetect.runtimeVersion("iOS-18-10") == [18, 10])
    #expect(AutoDetect.runtimeVersion("iOS-18-2").lexicographicallyPrecedes(AutoDetect.runtimeVersion("iOS-18-10")))
  }

  @Test("compiling picks a booted iOS simulator, else the newest iPhone, without needing one booted")
  func compileSimulator() {
    let none = [
      device("iPad Air", "IPAD", runtime: "iOS-26-0"),
      device("iPhone 15", "P15", runtime: "iOS-17-5"),
      device("iPhone 17", "P17", runtime: "iOS-26-0"),
      device("Apple Watch", "WATCH", runtime: "watchOS-11-0"),
    ]
    #expect(AutoDetect.simulatorForCompile(from: none) == "P17")
    let booted = none + [
      device("iPhone 15", "B1", runtime: "iOS-17-5", state: "Booted"),
      device("iPad Air", "B2", runtime: "iOS-26-0", state: "Booted"),
    ]
    #expect(AutoDetect.simulatorForCompile(from: booted) == "B2")
    #expect(AutoDetect.simulatorForCompile(from: []) == nil)
  }

  // MARK: - Test build scope

  @Test("a filtered run builds only its targets, and only when every ID names a known target")
  func filterTargets() {
    let known = ["AppTests", "AppUITests"]
    let one = TestTools.buildTargetsForFilter(["AppTests/A/a()", "AppTests/B/b()"], known: known)
    #expect(one == ["AppTests"])
    let both = TestTools.buildTargetsForFilter(["AppTests/A/a()", "AppUITests/U"], known: known)
    #expect(both == ["AppTests", "AppUITests"])
    #expect(TestTools.buildTargetsForFilter(["Suite/test()"], known: known) == nil)
    #expect(TestTools.buildTargetsForFilter([], known: known) == nil)
  }

  @Test("a test build covers a rerun only when it built the targets the rerun needs")
  func testBuildScope() throws {
    let root = tempDir()
    defer { try? FileManager.default.removeItem(atPath: root) }
    let project = (root as NSString).appendingPathComponent("App-\(UUID().uuidString).xcodeproj")
    defer { try? FileManager.default.removeItem(atPath: LastResultStore.filePath(for: project)) }
    let key = LastResultStore.testBuildKey(
      scheme: "App", configuration: "Debug", coverage: false, physicalDevice: false, testPlan: "quick")
    let past = Date().addingTimeInterval(-60)

    func current(_ targets: [String]?, plan: String? = "quick") -> Bool {
      let key = LastResultStore.testBuildKey(
        scheme: "App", configuration: "Debug", coverage: false, physicalDevice: false, testPlan: plan)
      return LastResultStore.testBuildIsCurrent(project: project, key: key, targets: targets, sourceRoot: root)
    }

    LastResultStore.recordTestBuild(project: project, key: key, targets: ["AppTests"], now: past)
    #expect(current(["AppTests"]))
    #expect(!current(["AppUITests"]))
    #expect(!current(nil))

    LastResultStore.recordTestBuild(project: project, key: key, targets: nil, now: past)
    #expect(current(["AppUITests"]))
    #expect(!current(nil, plan: "ci"))
  }

  // MARK: - Reporting

  @Test("a failed test build becomes the latest test result, so test failures can't go stale")
  func failedTestBuildRecorded() throws {
    let dir = tempDir()
    defer { try? FileManager.default.removeItem(atPath: dir) }
    let project = (dir as NSString).appendingPathComponent("App-\(UUID().uuidString).xcodeproj")
    defer { try? FileManager.default.removeItem(atPath: LastResultStore.filePath(for: project)) }
    let testBundle = (dir as NSString).appendingPathComponent("t.xcresult")
    let buildBundle = (dir as NSString).appendingPathComponent("b.xcresult")
    try FileManager.default.createDirectory(atPath: testBundle, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(atPath: buildBundle, withIntermediateDirectories: true)

    LastResultStore.recordFromArguments(
      ["-project", project, "-resultBundlePath", testBundle, "test-without-building"], succeeded: false)
    LastResultStore.recordFromArguments(
      ["-project", project, "-resultBundlePath", buildBundle, "build-for-testing"], succeeded: true)
    #expect(LastResultStore.latest(project: project, kind: .test) == testBundle)

    LastResultStore.recordFromArguments(
      ["-project", project, "-resultBundlePath", buildBundle, "build-for-testing"], succeeded: false)
    #expect(LastResultStore.latest(project: project, kind: .test) == buildBundle)
  }

  @Test("compile errors render with file and line, capped")
  func buildErrorLines() {
    let errors = TestTools.buildErrorFailures([
      TestTools.BuildIssueObservation(
        severity: .error, message: "cannot find 'x' in scope",
        location: SourceLocation(filePath: "AppTests/ATests.swift", line: 12), source: "xcresult"),
      TestTools.BuildIssueObservation(severity: .warning, message: "unused", location: nil, source: "xcresult"),
    ])
    #expect(errors.count == 1)
    #expect(TestFailureText.buildErrorLines(errors) == ["  AppTests/ATests.swift:12: cannot find 'x' in scope"])
    let many = Array(repeating: errors[0], count: 25)
    let lines = TestFailureText.buildErrorLines(many, limit: 20)
    #expect(lines.count == 21)
    #expect(lines.last == "  +5 more errors")
  }

  @Test("agent JSON names the result bundle and why a timed-out run stopped")
  func agentTimeoutAndBundle() throws {
    let failure = TestTools.TestFailureObservation(
      testName: "a()", testIdentifier: "AppTests/A/a()", message: "boom", source: "xcresult")
    let execution = TestTools.TestExecution(
      succeeded: false, elapsed: "600", xcresultPath: "/tmp/run.xcresult", scheme: "App", simulator: "iPhone",
      totalTestCount: 3, passedTestCount: 1, failedTestCount: 1, skippedTestCount: 0, expectedFailureCount: 0,
      failures: [failure], deviceName: nil, osVersion: nil, screenshotPaths: [], hasStructuredSummary: true,
      buildFailed: false, buildDiagnostics: nil, xcforgeTimedOut: true,
      timeoutDetail: "Killed after 600s with no output (idle timeout). Likely hung.")
    let projected = AgentResultProjection.project(execution)
    #expect(projected.timedOut)
    #expect(projected.reason?.contains("idle timeout") == true)
    #expect(projected.xcresult == "/tmp/run.xcresult")
    let json = try WorkflowJSONRenderer.renderJSON(projected)
    #expect(json.contains("\"xcresult\""))
  }
}

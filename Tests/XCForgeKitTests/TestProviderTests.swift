import Foundation
import Testing

@testable import XCForgeKit

// MARK: - TestRecordingShell

/// Actor-based shell that records every xcodebuild invocation and simctl call.
actor TestRecordingShell: ShellExecutor {
  private(set) var xcodebuildInvocations: [[String]] = []
  private(set) var simctlCalls: [String] = []
  private(set) var eraseCalled = false

  /// When set, `pgrep -n xcodebuild` returns this PID.
  let fakePid: String
  /// State returned for the test device in `simctl list` responses.
  /// Default "Booted" = healthy sim.
  let simState: String

  init(fakePid: String = "99999", simState: String = "Booted") {
    self.fakePid = fakePid
    self.simState = simState
  }

  nonisolated func run(
    _ executable: String,
    arguments: [String],
    workingDirectory: String?,
    environment: [String: String]?,
    timeout: TimeInterval,
    outputLimit: Int
  ) async throws -> ShellResult {
    await recordAndDispatch(executable: executable, arguments: arguments)
  }

  nonisolated func xcrun(timeout: TimeInterval, arguments: [String]) async throws -> ShellResult {
    await recordAndDispatch(executable: "/usr/bin/xcrun", arguments: arguments)
  }

  nonisolated func git(_ arguments: [String], workingDirectory: String, timeout: TimeInterval)
    async throws -> ShellResult
  {
    ShellResult(stdout: "", stderr: "", exitCode: 0)
  }

  private func recordAndDispatch(executable: String, arguments: [String]) async -> ShellResult {
    let exe = (executable as NSString).lastPathComponent

    // xcodebuild invocations
    if exe == "xcodebuild" {
      xcodebuildInvocations.append(arguments)
      return ShellResult(stdout: "** BUILD SUCCEEDED **", stderr: "", exitCode: 0)
    }

    // pgrep — return fake PID for xcodebuild lookup
    if exe == "pgrep" && arguments.contains("xcodebuild") {
      return ShellResult(stdout: fakePid, stderr: "", exitCode: 0)
    }

    // pgrep -P (child PIDs): return empty — no children
    if exe == "pgrep" && arguments.contains("-P") {
      return ShellResult(stdout: "", stderr: "", exitCode: 1)
    }

    // simctl dispatch
    if exe == "xcrun" || arguments.first == "simctl" {
      let subArgs = arguments.first == "simctl" ? Array(arguments.dropFirst()) : arguments
      return handleSimctl(subArgs)
    }

    // sample
    if exe == "sample" {
      return ShellResult(stdout: "sample output line", stderr: "", exitCode: 0)
    }

    return ShellResult(stdout: "", stderr: "", exitCode: 0)
  }

  private func handleSimctl(_ arguments: [String]) -> ShellResult {
    let sub = arguments.first ?? ""
    simctlCalls.append(sub)

    switch sub {
    case "list":
      // Return minimal device JSON for resolver/health probe, using configured state.
      let json =
        """
        {"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-26-0":[{"name":"iPhone 17","udid":"AAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE","state":"\(simState)","isAvailable":true}]}}
        """
      return ShellResult(stdout: json, stderr: "", exitCode: 0)
    case "erase":
      eraseCalled = true
      return ShellResult(stdout: "", stderr: "", exitCode: 0)
    case "shutdown", "boot":
      return ShellResult(stdout: "", stderr: "", exitCode: 0)
    default:
      return ShellResult(stdout: "", stderr: "", exitCode: 0)
    }
  }
}

// MARK: - ChildAwareShell

/// Struct-based shell that returns a fake child PID for `pgrep -P`.
struct ChildAwareShell: ShellExecutor {
  let childPid: String

  func run(
    _ executable: String,
    arguments: [String],
    workingDirectory: String?,
    environment: [String: String]?,
    timeout: TimeInterval,
    outputLimit: Int
  ) async throws -> ShellResult {
    let exe = (executable as NSString).lastPathComponent
    if exe == "pgrep" && arguments.contains("-P") {
      return ShellResult(stdout: childPid, stderr: "", exitCode: 0)
    }
    if exe == "pgrep" {
      return ShellResult(stdout: "11111", stderr: "", exitCode: 0)
    }
    if exe == "sample" {
      return ShellResult(stdout: "sample output from child", stderr: "", exitCode: 0)
    }
    if exe == "ps" {
      return ShellResult(stdout: "SWBBuildService", stderr: "", exitCode: 0)
    }
    return ShellResult(stdout: "", stderr: "", exitCode: 0)
  }

  func xcrun(timeout: TimeInterval, arguments: [String]) async throws -> ShellResult {
    ShellResult(stdout: "", stderr: "", exitCode: 0)
  }

  func git(_ arguments: [String], workingDirectory: String, timeout: TimeInterval) async throws
    -> ShellResult
  {
    ShellResult(stdout: "", stderr: "", exitCode: 0)
  }
}

// MARK: - Fixture helpers

private func loadFixture(named name: String) -> String {
  // Try Bundle.module first (when built with SPM test resources)
  if let url = Bundle.module.url(
    forResource: name, withExtension: "txt", subdirectory: "Fixtures")
  {
    return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
  }

  // Fallback: source-relative path for local development
  let sourceDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
  let fallback = sourceDir.appendingPathComponent("Fixtures/\(name).txt")
  return (try? String(contentsOf: fallback, encoding: .utf8)) ?? ""
}

// MARK: - Tests

@Suite("TestProvider")
struct TestProviderTests {

  // MARK: 1. Split path: two distinct xcodebuild invocations

  @Test("split pipeline records build-for-testing then test-without-building invocations")
  func splitPipelineRecordsTwoInvocations() async throws {
    let shell = TestRecordingShell()
    let env = Environment(shell: shell)

    let buildPath = "/tmp/xcf-bft-test-\(UUID().uuidString).xcresult"
    let testPath = "/tmp/xcf-twb-test-\(UUID().uuidString).xcresult"
    defer {
      try? FileManager.default.removeItem(atPath: buildPath)
      try? FileManager.default.removeItem(atPath: testPath)
    }

    _ = try await TestTools.runBuildForTesting(
      project: "/tmp/fake.xcodeproj",
      scheme: "MyScheme",
      destination: "platform=iOS Simulator,id=FAKE-UDID",
      configuration: "Debug",
      coverage: false,
      resultPath: buildPath,
      env: env
    )

    _ = try await TestTools.runTestWithoutBuilding(
      project: "/tmp/fake.xcodeproj",
      scheme: "MyScheme",
      destination: "platform=iOS Simulator,id=FAKE-UDID",
      configuration: "Debug",
      testplan: nil,
      filter: nil,
      coverage: false,
      resultPath: testPath,
      env: env
    )

    let invocations = await shell.xcodebuildInvocations
    #expect(invocations.count == 2)

    let buildArgs = invocations[0]
    let testArgs = invocations[1]
    #expect(buildArgs.contains("build-for-testing"))
    #expect(testArgs.contains("test-without-building"))
  }

  // MARK: 2. classifyVerdict → swbbuildserviceDeadlock

  @Test("classifyVerdict returns swbbuildserviceDeadlock on deadlock fixture")
  func classifyVerdictDeadlock() {
    let content = loadFixture(named: "swbbuildservice-deadlock")
    #expect(!content.isEmpty, "Fixture file missing")

    let verdict = DiagnosticSnapshot.classifyVerdictFromContent(content)
    #expect(verdict == .swbbuildserviceDeadlock)
  }

  // MARK: 3. classifyVerdict → dtdevicekitHang

  @Test("classifyVerdict returns dtdevicekitHang on DTDeviceKit fixture")
  func classifyVerdictDTDeviceKit() {
    let content = loadFixture(named: "dtdevicekit-hang")
    #expect(!content.isEmpty, "Fixture file missing")

    let verdict = DiagnosticSnapshot.classifyVerdictFromContent(content)
    #expect(verdict == .dtdevicekitHang)
  }

  // MARK: 4. classifyVerdict → timeout for generic snapshot

  @Test("classifyVerdict returns timeout for a generic snapshot with no known signatures")
  func classifyVerdictTimeout() {
    let content = """
      === xcforge diagnostic snapshot ===
      Timestamp: 2026-04-30T09:00:00Z
      xcodebuild PID: 99999

      === sample ===
      Process: xcodebuild [99999]
      Thread 0x1000
        0  libsystem_kernel.dylib  mach_msg_trap
        1  CoreFoundation           CFRunLoopRunSpecific
      """
    let verdict = DiagnosticSnapshot.classifyVerdictFromContent(content)
    #expect(verdict == .timeout)
  }

  // MARK: 5. Regression: swbbuildservice symbol in parent section must not match

  @Test(
    "classifyVerdictFromContent does NOT return swbbuildserviceDeadlock when symbol is in parent section"
  )
  func classifyVerdictNoFalsePositiveInParent() {
    // swift_task_asyncMainDrainQueue appears in the parent section (before any child header)
    // This must NOT trigger a swbbuildservice_deadlock verdict.
    let content = """
      === xcforge diagnostic snapshot ===
      Timestamp: 2026-04-30T09:00:00Z
      xcodebuild PID: 55555

      === sample ===
      Process: xcodebuild [55555]
      Thread 0x1000 DispatchQueue "com.apple.main-thread"(serial)
        0  libswift_Concurrency.dylib  swift_task_asyncMainDrainQueue
        1  xcodebuild                   main

      === child process samples ===
      === child 55556 (idb_companion) ===
      Thread 0x2000
        0  libsystem_kernel.dylib  mach_msg_trap
      """
    let verdict = DiagnosticSnapshot.classifyVerdictFromContent(content)
    // Symbol is in parent (xcodebuild) section — must not match as SWBBuildService deadlock
    #expect(verdict != .swbbuildserviceDeadlock)
  }

  // MARK: 6. simRecovery .auto — healthy sim: no erase

  @Test("simRecovery .auto healthy sim: probeAndRecover returns fired=false, no erase called")
  func simRecoveryAutoHealthy() async {
    let shell = TestRecordingShell(simState: "Booted")
    let env = Environment(shell: shell)

    let outcome = await SimulatorRecovery.probeAndRecover(
      udid: "AAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
      env: env
    )

    #expect(!outcome.fired)
    #expect(outcome.reason == nil)
    let eraseCalled = await shell.eraseCalled
    #expect(!eraseCalled)
  }

  // MARK: 7. simRecovery .auto — unhealthy sim: tiered recovery; erase reached when tier 1 fails

  @Test("simRecovery .auto unhealthy sim: probeAndRecover returns fired=true, erase called")
  func simRecoveryAutoUnhealthy() async {
    // State is Shutdown — health probe returns notBooted, triggering tiered recovery.
    // After tier-1 shutdown+boot the list probe returns Shutdown again (mock is stateless),
    // so tier 2 (erase) fires.
    let shell = TestRecordingShell(simState: "Shutdown")
    let env = Environment(shell: shell)

    let outcome = await SimulatorRecovery.probeAndRecover(
      udid: "AAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
      env: env
    )

    #expect(outcome.fired)
    #expect(outcome.reason == "sim_unhealthy")
    let eraseCalled = await shell.eraseCalled
    #expect(eraseCalled)
  }

  // MARK: 8. simRecovery .off gate — no erase called for unhealthy sim

  @Test("simRecovery .off skips probe: unhealthy sim, no erase invoked")
  func simRecoveryOffSkipsProbeOnUnhealthySim() async {
    // The gate in executeBuildAndTest is: `if simRecovery == .auto { probeAndRecover(...) }`
    // With .off, probeAndRecover is never called.
    let shell = TestRecordingShell(simState: "Shutdown")
    let env = Environment(shell: shell)

    let recoveryMode: SimRecoveryMode = .off
    var eraseWouldHaveFired = false

    if recoveryMode == .auto {
      let outcome = await SimulatorRecovery.probeAndRecover(
        udid: "AAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
        env: env
      )
      eraseWouldHaveFired = outcome.fired
    }

    // Gate blocked the probe — neither fired nor erase called
    #expect(!eraseWouldHaveFired)
    let shellEraseCalled = await shell.eraseCalled
    #expect(!shellEraseCalled)
  }

  // MARK: 9. Child sections appear below legacy headers

  @Test("child process samples appear below legacy header lines in snapshot output")
  func childSectionsBelowLegacyHeaders() async {
    let path = "/tmp/xcf-test-child-\(UUID().uuidString).txt"
    defer { try? FileManager.default.removeItem(atPath: path) }

    let shell = ChildAwareShell(childPid: "22222")
    let env = Environment(shell: shell)

    _ = await DiagnosticSnapshot.capture(udid: nil, snapshotPath: path, env: env)

    let contents = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""

    // Legacy headers must appear
    #expect(contents.contains("=== xcforge diagnostic snapshot ==="))
    #expect(contents.contains("=== sample ==="))
    #expect(contents.contains("=== lsof ==="))

    // Child section must appear below the legacy headers
    let legacyRange = contents.range(of: "=== sample ===")
    let childRange = contents.range(of: "=== child process samples ===")

    #expect(legacyRange != nil)
    if let legacy = legacyRange, let child = childRange {
      #expect(legacy.lowerBound < child.lowerBound)
    }
  }
}

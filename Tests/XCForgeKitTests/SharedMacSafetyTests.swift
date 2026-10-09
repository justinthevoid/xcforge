import Foundation
import MCP
import Testing

@testable import XCForgeKit

@Suite("Shared-Mac safety: xcodebuild options, build lock, last results", .serialized)
struct SharedMacSafetyTests {

  private func makeTempDir() -> String {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("xcforge-shared-\(UUID().uuidString)", isDirectory: true)
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.path
  }

  // MARK: - Xcodebuild.apply

  @Test("apply inserts -derivedDataPath and extra args before the action")
  func applyInsertsBeforeAction() {
    let options = XcodebuildOptions(derivedDataPath: "/dd", extraArgs: ["-jobs", "6"])
    let args = ["-project", "A.xcodeproj", "-scheme", "A", "build", "COMPILATION_CACHE_ENABLE_CACHING=YES"]
    let result = Xcodebuild.apply(options, to: args)
    #expect(
      result == [
        "-project", "A.xcodeproj", "-scheme", "A", "-derivedDataPath", "/dd", "-jobs", "6", "build",
        "COMPILATION_CACHE_ENABLE_CACHING=YES",
      ])
  }

  @Test("apply leaves -list and an existing -derivedDataPath alone")
  func applySkipsNonBuildAndDuplicates() {
    let options = XcodebuildOptions(derivedDataPath: "/dd")
    let list = ["-project", "A.xcodeproj", "-list", "-json"]
    #expect(Xcodebuild.apply(options, to: list) == list)
    let explicit = ["-derivedDataPath", "/mine", "build"]
    #expect(Xcodebuild.apply(options, to: explicit) == explicit)
  }

  @Test("-showBuildSettings gets DerivedData but does not take the lock")
  func showBuildSettingsNoLock() {
    let args = ["-scheme", "A", "-showBuildSettings"]
    #expect(Xcodebuild.isBuildInvocation(args))
    #expect(!Xcodebuild.needsLock(args))
    #expect(Xcodebuild.needsLock(["-scheme", "A", "test-without-building"]))
  }

  // MARK: - Result bundle paths

  @Test("generated result bundle paths never collide")
  func uniquePaths() {
    let a = XcodebuildOptions.resultBundlePath(prefix: "test")
    let b = XcodebuildOptions.resultBundlePath(prefix: "test")
    #expect(a != b)
    #expect(a.hasSuffix(".xcresult"))
  }

  @Test("a fixed resultBundlePath is used for the final phase; earlier phases get a sibling")
  func fixedResultBundlePath() {
    let options = XcodebuildOptions(resultBundlePath: "/out/run.xcresult")
    XcodebuildOptions.$current.withValue(options) {
      #expect(XcodebuildOptions.resultBundlePath(prefix: "test") == "/out/run.xcresult")
      #expect(
        XcodebuildOptions.resultBundlePath(prefix: "build-for-testing")
          == "/out/run-build-for-testing.xcresult")
    }
  }

  // MARK: - Effective options

  @Test("task-local values win over environment variables")
  func effectivePrecedence() {
    let env = ["XCFORGE_DERIVED_DATA_PATH": "/env-dd", "XCFORGE_BUILD_LOCK": "/env.lock"]
    let fromEnv = XcodebuildOptions.effective(cwd: "/", environment: env)
    #expect(fromEnv.derivedDataPath == "/env-dd")
    #expect(fromEnv.lockPath == "/env.lock")

    XcodebuildOptions.$current.withValue(XcodebuildOptions(derivedDataPath: "/explicit")) {
      let merged = XcodebuildOptions.effective(cwd: "/", environment: env)
      #expect(merged.derivedDataPath == "/explicit")
      #expect(merged.lockPath == "/env.lock")
    }
  }

  @Test(".xcforge.yaml path keys resolve relative to the yaml's folder")
  func repoConfigPathKeys() throws {
    let dir = makeTempDir()
    defer { try? FileManager.default.removeItem(atPath: dir) }
    let yaml = """
      derivedDataPath: build/dd
      buildLock: /tmp/ios.lock
      minFreeGB: 5
      """
    let path = (dir as NSString).appendingPathComponent(".xcforge.yaml")
    try yaml.write(toFile: path, atomically: true, encoding: .utf8)
    let values = RepoConfig.load(from: path, configDir: dir)
    #expect(values?.derivedDataPath == (dir as NSString).appendingPathComponent("build/dd"))
    #expect(values?.buildLock == "/tmp/ios.lock")
    #expect(values?.minFreeGB == 5)
  }

  // MARK: - MCP plumbing

  @Test("MCP arguments parse into options, and build tools advertise them")
  func mcpOptions() {
    let args: [String: Value] = [
      "derivedDataPath": .string("/dd"),
      "xcodebuildArgs": .array([.string("-jobs"), .string("6")]),
      "buildLock": .string("/tmp/l"),
      "lockWaitSeconds": .int(30),
    ]
    let options = XcodebuildOptions.fromMCPArguments(args)
    #expect(options.derivedDataPath == "/dd")
    #expect(options.extraArgs == ["-jobs", "6"])
    #expect(options.lockPath == "/tmp/l")
    #expect(options.lockWaitSeconds == 30)

    let tool = ToolRegistry.allTools.first { $0.name == "build_and_test" }
    let properties = tool?.inputSchema.objectValue?["properties"]?.objectValue
    #expect(properties?["derivedDataPath"] != nil)
    #expect(properties?["buildLock"] != nil)
  }

  // MARK: - Build lock

  @Test("lock is acquired, reported, and released")
  func lockLifecycle() async throws {
    let dir = makeTempDir()
    defer { try? FileManager.default.removeItem(atPath: dir) }
    let path = (dir as NSString).appendingPathComponent("build.lock")

    let handle = try await BuildLock.acquire(path: path, label: "test build", maxWait: 5)
    let held = BuildLock.status(path: path, externalHolders: [])
    #expect(held.held)
    #expect(held.holder?.pid == ProcessInfo.processInfo.processIdentifier)
    #expect(held.holder?.command == "test build")
    #expect(BuildLock.format(held).contains("test build"))

    handle.release()
    let free = BuildLock.status(path: path, externalHolders: [])
    #expect(!free.held)
    #expect(free.holder == nil)
  }

  @Test("a second waiter times out with the holder named in the error")
  func lockTimeout() async throws {
    let dir = makeTempDir()
    defer { try? FileManager.default.removeItem(atPath: dir) }
    let path = (dir as NSString).appendingPathComponent("build.lock")

    let handle = try await BuildLock.acquire(path: path, label: "first", maxWait: 5)
    defer { handle.release() }
    do {
      _ = try await BuildLock.acquire(path: path, label: "second", maxWait: 0.5, pollInterval: 0.1)
      Issue.record("second acquire should have timed out")
    } catch let error as BuildLock.LockError {
      #expect("\(error)".contains("first"))
    }
    // The timed-out waiter's ticket is gone.
    #expect(BuildLock.liveTickets(in: BuildLock.queueDir(path)).isEmpty)
  }

  @Test("tickets from dead processes are pruned")
  func deadTicketsPruned() throws {
    let dir = makeTempDir()
    defer { try? FileManager.default.removeItem(atPath: dir) }
    let queue = (dir as NSString).appendingPathComponent("q")
    try FileManager.default.createDirectory(atPath: queue, withIntermediateDirectories: true)
    let ticket = """
      {"pid": 2147483000, "command": "ghost", "cwd": "/", "since": "2026-01-01T00:00:00Z"}
      """
    try ticket.write(
      toFile: (queue as NSString).appendingPathComponent("00000000000000000001-1.json"),
      atomically: true, encoding: .utf8)
    #expect(BuildLock.liveTickets(in: queue).isEmpty)
    #expect(try FileManager.default.contentsOfDirectory(atPath: queue).isEmpty)
  }

  // MARK: - Last results

  @Test("last result is recorded per project from xcodebuild arguments")
  func lastResultRecorded() throws {
    let dir = makeTempDir()
    defer { try? FileManager.default.removeItem(atPath: dir) }
    let bundle = (dir as NSString).appendingPathComponent("t.xcresult")
    try FileManager.default.createDirectory(atPath: bundle, withIntermediateDirectories: true)
    let project = (dir as NSString).appendingPathComponent("App-\(UUID().uuidString).xcodeproj")

    LastResultStore.recordFromArguments([
      "-project", project, "-scheme", "App", "-resultBundlePath", bundle, "test-without-building",
    ])
    #expect(LastResultStore.latest(project: project, kind: .test) == bundle)
    #expect(LastResultStore.latest(project: project, kind: .build) == nil)
    try? FileManager.default.removeItem(atPath: LastResultStore.filePath(for: project))
  }

  // MARK: - Isolated simulator

  @Test("deviceSpec finds the device type and runtime by UDID or name")
  func deviceSpecLookup() {
    let json = """
      {"devices": {
        "com.apple.CoreSimulator.SimRuntime.iOS-18-0": [
          {"udid": "AAA", "name": "iPhone 16", "deviceTypeIdentifier": "type.iPhone-16", "isAvailable": true}
        ],
        "com.apple.CoreSimulator.SimRuntime.iOS-26-0": [
          {"udid": "BBB", "name": "iPhone 17", "deviceTypeIdentifier": "type.iPhone-17", "isAvailable": true}
        ]
      }}
      """
    let byUDID = IsolatedSimulator.deviceSpec(source: "AAA", listJSON: json)
    #expect(byUDID?.deviceType == "type.iPhone-16")
    #expect(byUDID?.runtime == "com.apple.CoreSimulator.SimRuntime.iOS-18-0")
    let byName = IsolatedSimulator.deviceSpec(source: "iPhone 17", listJSON: json)
    #expect(byName?.deviceType == "type.iPhone-17")
    #expect(IsolatedSimulator.deviceSpec(source: "nope", listJSON: json) == nil)
  }

  // MARK: - WDA port cleanup

  @Test("only WebDriverAgent runner processes are eligible for port cleanup")
  func wdaRunnerDetection() {
    #expect(WDAClient.isWDARunnerCommand("/path/xcforgeWDARunner-Runner"))
    #expect(WDAClient.isWDARunnerCommand("WebDriverAgentRunner-Runner"))
    #expect(!WDAClient.isWDARunnerCommand("/usr/bin/python3"))
    #expect(!WDAClient.isWDARunnerCommand("node"))
  }
}

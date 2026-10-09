import Foundation
import Testing

@testable import XCForgeKit

@Suite("Run loop: launch checks, the right app, captures, clean", .serialized)
struct RunLoopTests {

  private func tempDir() -> String {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("xcforge-run-\(UUID().uuidString)", isDirectory: true).path
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    return dir
  }

  // MARK: - Launch

  @Test("the pid comes from the `bundle: pid` line, never from a URL's port")
  func launchPid() {
    #expect(AppLiveness.pid(fromLaunchOutput: "com.example.app: 4242") == 4242)
    let message = "Launched com.example.app on ABC\ncom.example.app: 77\nOpened https://example.com:8080"
    #expect(AppLiveness.pid(fromLaunchOutput: message) == 77)
    #expect(AppLiveness.pid(fromLaunchOutput: "App running: true") == nil)
  }

  @Test("launch environment entries must be KEY=VALUE")
  func launchEnvironment() throws {
    let parsed = try SimTools.parseEnvironment(["A=1", "URL=https://x?a=b"])
    #expect(parsed == ["A": "1", "URL": "https://x?a=b"])
    #expect(throws: (any Error).self) { try SimTools.parseEnvironment(["NOVALUE"]) }
  }

  static let crashReport = """
    {"app_name":"App","bundleID":"com.example.app","bug_type":"309"}
    {
      "exception": {"type": "EXC_CRASH", "signal": "SIGABRT"},
      "asi": {"libsystem_c.dylib": ["abort() called"]},
      "usedImages": [{"name": "App"}, {"name": "libsystem_c.dylib"}],
      "threads": [
        {"frames": [{"imageIndex": 0, "imageOffset": 10}]},
        {"triggered": true, "frames": [
          {"imageIndex": 1, "symbol": "abort"},
          {"imageIndex": 0, "symbol": "AppDelegate.setUp()"},
          {"imageIndex": 0, "imageOffset": 512}
        ]}
      ]
    }
    """

  @Test("a crash report becomes the exception, reason and crashed thread's frames")
  func crashSummary() throws {
    let summary = try #require(CrashReports.summarize(Self.crashReport, path: "/r.ips"))
    #expect(summary.headline == "EXC_CRASH (SIGABRT): abort() called")
    #expect(summary.frames == ["libsystem_c.dylib  abort", "App  AppDelegate.setUp()", "App  +512"])
    let text = AppLiveness.describe(.exited(summary), bundleId: "com.example.app")
    #expect(text.contains("App running: false"))
    #expect(text.contains("Crash report: /r.ips"))
  }

  @Test("the newest report for the app since launch is the one picked")
  func newestCrashReport() throws {
    let dir = tempDir()
    defer { try? FileManager.default.removeItem(atPath: dir) }
    let launchedAt = Date()
    let mine = (dir as NSString).appendingPathComponent("App-1.ips")
    let other = (dir as NSString).appendingPathComponent("Other-1.ips")
    let old = (dir as NSString).appendingPathComponent("App-0.ips")
    try Self.crashReport.write(toFile: mine, atomically: true, encoding: .utf8)
    try Self.crashReport.replacingOccurrences(of: "com.example.app", with: "com.other")
      .write(toFile: other, atomically: true, encoding: .utf8)
    try Self.crashReport.write(toFile: old, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
      [.modificationDate: launchedAt.addingTimeInterval(-3600)], ofItemAtPath: old)

    #expect(CrashReports.newest(bundleId: "com.example.app", after: launchedAt, in: dir) == mine)
    #expect(CrashReports.newest(bundleId: "com.missing", after: launchedAt, in: dir) == nil)
  }

  // MARK: - The right app

  @Test("the scheme's application target is the product, not the last target listed")
  func appProduct() throws {
    let settings: [[String: Any]] = [
      [
        "target": "App",
        "buildSettings": [
          "PRODUCT_TYPE": "com.apple.product-type.application", "PRODUCT_BUNDLE_IDENTIFIER": "com.example.app",
          "BUILT_PRODUCTS_DIR": "/dd/Build/Products/Debug-iphonesimulator", "FULL_PRODUCT_NAME": "App.app",
        ],
      ],
      [
        "target": "Widget",
        "buildSettings": [
          "PRODUCT_TYPE": "com.apple.product-type.app-extension", "WRAPPER_EXTENSION": "appex",
          "PRODUCT_BUNDLE_IDENTIFIER": "com.example.app.widget",
          "BUILT_PRODUCTS_DIR": "/dd/Build/Products/Debug-iphonesimulator", "FULL_PRODUCT_NAME": "Widget.appex",
        ],
      ],
    ]
    let json = String(decoding: try JSONSerialization.data(withJSONObject: settings), as: UTF8.self)
    let product = try #require(BuildTools.appProduct(fromSettings: json))
    #expect(product.bundleId == "com.example.app")
    #expect(product.appPath == "/dd/Build/Products/Debug-iphonesimulator/App.app")

    let extensionData = try JSONSerialization.data(withJSONObject: [settings[1]])
    let onlyExtension = String(decoding: extensionData, as: UTF8.self)
    #expect(BuildTools.appProduct(fromSettings: onlyExtension) == nil)
  }

  @Test("with several schemes, the one named after the project or the only app scheme wins")
  func preferredScheme() {
    #expect(AutoDetect.preferredScheme(["App", "AppDev", "AppTests"], projectName: "App") == "App")
    #expect(AutoDetect.preferredScheme(["Main", "MainTests", "Pods-Main"], projectName: "App") == "Main")
    #expect(AutoDetect.preferredScheme(["One", "Two"], projectName: "App") == nil)
    #expect(AutoDetect.preferredScheme(["Only"], projectName: "App") == "Only")
  }

  // MARK: - Clean

  @Test("only a path shaped like one project's DerivedData folder can be deleted")
  func derivedDataFolder() {
    let folder = "/Users/me/Library/Developer/Xcode/DerivedData/App-abc"
    #expect(BuildTools.derivedDataFolder(fromBuildRoot: folder + "/Build/Products") == folder)
    #expect(BuildTools.derivedDataFolder(fromBuildRoot: "/tmp/Build/Products") == nil)
    #expect(BuildTools.derivedDataFolder(fromBuildRoot: "/a/b/c/Build") == nil)
    #expect(BuildTools.derivedDataFolder(fromBuildRoot: "relative/x/y/Build/Products") == nil)
  }

  // MARK: - Logs and console

  @Test("reads return the newest 200 lines by default and say how many were left out")
  func captureTail() {
    let lines = (1...250).map { "line \($0)" }
    let (kept, omitted) = CaptureTail.tail(lines, last: nil)
    #expect(kept.count == 200)
    #expect(kept.last == "line 250")
    #expect(omitted == 50)
    #expect(CaptureTail.tail(lines, last: 0).lines.count == 250)
    #expect(CaptureTail.tail(lines, last: 5).lines == Array(lines.suffix(5)))
    #expect(CaptureTail.keepEnd("abcdef", limit: 3).hasSuffix("def"))
  }

  @Test("errors and faults are crashes; default-level lines are not")
  func crashTopic() {
    #expect(LogTools.isErrorOrFault("E"))
    #expect(LogTools.isErrorOrFault("F"))
    #expect(LogTools.isErrorOrFault("Fa"))
    #expect(!LogTools.isErrorOrFault("Df"))
    let line = "2026-03-29 22:26:04.618 Df  log[43371:3a7ccf] (LoggingSupport) Sending stream request"
    let topics = LogTools.parseLine(line).map { LogTools.categorize($0, bundleId: nil, processName: nil) }
    #expect(topics?.contains("crashes") == false)
  }

  @Test("lines read from a capture file collapse repeats like live capture")
  func collapseRepeats() {
    let a = "2026-03-29 22:26:04.112 Db  App[1:2] [com.app:x] hello"
    let a2 = "2026-03-29 22:26:05.112 Db  App[1:2] [com.app:x] hello"
    let b = "2026-03-29 22:26:06.112 Db  App[1:2] [com.app:x] bye"
    #expect(LogTools.collapseRepeats([a, a2, a2, b]) == [a, "  ... repeated 2x", b])
  }

  @Test("a background capture's output survives this process and reads by stream")
  func detachedCapture() async throws {
    let dir = tempDir()
    defer { try? FileManager.default.removeItem(atPath: dir) }
    let capture = DetachedCapture(name: "test", directory: dir)
    try capture.start(
      executable: "/bin/sh", arguments: ["-c", "echo one; echo two >&2; echo \"$XCF_TEST\""],
      environment: ["XCF_TEST": "three"], captureStderr: true, bundleId: "com.example.app")
    for _ in 0..<50 where capture.isRunning {
      try await Task.sleep(nanoseconds: 100_000_000)
    }
    #expect(capture.lines(.stdout) == ["one", "three"])
    #expect(capture.lines(.stderr) == ["two"])
    #expect(capture.state()?.bundleId == "com.example.app")

    let (lines, next) = capture.newLines(.stdout, after: 0)
    #expect(lines == ["one", "three"])
    #expect(capture.newLines(.stdout, after: next).lines.isEmpty)

    capture.clear()
    #expect(capture.lines(.stdout).isEmpty)
    capture.stop()
    #expect(!capture.exists)
  }
}

import Foundation
import Testing

@testable import XCForgeKit

@Suite("Fixes from the real-Mac run", .serialized)
struct MacVerifyFixesTests {

  private func makeTempDir() -> String {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("xcforge-macfix-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.path
  }

  // MARK: - typecheck --target with a custom DerivedData

  @Test("-target builds put products and intermediates where a scheme build would")
  func targetBuildRoots() {
    #expect(
      BuildTools.targetBuildRoots(derivedData: "/tmp/dd") == [
        "SYMROOT=/tmp/dd/Build/Products", "OBJROOT=/tmp/dd/Build/Intermediates.noindex",
      ])
  }

  @Test("-target builds never get -derivedDataPath")
  func applySkipsDerivedDataForTarget() {
    let options = XcodebuildOptions(derivedDataPath: "/tmp/dd", continueAfterErrors: false)
    let target = Xcodebuild.apply(options, to: ["-project", "A.xcodeproj", "-target", "Shared", "build"])
    #expect(!target.contains("-derivedDataPath"))
    let scheme = Xcodebuild.apply(options, to: ["-scheme", "A", "build"])
    #expect(scheme.contains("-derivedDataPath"))
  }

  @Test("an xcodebuild usage error is found and isn't a compile error")
  func usageError() {
    let output = "Command line invocation:\n    xcodebuild: error: The option -derivedDataPath is not valid\n"
    #expect(BuildTools.xcodebuildUsageError(output) == "xcodebuild: error: The option -derivedDataPath is not valid")
    #expect(BuildTools.xcodebuildUsageError("main.swift:3:1: error: oops") == nil)
  }

  // MARK: - HID on Xcode 27

  @Test("SimulatorKit is looked for in SharedFrameworks first, then PrivateFrameworks")
  func simulatorKitCandidates() {
    let paths = IndigoHIDClient.simulatorKitCandidates(developerDir: "/Applications/Xcode.app/Contents/Developer")
    #expect(
      paths == [
        "/Applications/Xcode.app/Contents/SharedFrameworks/SimulatorKit.framework/SimulatorKit",
        "/Applications/Xcode.app/Contents/Developer/Library/PrivateFrameworks/SimulatorKit.framework/SimulatorKit",
      ])
  }

  // MARK: - crash detection after launch

  @Test("watch and report-wait seconds read the environment, ignoring bad values")
  func secondsOverride() {
    #expect(AppLiveness.seconds("K", default: 8, environment: [:]) == 8)
    #expect(AppLiveness.seconds("K", default: 8, environment: ["K": "20"]) == 20)
    #expect(AppLiveness.seconds("K", default: 8, environment: ["K": "-1"]) == 8)
    #expect(AppLiveness.seconds("K", default: 8, environment: ["K": "soon"]) == 8)
  }

  @Test("an exit without a report says when and where to look")
  func exitedWithoutReport() {
    let text = AppLiveness.describe(.exited(nil, afterSeconds: 4.2), bundleId: "com.example.app")
    #expect(text.contains("exited about 4.2s after launch"))
    #expect(text.contains(".ips"))
    let crashed = AppLiveness.describe(
      .exited(CrashSummary(exception: "EXC_CRASH", reason: nil, frames: [], path: "/r.ips"), afterSeconds: 6),
      bundleId: "com.example.app")
    #expect(crashed.contains("crashed about 6.0s after launch"))
  }

  // MARK: - relative --project

  @Test("a relative project path becomes absolute")
  func absoluteProjectPath() {
    let cwd = FileManager.default.currentDirectoryPath
    let expected = (cwd as NSString).appendingPathComponent("ios/App.xcodeproj")
    #expect(SessionState.absolutePath("ios/App.xcodeproj") == expected)
    #expect(SessionState.absolutePath("/a/./b/../App.xcodeproj") == "/a/App.xcodeproj")
    #expect(!SessionState.absolutePath("~/App.xcodeproj").hasPrefix("~"))
  }

  // MARK: - first WDA start

  @Test("an old xcforgeWDA copy on a newer Xcode is explained")
  func wdaBuildFailure() {
    let old = WDAClient.explainWDABuildFailure(
      "xcodebuild: error: Supported platforms for the buildables in the current scheme is empty.",
      projectDir: "/opt/homebrew/share/xcforge/xcforgeWDA")
    #expect(old.contains("XCFORGE_WDA_DIR"))
    let other = WDAClient.explainWDABuildFailure("x\nRunner.swift:1: error: boom\n", projectDir: "/w")
    #expect(other.contains("error: boom"))
  }

  @Test("a WDA start failure carries its reason")
  func noBackendReason() {
    #expect("\(WDAError.noBackendAvailable("the build failed"))".contains("the build failed"))
  }

  // MARK: - minor items

  @Test("queued xcforge processes don't count as lock holders")
  func externalHoldersSkipQueued() {
    let lsof = "p100\ncxcodebuild\np200\ncxcforge\n"
    #expect(BuildLock.externalHolders(lsofOutput: lsof, queued: ["200"]) == ["pid 100 xcodebuild"])
  }

  @Test("old xcforge artifacts are pruned, others are kept")
  func pruneArtifacts() throws {
    let dir = makeTempDir()
    defer { try? FileManager.default.removeItem(atPath: dir) }
    let fm = FileManager.default
    let old = Date().addingTimeInterval(-3 * 24 * 3600)
    for name in ["xcf-test-1-2-ab.txt", "xcf-test-1-2-cd.log", "notes.txt", "xcf-new-1-2-ef.txt"] {
      let path = (dir as NSString).appendingPathComponent(name)
      fm.createFile(atPath: path, contents: Data("x".utf8))
      if name != "xcf-new-1-2-ef.txt" {
        try fm.setAttributes([.modificationDate: old], ofItemAtPath: path)
      }
    }
    let removed = ArtifactPruning.prune(directory: dir, now: Date())
    #expect(Set(removed) == ["xcf-test-1-2-ab.txt", "xcf-test-1-2-cd.log"])
    #expect(fm.fileExists(atPath: (dir as NSString).appendingPathComponent("notes.txt")))
    #expect(fm.fileExists(atPath: (dir as NSString).appendingPathComponent("xcf-new-1-2-ef.txt")))
    #expect(ArtifactPruning.isXCForgeArtifact("xcf-test-1-2-ab.xcresult"))
    #expect(!ArtifactPruning.isXCForgeArtifact("xcf-test.png"))
  }

  @Test("a landscape capture reports landscape point sizes")
  func orientedPointSize() {
    let landscape = ScreenshotShaping.orientedPointSize(width: 402, height: 874, pixelWidth: 2622, pixelHeight: 1206)
    #expect(landscape.width == 874 && landscape.height == 402)
    let portrait = ScreenshotShaping.orientedPointSize(width: 402, height: 874, pixelWidth: 1206, pixelHeight: 2622)
    #expect(portrait.width == 402 && portrait.height == 874)
  }

  @Test("set_orientation takes a simulator")
  func orientationTakesSimulator() {
    #expect(UITarget.toolNames.contains("set_orientation"))
  }
}

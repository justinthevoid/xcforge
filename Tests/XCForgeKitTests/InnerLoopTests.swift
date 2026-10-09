import Foundation
import Testing

@testable import XCForgeKit

@Suite("Inner loop: typecheck, lsp, snapshots, SwiftPM results, jobs", .serialized)
struct InnerLoopTests {
  private func tempDir() -> String {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("xcforge-loop-\(UUID().uuidString)", isDirectory: true).path
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    return dir
  }

  private func touch(_ path: String, _ contents: String = "") {
    try? FileManager.default.createDirectory(
      atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: path, contents: Data(contents.utf8))
  }

  // MARK: - SwiftPM output

  static let swiftTestOutput = """
    Building for debugging...
    /repo/Sources/Lib/Model.swift:12:9: warning: variable 'x' was never mutated
    /repo/Sources/Lib/Model.swift:30:5: error: cannot find 'missing' in scope
    /repo/Sources/Lib/Model.swift:30:5: error: cannot find 'missing' in scope
    Test Suite 'All tests' started at 2026-10-09 10:00:00.000.
    /repo/Tests/LibTests/ModelTests.swift:44: error: -[LibTests.ModelTests testRounding] : XCTAssertEqual failed: ("1") is not equal to ("2")
    Test Case '-[LibTests.ModelTests testRounding]' failed (0.002 seconds).
    Executed 3 tests, with 1 failure (0 unexpected) in 0.004 (0.005) seconds
    Executed 3 tests, with 1 failure (0 unexpected) in 0.004 (0.006) seconds
    ◇ Test run started.
    ✘ Test addsNumbers() recorded an issue at MathTests.swift:8:5: Expectation failed: (sum → 3) == 4
    ✘ Test addsNumbers() failed after 0.001 seconds with 1 issue.
    ✘ Test run with 5 tests in 2 suites failed after 0.010 seconds with 1 issue.
    """

  @Test("compile errors, XCTest and Swift Testing failures, and counts are read from swift test")
  func parseSwiftTest() {
    let parsed = SwiftPMOutput.parse(Self.swiftTestOutput)
    #expect(parsed.errors.count == 1)
    #expect(parsed.errors.first?.text == "/repo/Sources/Lib/Model.swift:30:5: cannot find 'missing' in scope")
    #expect(parsed.warningCount == 1)
    #expect(parsed.failures.count == 2)
    #expect(parsed.failures[0].test == "ModelTests/testRounding")
    #expect(parsed.failures[0].location == "/repo/Tests/LibTests/ModelTests.swift:44")
    #expect(parsed.failures[1].test == "addsNumbers()")
    #expect(parsed.failures[1].location == "MathTests.swift:8:5")
    #expect(parsed.testsRun == 8)
    #expect(parsed.testsFailed == 2)

    let text = parsed.summary(action: "Tests", succeeded: false, output: Self.swiftTestOutput)
    #expect(text.hasPrefix("Tests failed: 8 tests, 2 failed (1 warnings)"))
    #expect(text.contains("ModelTests/testRounding (/repo/Tests/LibTests/ModelTests.swift:44)"))
    #expect(!text.contains("--- last"))
  }

  @Test("a failure nothing parses keeps the end of the raw output")
  func unparsedFailure() {
    let output = (1...100).map { "line \($0)" }.joined(separator: "\n")
    let text = SwiftPMOutput.parse(output).summary(action: "Build", succeeded: false, output: output)
    #expect(text.contains("--- last 40 lines ---"))
    #expect(text.hasSuffix("line 100"))
    #expect(!text.contains("line 60\n"))
  }

  // MARK: - Finding packages

  @Test("packages under the repo are found, skipping build output")
  func discoverPackages() {
    let root = tempDir()
    defer { try? FileManager.default.removeItem(atPath: root) }
    touch(root + "/ios/App/Shared/Package.swift")
    touch(root + "/ios/App/Shared/.build/checkouts/Dep/Package.swift")
    touch(root + "/node_modules/x/Package.swift")
    #expect(SwiftPackageTools.discoverPackages(root: root) == [root + "/ios/App/Shared"])

    switch SwiftPackageTools.resolvePackage(nil, cwd: root) {
    case .success(let path): #expect(path == root + "/ios/App/Shared")
    case .failure(let failure): Issue.record("expected a package: \(failure.message)")
    }
    if case .success = SwiftPackageTools.resolvePackage("missing", cwd: root) {
      Issue.record("a path without Package.swift must fail")
    }
  }

  // MARK: - Options

  @Test("jobs, diagnosticDerivedDataPath and packagePath are read from .xcforge.yaml")
  func yamlKeys() throws {
    let dir = tempDir()
    defer { try? FileManager.default.removeItem(atPath: dir) }
    let path = dir + "/.xcforge.yaml"
    touch(path, "jobs: 6\ndiagnosticDerivedDataPath: .dd-diag\npackagePath: ios/Shared\n")
    let values = try #require(RepoConfig.load(from: path, configDir: dir))
    #expect(values.jobs == 6)
    #expect(values.diagnosticDerivedDataPath?.hasSuffix("/.dd-diag") == true)
    #expect(values.packagePath?.hasSuffix("/ios/Shared") == true)
    #expect(values.warnings.isEmpty)
  }

  @Test("jobs becomes -jobs on compiling actions only")
  func jobsFlag() {
    let options = XcodebuildOptions(continueAfterErrors: false, jobs: 6)
    #expect(Xcodebuild.apply(options, to: ["-scheme", "A", "build"]) == ["-scheme", "A", "-jobs", "6", "build"])
    #expect(Xcodebuild.apply(options, to: ["-scheme", "A", "clean"]) == ["-scheme", "A", "clean"])
    let explicit = XcodebuildOptions(extraArgs: ["-jobs", "2"], continueAfterErrors: false, jobs: 6)
    #expect(Xcodebuild.apply(explicit, to: ["build"]) == ["-jobs", "2", "build"])
  }

  @Test("an all-errors build uses the diagnostic DerivedData slot")
  func diagnosticSlot() {
    let plain = XcodebuildOptions(derivedDataPath: "/main")
    #expect(plain.withDiagnosticSlot(project: "/x/App.xcodeproj").derivedDataPath == "/main")

    let configured = XcodebuildOptions(derivedDataPath: "/main", allErrors: true, diagnosticDerivedDataPath: "/diag")
    let slot = configured.withDiagnosticSlot(project: "/x/App.xcodeproj")
    #expect(slot.derivedDataPath == "/diag")
    #expect(slot.continueAfterErrors == true)

    let fallback = XcodebuildOptions.defaultDiagnosticDerivedDataPath(project: "/x/App.xcodeproj", home: "/h")
    #expect(fallback.hasPrefix("/h/Library/Developer/Xcode/DerivedData/xcforge-diagnostic-App-"))
    #expect(fallback == XcodebuildOptions.defaultDiagnosticDerivedDataPath(project: "/x/App.xcodeproj", home: "/h"))
    #expect(fallback != XcodebuildOptions.defaultDiagnosticDerivedDataPath(project: "/y/App.xcodeproj", home: "/h"))
  }

  // MARK: - Snapshots

  @Test("snapshot paths map into the worktree and results map back")
  func snapshotPaths() {
    let worktree = SourceSnapshot.worktreePath(repoRoot: "/src/app", root: "/snap")
    #expect(worktree.hasPrefix("/snap/app-"))
    #expect(worktree == SourceSnapshot.worktreePath(repoRoot: "/src/app", root: "/snap"))
    #expect(
      SourceSnapshot.mapPath("/src/app/ios/App.xcodeproj", repoRoot: "/src/app", worktree: worktree)
        == worktree + "/ios/App.xcodeproj")
    #expect(SourceSnapshot.mapPath("/elsewhere/App.xcodeproj", repoRoot: "/src/app", worktree: worktree) == nil)

    struct Report: Codable, Equatable { let errors: [String] }
    let report = Report(errors: [worktree + "/ios/A.swift:3: error: x"])
    let remapped = SourceSnapshot.remap(report, from: worktree, to: "/src/app")
    #expect(remapped == Report(errors: ["/src/app/ios/A.swift:3: error: x"]))
  }

  @Test("a snapshot build keeps out of a configured DerivedData folder")
  func snapshotDerivedData() {
    let options = XcodebuildOptions(derivedDataPath: "/dd")
    let inside = SourceSnapshot.root() + "/app-1234/App.xcodeproj"
    #expect(options.forSnapshot(project: inside).derivedDataPath == "/dd-snapshot")
    #expect(options.forSnapshot(project: "/src/app/App.xcodeproj").derivedDataPath == "/dd")
  }

  // MARK: - Typecheck and lsp

  @Test("a target builds through its own scheme, else -target in the project that has it")
  func targetSelector() {
    let listing = BuildTools.ProjectListing(schemes: ["App", "Shared"], targets: [])
    let project = BuildTools.ProjectListing(schemes: [], targets: ["App", "Widget"])
    #expect(
      BuildTools.targetSelector("Shared", project: "/a/App.xcworkspace", listing: listing, projects: [])
        == ["-workspace", "/a/App.xcworkspace", "-scheme", "Shared"])
    #expect(
      BuildTools.targetSelector(
        "Widget", project: "/a/App.xcworkspace", listing: listing, projects: [("/a/App.xcodeproj", project)])
        == ["-project", "/a/App.xcodeproj", "-target", "Widget"])
    #expect(BuildTools.targetSelector("Nope", project: "/a/App.xcworkspace", listing: listing, projects: []) == nil)
  }

  @Test("xcodebuild -list output gives schemes and targets")
  func projectListing() {
    let json = #"{"project":{"name":"App","schemes":["App"],"targets":["App","AppTests"]}}"#
    let expected = BuildTools.ProjectListing(schemes: ["App"], targets: ["App", "AppTests"])
    #expect(BuildTools.ProjectListing.parse(json) == expected)
    #expect(BuildTools.ProjectListing.parse("not json") == nil)
  }

  @Test("buildServer.json gets the build root xcforge builds into")
  func buildServerPatch() {
    let patched = BuildTools.patchBuildServer(["scheme": "App", "build_root": "/old"], buildRoot: "/dd")
    #expect(patched["build_root"] as? String == "/dd")
    #expect(patched["scheme"] as? String == "App")
  }
}

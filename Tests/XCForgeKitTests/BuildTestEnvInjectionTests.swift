import Foundation
import Testing

@testable import XCForgeKit

/// Recording shell that captures the `environment:` argument passed to xcodebuild.
private actor EnvRecordingShell: ShellExecutor {
  private(set) var xcodebuildEnvironments: [[String: String]?] = []

  nonisolated func run(
    _ executable: String, arguments: [String], workingDirectory: String?,
    environment: [String: String]?, timeout: TimeInterval, outputLimit: Int
  ) async throws -> ShellResult {
    let exe = (executable as NSString).lastPathComponent
    if exe == "xcodebuild" {
      await record(environment)
      return ShellResult(stdout: "** BUILD SUCCEEDED **", stderr: "", exitCode: 0)
    }
    return ShellResult(stdout: "", stderr: "", exitCode: 0)
  }

  nonisolated func xcrun(timeout: TimeInterval, arguments: [String]) async throws -> ShellResult {
    ShellResult(stdout: "", stderr: "", exitCode: 0)
  }

  nonisolated func git(_ arguments: [String], workingDirectory: String, timeout: TimeInterval)
    async throws -> ShellResult
  {
    ShellResult(stdout: "", stderr: "", exitCode: 0)
  }

  private func record(_ environment: [String: String]?) {
    xcodebuildEnvironments.append(environment)
  }
}

@Suite("build-test --env injection")
struct BuildTestEnvInjectionTests {

  // MARK: - Pure unit tests for the helper

  @Test("happy path: single entry is prefixed and repo root is injected")
  func singleEntry() throws {
    let result = try TestTools.buildTestRunnerEnvironment(
      userEntries: ["BLESS_BASELINE=1"], repoRoot: "/repo")
    #expect(result["TEST_RUNNER_BLESS_BASELINE"] == "1")
    #expect(result["TEST_RUNNER_XCFORGE_REPO_ROOT"] == "/repo")
    #expect(result.count == 2)
  }

  @Test("repeated flag: every entry is prefixed independently")
  func repeatedEntries() throws {
    let result = try TestTools.buildTestRunnerEnvironment(
      userEntries: ["A=1", "B=2"], repoRoot: "/r")
    #expect(result["TEST_RUNNER_A"] == "1")
    #expect(result["TEST_RUNNER_B"] == "2")
    #expect(result["TEST_RUNNER_XCFORGE_REPO_ROOT"] == "/r")
  }

  @Test("value containing '=' splits on first '=' only")
  func valueWithEquals() throws {
    let result = try TestTools.buildTestRunnerEnvironment(
      userEntries: ["URL=https://x.y?a=b"], repoRoot: "/r")
    #expect(result["TEST_RUNNER_URL"] == "https://x.y?a=b")
  }

  @Test("user-supplied XCFORGE_REPO_ROOT overrides the default")
  func userOverridesRepoRoot() throws {
    let result = try TestTools.buildTestRunnerEnvironment(
      userEntries: ["XCFORGE_REPO_ROOT=/tmp/foo"], repoRoot: "/default")
    #expect(result["TEST_RUNNER_XCFORGE_REPO_ROOT"] == "/tmp/foo")
    // Exactly one entry under that key — no shadowing.
    let matches = result.keys.filter { $0 == "TEST_RUNNER_XCFORGE_REPO_ROOT" }
    #expect(matches.count == 1)
  }

  @Test("malformed: no '=' is rejected")
  func malformedNoEquals() {
    #expect(throws: TestTools.TestRunnerEnvError.self) {
      try TestTools.buildTestRunnerEnvironment(userEntries: ["FOO"], repoRoot: "/r")
    }
  }

  @Test("malformed: empty key is rejected")
  func malformedEmptyKey() {
    #expect(throws: TestTools.TestRunnerEnvError.self) {
      try TestTools.buildTestRunnerEnvironment(userEntries: ["=bar"], repoRoot: "/r")
    }
  }

  @Test("malformed: key with whitespace is rejected")
  func malformedWhitespaceKey() {
    #expect(throws: TestTools.TestRunnerEnvError.self) {
      try TestTools.buildTestRunnerEnvironment(userEntries: ["A B=1"], repoRoot: "/r")
    }
  }

  @Test("duplicate key: last value wins")
  func duplicateKey() throws {
    let result = try TestTools.buildTestRunnerEnvironment(
      userEntries: ["A=1", "A=2"], repoRoot: "/r")
    #expect(result["TEST_RUNNER_A"] == "2")
  }

  @Test("empty value is allowed (KEY=)")
  func emptyValue() throws {
    let result = try TestTools.buildTestRunnerEnvironment(
      userEntries: ["FLAG="], repoRoot: "/r")
    #expect(result["TEST_RUNNER_FLAG"] == "")
  }

  @Test("error message names the offending entry")
  func errorMessageQuotesEntry() {
    do {
      _ = try TestTools.buildTestRunnerEnvironment(userEntries: ["BADENTRY"], repoRoot: "/r")
      Issue.record("expected error")
    } catch let err as TestTools.TestRunnerEnvError {
      #expect(err.description.contains("BADENTRY"))
    } catch {
      Issue.record("wrong error type: \(error)")
    }
  }

  // MARK: - Integration: env actually reaches xcodebuild

  @Test("runBuildForTesting forwards childEnvironment to env.shell.run")
  func runBuildForTestingForwardsEnv() async throws {
    let shell = EnvRecordingShell()
    let env = Environment(shell: shell)
    let payload: [String: String] = [
      "TEST_RUNNER_BLESS_BASELINE": "1",
      "TEST_RUNNER_XCFORGE_REPO_ROOT": "/repo",
    ]
    let resultPath = "/tmp/xcf-envinj-bft-\(UUID().uuidString).xcresult"
    defer { try? FileManager.default.removeItem(atPath: resultPath) }

    _ = try await TestTools.runBuildForTesting(
      project: "/tmp/fake.xcodeproj", scheme: "S",
      destination: "platform=iOS Simulator,id=FAKE",
      configuration: "Debug", coverage: false, resultPath: resultPath,
      childEnvironment: payload, env: env
    )

    let recorded = await shell.xcodebuildEnvironments
    #expect(recorded.count == 1)
    #expect(recorded.first??["TEST_RUNNER_BLESS_BASELINE"] == "1")
    #expect(recorded.first??["TEST_RUNNER_XCFORGE_REPO_ROOT"] == "/repo")
  }

  @Test("runTestWithoutBuilding forwards childEnvironment to env.shell.run")
  func runTestWithoutBuildingForwardsEnv() async throws {
    let shell = EnvRecordingShell()
    let env = Environment(shell: shell)
    let payload: [String: String] = ["TEST_RUNNER_FOO": "bar"]
    let resultPath = "/tmp/xcf-envinj-twb-\(UUID().uuidString).xcresult"
    defer { try? FileManager.default.removeItem(atPath: resultPath) }

    _ = try await TestTools.runTestWithoutBuilding(
      project: "/tmp/fake.xcodeproj", scheme: "S",
      destination: "platform=iOS Simulator,id=FAKE",
      configuration: "Debug", testplan: nil, filter: nil,
      coverage: false, resultPath: resultPath,
      childEnvironment: payload, env: env
    )

    let recorded = await shell.xcodebuildEnvironments
    #expect(recorded.count == 1)
    #expect(recorded.first??["TEST_RUNNER_FOO"] == "bar")
  }

  // MARK: - Repo-root fallback (matrix row 8)

  @Test("AutoDetect.repoRoot returns nil for a CWD outside any git repo")
  func repoRootFallbackForNonGitCwd() throws {
    let tmp = NSTemporaryDirectory() + "xcf-no-git-" + UUID().uuidString
    try FileManager.default.createDirectory(
      atPath: tmp, withIntermediateDirectories: true, attributes: nil)
    defer { try? FileManager.default.removeItem(atPath: tmp) }

    // Walk-up will hit "/" without finding .git.
    let found = AutoDetect.repoRoot(from: tmp)
    #expect(found == nil, "expected nil for non-git CWD, got \(String(describing: found))")
  }
}

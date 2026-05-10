import Foundation
import MCP
import Testing

@testable import XCForgeKit

/// Recording shell for build_compile: pretends xcodebuild succeeded and counts
/// any simctl install / launch calls (which build_compile must NOT issue).
private actor BuildCompileShell: ShellExecutor {
  private(set) var xcodebuildCount = 0
  private(set) var simctlInstallCount = 0
  private(set) var simctlLaunchCount = 0
  private(set) var simctlBootCount = 0

  nonisolated func run(
    _ executable: String, arguments: [String], workingDirectory: String?,
    environment: [String: String]?, timeout: TimeInterval, outputLimit: Int
  ) async throws -> ShellResult {
    await dispatch(executable: executable, arguments: arguments)
  }

  nonisolated func xcrun(timeout: TimeInterval, arguments: [String]) async throws -> ShellResult {
    await dispatch(executable: "/usr/bin/xcrun", arguments: arguments)
  }

  nonisolated func git(_ arguments: [String], workingDirectory: String, timeout: TimeInterval)
    async throws -> ShellResult
  {
    ShellResult(stdout: "", stderr: "", exitCode: 0)
  }

  func snapshot() -> (xcodebuild: Int, install: Int, launch: Int, boot: Int) {
    (xcodebuildCount, simctlInstallCount, simctlLaunchCount, simctlBootCount)
  }

  private func dispatch(executable: String, arguments: [String]) -> ShellResult {
    let exe = (executable as NSString).lastPathComponent
    if exe == "xcodebuild" {
      xcodebuildCount += 1
      return ShellResult(stdout: "** BUILD SUCCEEDED **", stderr: "", exitCode: 0)
    }
    if exe == "xcrun" {
      let sub = arguments.first ?? ""
      if sub == "simctl" {
        let cmd = arguments.count > 1 ? arguments[1] : ""
        switch cmd {
        case "install": simctlInstallCount += 1
        case "launch": simctlLaunchCount += 1
        case "boot": simctlBootCount += 1
        default: break
        }
      }
    }
    return ShellResult(stdout: "", stderr: "", exitCode: 0)
  }
}

@Suite("build compile")
struct BuildCompileTests {
  /// build_compile must invoke xcodebuild but never simctl install or launch.
  /// (boot is also outside its scope in the compile-only path.)
  @Test("build_compile MCP tool invokes xcodebuild without install/launch")
  func compileSkipsInstallAndLaunch() async throws {
    let shell = BuildCompileShell()
    let session = SessionState()
    // Pre-populate session state so executeBuild does not actually probe the FS.
    await session.setDefaults(
      project: "/tmp/Fake.xcodeproj",
      scheme: "FakeScheme",
      simulator: "iPhone Test"
    )
    let env = Environment(shell: shell, session: session)

    let args: [String: Value] = [
      "project": .string("/tmp/Fake.xcodeproj"),
      "scheme": .string("FakeScheme"),
      "simulator": .string("iPhone Test"),
    ]

    // Dispatch via the registry to confirm the tool is wired up by name.
    _ = await BuildTools.dispatch("build_compile", args, env: env)

    let counts = await shell.snapshot()
    #expect(counts.xcodebuild >= 1, "expected xcodebuild to be invoked at least once")
    #expect(counts.install == 0, "build_compile must not call simctl install")
    #expect(counts.launch == 0, "build_compile must not call simctl launch")
    #expect(counts.boot == 0, "build_compile must not boot the simulator")
  }
}

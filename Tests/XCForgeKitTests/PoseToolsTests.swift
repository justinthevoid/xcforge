import Foundation
import Testing

@testable import XCForgeKit

/// Recording shell that captures the exact `simctl launch` argv used by
/// `launchAppStructured`. Other commands return success without recording.
private actor LaunchArgvShell: ShellExecutor {
  private(set) var launchArgv: [String]?

  nonisolated func run(
    _ executable: String, arguments: [String], workingDirectory: String?,
    environment: [String: String]?, timeout: TimeInterval, outputLimit: Int
  ) async throws -> ShellResult {
    await record(executable: executable, arguments: arguments)
  }

  nonisolated func xcrun(timeout: TimeInterval, arguments: [String]) async throws -> ShellResult {
    await record(executable: "/usr/bin/xcrun", arguments: arguments)
  }

  nonisolated func git(_ arguments: [String], workingDirectory: String, timeout: TimeInterval)
    async throws -> ShellResult
  {
    ShellResult(stdout: "", stderr: "", exitCode: 0)
  }

  func snapshot() -> [String]? { launchArgv }

  private func record(executable: String, arguments: [String]) -> ShellResult {
    let exe = (executable as NSString).lastPathComponent
    if exe == "xcrun", arguments.count >= 2, arguments[0] == "simctl", arguments[1] == "launch" {
      launchArgv = arguments
      // simctl launch prints "<bundleId>: <pid>" on success.
      return ShellResult(
        stdout: "\(arguments[3]): 12345", stderr: "", exitCode: 0)
    }
    return ShellResult(stdout: "", stderr: "", exitCode: 0)
  }
}

@Suite("pose")
struct PoseToolsTests {
  /// The pose flow must append `<key> <name>` to the simctl launch argv.
  /// We exercise this directly through `launchAppStructured(args:)` since the
  /// pose CLI/MCP path composes that with build + install upstream.
  @Test("launchAppStructured forwards args after bundleId in simctl launch argv")
  func launchArgsAreAppended() async throws {
    let shell = LaunchArgvShell()
    let env = Environment(shell: shell)

    _ = try await SimTools.launchAppStructured(
      simulatorUDID: "FAKE-UDID",
      bundleId: "com.example.app",
      args: ["-pose", "Settings"],
      env: env
    )

    let argv = await shell.snapshot()
    #expect(argv == ["simctl", "launch", "FAKE-UDID", "com.example.app", "-pose", "Settings"])
  }

  /// Default key is `-pose`; pose with a custom key should thread through unchanged.
  @Test("custom key replaces default key in launch argv")
  func customKeyOverridesDefault() async throws {
    let shell = LaunchArgvShell()
    let env = Environment(shell: shell)

    _ = try await SimTools.launchAppStructured(
      simulatorUDID: "FAKE-UDID",
      bundleId: "com.example.app",
      args: ["-DebugScreen", "Login"],
      env: env
    )

    let argv = await shell.snapshot()
    #expect(argv == ["simctl", "launch", "FAKE-UDID", "com.example.app", "-DebugScreen", "Login"])
  }

  /// Existing call sites pass nil → original argv shape preserved.
  @Test("nil args preserves the original simctl launch argv (no extra tokens)")
  func nilArgsPreservesArgv() async throws {
    let shell = LaunchArgvShell()
    let env = Environment(shell: shell)

    _ = try await SimTools.launchAppStructured(
      simulatorUDID: "FAKE-UDID",
      bundleId: "com.example.app",
      env: env
    )

    let argv = await shell.snapshot()
    #expect(argv == ["simctl", "launch", "FAKE-UDID", "com.example.app"])
  }
}

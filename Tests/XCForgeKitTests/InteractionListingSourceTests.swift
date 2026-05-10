import Foundation
import Testing

@testable import XCForgeKit

/// Verifies the source-selection policy added to `UITools.renderListing` so `ui ls`
/// no longer returns macOS Simulator.app's menubar tree when an iOS sim is booted
/// and an app is foregrounded. The behavioral surface we exercise here is
/// `isAnySimulatorBooted(env:)` — the input that flips `auto` from AXP to WDA.
@Suite("ui ls source selection", .serialized)
struct InteractionListingSourceTests {

  /// Minimal shell stub that returns a canned `simctl list devices -j` payload.
  private struct SimctlShell: ShellExecutor {
    let payload: String

    func run(
      _ executable: String,
      arguments: [String],
      workingDirectory: String?,
      environment: [String: String]?,
      timeout: TimeInterval,
      outputLimit: Int
    ) async throws -> ShellResult {
      ShellResult(stdout: "", stderr: "", exitCode: 1)
    }

    func xcrun(timeout: TimeInterval, arguments: [String]) async throws -> ShellResult {
      ShellResult(stdout: payload, stderr: "", exitCode: 0)
    }

    func git(_ arguments: [String], workingDirectory: String, timeout: TimeInterval) async throws
      -> ShellResult
    {
      ShellResult(stdout: "", stderr: "", exitCode: 1)
    }
  }

  private func makeEnv(simctlPayload: String) -> Environment {
    Environment(shell: SimctlShell(payload: simctlPayload))
  }

  @Test("isAnySimulatorBooted is true when any device reports state=Booted")
  func detectsBooted() async {
    let payload = """
      {
        "devices": {
          "com.apple.CoreSimulator.SimRuntime.iOS-26-0": [
            {"name": "iPhone 16", "udid": "ABC", "state": "Shutdown"},
            {"name": "iPhone 17", "udid": "DEF", "state": "Booted"}
          ]
        }
      }
      """
    let env = makeEnv(simctlPayload: payload)
    let booted = await UITools.isAnySimulatorBooted(env: env)
    #expect(booted == true)
  }

  @Test("isAnySimulatorBooted is false when no device is booted")
  func detectsNoBooted() async {
    let payload = """
      {
        "devices": {
          "com.apple.CoreSimulator.SimRuntime.iOS-26-0": [
            {"name": "iPhone 16", "udid": "ABC", "state": "Shutdown"}
          ]
        }
      }
      """
    let env = makeEnv(simctlPayload: payload)
    let booted = await UITools.isAnySimulatorBooted(env: env)
    #expect(booted == false)
  }

  @Test("isAnySimulatorBooted returns false on malformed simctl output")
  func detectsMalformed() async {
    let env = makeEnv(simctlPayload: "not json")
    let booted = await UITools.isAnySimulatorBooted(env: env)
    #expect(booted == false)
  }
}

import Foundation
import Testing

@testable import XCForgeKit

@Suite("HangWatchdog")
struct HangWatchdogTests {

  // MARK: - cancel-on-complete

  @Test("cancel before first deadline fires leaves no snapshot file")
  func cancelBeforeFirstDeadline() async throws {
    let path = "/tmp/xcf-test-watchdog-\(UUID().uuidString).txt"
    defer { try? FileManager.default.removeItem(atPath: path) }

    let env = Environment(shell: ImmediateShell())
    let watchdog = HangWatchdog(udid: nil, snapshotPath: path, sampleAt: [9999], env: env)
    watchdog.cancel()
    let result = await watchdog.latestResult
    #expect(result == nil)
    #expect(!FileManager.default.fileExists(atPath: path))
  }

  // MARK: - tick-on-deadline

  @Test("snapshot is written when deadline fires before cancel")
  func snapshotWrittenOnDeadline() async {
    let path = "/tmp/xcf-test-watchdog-\(UUID().uuidString).txt"
    defer { try? FileManager.default.removeItem(atPath: path) }

    let env = Environment(shell: ImmediateShell())
    let watchdog = HangWatchdog(udid: nil, snapshotPath: path, sampleAt: [0.01], env: env)
    // Allow the deadline to fire
    try? await Task.sleep(nanoseconds: 200_000_000)
    watchdog.cancel()
    let result = await watchdog.latestResult
    #expect(result != nil)
    #expect(FileManager.default.fileExists(atPath: path))
  }

  // MARK: - cancel during snapshot is safe

  @Test("cancel during in-flight snapshot does not crash")
  func cancelDuringSnapshot() async {
    let path = "/tmp/xcf-test-watchdog-\(UUID().uuidString).txt"
    defer { try? FileManager.default.removeItem(atPath: path) }

    let env = Environment(shell: SlowShell())
    let watchdog = HangWatchdog(udid: nil, snapshotPath: path, sampleAt: [0.0], env: env)
    // Give it a moment to start the capture, then cancel mid-flight
    try? await Task.sleep(nanoseconds: 20_000_000)
    watchdog.cancel()
    // Awaiting the result should return without crashing
    _ = await watchdog.latestResult
  }

  // MARK: - sample error captured into file

  @Test("sample command failure is logged to snapshot file, not thrown")
  func sampleErrorCapturedToFile() async {
    let path = "/tmp/xcf-test-watchdog-\(UUID().uuidString).txt"
    defer { try? FileManager.default.removeItem(atPath: path) }

    let env = Environment(shell: FailingShell())
    let watchdog = HangWatchdog(udid: nil, snapshotPath: path, sampleAt: [0.01], env: env)
    try? await Task.sleep(nanoseconds: 200_000_000)
    watchdog.cancel()
    let result = await watchdog.latestResult
    // The watchdog result should still be present (soft-fail, not thrown)
    #expect(result != nil)
    let contents = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    #expect(!contents.isEmpty)
    #expect(contents.contains("sample failed:"))
  }
}

// MARK: - Test doubles

private struct ImmediateShell: ShellExecutor {
  func run(
    _ executable: String,
    arguments: [String],
    workingDirectory: String?,
    environment: [String: String]?,
    timeout: TimeInterval,
    outputLimit: Int
  ) async throws -> ShellResult {
    ShellResult(stdout: "", stderr: "", exitCode: 0)
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

private struct SlowShell: ShellExecutor {
  func run(
    _ executable: String,
    arguments: [String],
    workingDirectory: String?,
    environment: [String: String]?,
    timeout: TimeInterval,
    outputLimit: Int
  ) async throws -> ShellResult {
    try? await Task.sleep(nanoseconds: 500_000_000)
    return ShellResult(stdout: "", stderr: "", exitCode: 0)
  }

  func xcrun(timeout: TimeInterval, arguments: [String]) async throws -> ShellResult {
    try? await Task.sleep(nanoseconds: 500_000_000)
    return ShellResult(stdout: "", stderr: "", exitCode: 0)
  }

  func git(_ arguments: [String], workingDirectory: String, timeout: TimeInterval) async throws
    -> ShellResult
  {
    ShellResult(stdout: "", stderr: "", exitCode: 0)
  }
}

private struct FailingShell: ShellExecutor {
  func run(
    _ executable: String,
    arguments: [String],
    workingDirectory: String?,
    environment: [String: String]?,
    timeout: TimeInterval,
    outputLimit: Int
  ) async throws -> ShellResult {
    // Return a fake PID for pgrep so sample/lsof are attempted and can fail.
    if executable.hasSuffix("pgrep") {
      return ShellResult(stdout: "99999", stderr: "", exitCode: 0)
    }
    return ShellResult(stdout: "", stderr: "permission denied", exitCode: 1)
  }

  func xcrun(timeout: TimeInterval, arguments: [String]) async throws -> ShellResult {
    ShellResult(stdout: "", stderr: "permission denied", exitCode: 1)
  }

  func git(_ arguments: [String], workingDirectory: String, timeout: TimeInterval) async throws
    -> ShellResult
  {
    ShellResult(stdout: "", stderr: "permission denied", exitCode: 1)
  }
}

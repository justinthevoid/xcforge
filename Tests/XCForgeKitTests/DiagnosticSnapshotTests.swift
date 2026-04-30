import Foundation
import Testing

@testable import XCForgeKit

@Suite("DiagnosticSnapshot")
struct DiagnosticSnapshotTests {

  // MARK: - Header + section markers

  @Test("snapshot file contains header and all three section markers")
  func snapshotContainsRequiredSections() async {
    let path = "/tmp/xcf-test-snap-\(UUID().uuidString).txt"
    defer { try? FileManager.default.removeItem(atPath: path) }

    let env = Environment(shell: RecordingShell())
    _ = await DiagnosticSnapshot.capture(udid: nil, snapshotPath: path, env: env)

    let contents = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    #expect(contents.contains("xcforge diagnostic snapshot"))
    #expect(contents.contains("=== sample ==="))
    #expect(contents.contains("=== lsof ==="))
    #expect(contents.contains("=== simctl list devices booted ==="))
  }

  // MARK: - Summary line length

  @Test("summary line is 120 characters or fewer")
  func summaryLineFitsLimit() async {
    let path = "/tmp/xcf-test-snap-\(UUID().uuidString).txt"
    defer { try? FileManager.default.removeItem(atPath: path) }

    let longOutput = (0..<20).map { "frame \($0): " + String(repeating: "X", count: 40) }
      .joined(separator: "\n")
    let env = Environment(shell: RecordingShell(sampleOutput: longOutput, pgrepOutput: "99999"))
    let result = await DiagnosticSnapshot.capture(udid: nil, snapshotPath: path, env: env)
    #expect(result.summaryLine.count <= 120)
  }

  // MARK: - Missing UDID skips containermanagerd

  @Test("missing UDID skips containermanagerd section")
  func missingUdidSkipsContainermanagerd() async {
    let path = "/tmp/xcf-test-snap-\(UUID().uuidString).txt"
    defer { try? FileManager.default.removeItem(atPath: path) }

    let env = Environment(shell: RecordingShell())
    _ = await DiagnosticSnapshot.capture(udid: nil, snapshotPath: path, env: env)

    let contents = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    #expect(!contents.contains("=== containermanagerd cache ==="))
  }

  @Test("UDID present includes containermanagerd section")
  func udidPresentIncludesContainermanagerd() async {
    let path = "/tmp/xcf-test-snap-\(UUID().uuidString).txt"
    defer { try? FileManager.default.removeItem(atPath: path) }

    let env = Environment(shell: RecordingShell())
    _ = await DiagnosticSnapshot.capture(
      udid: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF",
      snapshotPath: path,
      env: env
    )

    let contents = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    #expect(contents.contains("=== containermanagerd cache ==="))
  }

  // MARK: - Appends to existing file

  @Test("second capture appends with separator rather than overwriting")
  func appendsWithSeparator() async {
    let path = "/tmp/xcf-test-snap-\(UUID().uuidString).txt"
    defer { try? FileManager.default.removeItem(atPath: path) }

    let env = Environment(shell: RecordingShell())
    _ = await DiagnosticSnapshot.capture(udid: nil, snapshotPath: path, env: env)
    _ = await DiagnosticSnapshot.capture(udid: nil, snapshotPath: path, env: env)

    let contents = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    let separatorCount =
      contents.components(separatedBy: String(repeating: "-", count: 60)).count
      - 1
    #expect(separatorCount >= 1)
    // Both snapshots should appear
    let headerCount = contents.components(separatedBy: "xcforge diagnostic snapshot").count - 1
    #expect(headerCount == 2)
  }

  // MARK: - no sample data fallback

  @Test("summary line returns 'no sample data' when sample produces no output")
  func summaryLineNoData() async {
    let path = "/tmp/xcf-test-snap-\(UUID().uuidString).txt"
    defer { try? FileManager.default.removeItem(atPath: path) }

    let env = Environment(shell: RecordingShell(sampleOutput: "", pgrepOutput: "99999"))
    let result = await DiagnosticSnapshot.capture(udid: nil, snapshotPath: path, env: env)
    #expect(result.summaryLine == "no sample data")
  }
}

// MARK: - Test double

private struct RecordingShell: ShellExecutor {
  let sampleOutput: String
  let pgrepOutput: String

  init(sampleOutput: String = "frame 0: main\nframe 1: swiftc", pgrepOutput: String = "") {
    self.sampleOutput = sampleOutput
    self.pgrepOutput = pgrepOutput
  }

  func run(
    _ executable: String,
    arguments: [String],
    workingDirectory: String?,
    environment: [String: String]?,
    timeout: TimeInterval,
    outputLimit: Int
  ) async throws -> ShellResult {
    if executable.hasSuffix("pgrep") {
      return ShellResult(stdout: pgrepOutput, stderr: "", exitCode: pgrepOutput.isEmpty ? 1 : 0)
    }
    if executable.hasSuffix("sample") {
      return ShellResult(stdout: sampleOutput, stderr: "", exitCode: 0)
    }
    if executable.hasSuffix("lsof") {
      return ShellResult(stdout: "lsof output line 1", stderr: "", exitCode: 0)
    }
    if executable.hasSuffix("ls") {
      return ShellResult(stdout: "ls output", stderr: "", exitCode: 0)
    }
    return ShellResult(stdout: "", stderr: "", exitCode: 0)
  }

  func xcrun(timeout: TimeInterval, arguments: [String]) async throws -> ShellResult {
    // simctl list devices booted
    ShellResult(stdout: "== Devices ==\niPhone 16 (booted)", stderr: "", exitCode: 0)
  }

  func git(_ arguments: [String], workingDirectory: String, timeout: TimeInterval) async throws
    -> ShellResult
  {
    ShellResult(stdout: "", stderr: "", exitCode: 0)
  }
}

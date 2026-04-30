import Foundation

/// Captures a point-in-time diagnostic snapshot of a running xcodebuild process.
///
/// All steps are best-effort: a failure in `sample`, `lsof`, or `simctl` is logged to the
/// snapshot file and execution continues. No step blocks the primary xcodebuild process.
enum DiagnosticSnapshot {
  struct Result: Sendable {
    let filePath: String
    let summaryLine: String
  }

  static func capture(udid: String?, snapshotPath: String, env: Environment) async -> Result {
    var sections: [String] = []
    sections.append("=== xcforge diagnostic snapshot ===")
    sections.append("Timestamp: \(ISO8601DateFormatter().string(from: Date()))")

    let pgrepResult = try? await env.shell.run(
      "/usr/bin/pgrep", arguments: ["-n", "xcodebuild"], timeout: 5)
    let pidStr =
      pgrepResult?.stdout
      .split(separator: "\n", omittingEmptySubsequences: true)
      .first
      .map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
    sections.append("xcodebuild PID: \(pidStr.isEmpty ? "not found" : pidStr)")
    sections.append("")

    // --- sample ---
    sections.append("=== sample ===")
    var sampleText = ""
    if !pidStr.isEmpty {
      let sampleResult = try? await env.shell.run(
        "/usr/bin/sample", arguments: [pidStr, "2", "-mayDie"], timeout: 10)
      if let out = sampleResult?.stdout, !out.isEmpty {
        sampleText = out
        sections.append(out)
      } else {
        sections.append("sample failed: \(sampleResult?.stderr ?? "no output")")
      }
    } else {
      sections.append("sample skipped: xcodebuild not found")
    }

    // --- lsof ---
    sections.append("")
    sections.append("=== lsof ===")
    if !pidStr.isEmpty {
      let lsofResult = try? await env.shell.run(
        "/usr/bin/lsof", arguments: ["-p", pidStr], timeout: 10)
      let raw = lsofResult?.stdout ?? ""
      let lsofLines = raw.split(separator: "\n", omittingEmptySubsequences: false).prefix(200)
      sections.append(lsofLines.joined(separator: "\n"))
    } else {
      sections.append("lsof skipped: xcodebuild not found")
    }

    // --- simctl ---
    sections.append("")
    sections.append("=== simctl list devices booted ===")
    let simctlResult = try? await env.shell.run(
      "/usr/bin/xcrun", arguments: ["simctl", "list", "devices", "booted"], timeout: 10)
    sections.append(simctlResult?.stdout ?? "simctl failed")

    // --- containermanagerd cache (when UDID is known) ---
    if let udid {
      sections.append("")
      sections.append("=== containermanagerd cache ===")
      let cacheDir =
        "\(NSHomeDirectory())/Library/Developer/CoreSimulator/Devices/\(udid)"
        + "/data/Library/Caches/com.apple.containermanagerd"
      let lsResult = try? await env.shell.run(
        "/bin/ls", arguments: ["-la", cacheDir], timeout: 5)
      sections.append(lsResult?.stdout ?? "ls failed")
    }

    let content = sections.joined(separator: "\n")
    let separator = "\n" + String(repeating: "-", count: 60) + "\n\n"
    let existing = (try? String(contentsOfFile: snapshotPath, encoding: .utf8)) ?? ""
    let output = existing.isEmpty ? content : existing + separator + content
    try? output.write(toFile: snapshotPath, atomically: true, encoding: .utf8)

    return Result(filePath: snapshotPath, summaryLine: makeSummaryLine(from: sampleText))
  }

  private static func makeSummaryLine(from sampleOutput: String) -> String {
    let nonEmpty = sampleOutput.split(separator: "\n")
      .map { String($0) }
      .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    let joined = nonEmpty.prefix(5).joined(separator: " | ")
    guard !joined.isEmpty else { return "no sample data" }
    return joined.count <= 120 ? joined : String(joined.prefix(117)) + "..."
  }
}

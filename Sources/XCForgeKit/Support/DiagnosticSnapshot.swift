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

  // MARK: - Verdict classification

  /// Classifies the dominant hang pattern in a diagnostic snapshot.
  public enum HangVerdict: String, Sendable {
    case swbbuildserviceDeadlock = "swbbuildservice_deadlock"
    case dtdevicekitHang = "dtdevicekit_hang"
    case timeout = "timeout"
  }

  /// Read a snapshot file and classify the hang verdict.
  static func classifyVerdict(snapshotPath: String) -> HangVerdict {
    let content = (try? String(contentsOfFile: snapshotPath, encoding: .utf8)) ?? ""
    return classifyVerdictFromContent(content)
  }

  /// Classify a hang verdict from snapshot content.
  ///
  /// Classifier scoping rules (critical):
  /// - DTDeviceKit: checks the *parent* section only (text before the first child header).
  /// - SWBBuildService deadlock: checks only child sections whose header names "SWBBuildService".
  static func classifyVerdictFromContent(_ content: String) -> HangVerdict {
    let childSectionHeader = "=== child process samples ==="

    // Split content into parent section and child sections
    if let childHeaderRange = content.range(of: childSectionHeader) {
      let parentSection = String(content[content.startIndex..<childHeaderRange.lowerBound])
      let childSection = String(content[childHeaderRange.upperBound...])

      // DTDeviceKit: check parent section only
      if parentSection.contains("DTDKRemoteDeviceConnection") {
        return .dtdevicekitHang
      }

      // SWBBuildService deadlock: check only SWBBuildService-named child sections
      if swbbuildserviceDeadlockPresent(in: childSection) {
        return .swbbuildserviceDeadlock
      }
    } else {
      // No child section header — check entire content for DTDeviceKit only.
      // Do NOT match SWBBuildService symbol here: it must be in a named child section.
      if content.contains("DTDKRemoteDeviceConnection") {
        return .dtdevicekitHang
      }
    }

    return .timeout
  }

  // MARK: - Capture

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

    // --- child process samples (appended below legacy sections) ---
    if !pidStr.isEmpty {
      let childSamples = await captureChildSamples(parentPid: pidStr, env: env)
      if !childSamples.isEmpty {
        sections.append("")
        sections.append("=== child process samples ===")
        sections.append(childSamples)
      }
    }

    let content = sections.joined(separator: "\n")
    let separator = "\n" + String(repeating: "-", count: 60) + "\n\n"
    let existing = (try? String(contentsOfFile: snapshotPath, encoding: .utf8)) ?? ""
    let output = existing.isEmpty ? content : existing + separator + content
    try? output.write(toFile: snapshotPath, atomically: true, encoding: .utf8)

    return Result(filePath: snapshotPath, summaryLine: makeSummaryLine(from: sampleText))
  }

  // MARK: - Child process sampling

  /// BFS walk of child PIDs via `pgrep -P`, capped at 20 descendants.
  /// For each child: sample via `/usr/bin/sample` and append under a header.
  static func captureChildSamples(parentPid: String, env: Environment) async -> String {
    var visited = Set<String>([parentPid])
    var queue = [parentPid]
    var childPids: [String] = []

    while !queue.isEmpty && childPids.count < 20 {
      let current = queue.removeFirst()
      let pgrepResult = try? await env.shell.run(
        "/usr/bin/pgrep", arguments: ["-P", current], timeout: 5)
      let pids =
        (pgrepResult?.stdout ?? "")
        .split(separator: "\n", omittingEmptySubsequences: true)
        .map { String($0).trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty && !visited.contains($0) && $0 != parentPid }

      for pid in pids {
        visited.insert(pid)
        queue.append(pid)
        if childPids.count < 20 {
          childPids.append(pid)
        }
      }
    }

    guard !childPids.isEmpty else { return "" }

    var sections: [String] = []
    for pid in childPids {
      let nameResult = try? await env.shell.run(
        "/bin/ps", arguments: ["-p", pid, "-o", "comm="], timeout: 5)
      let rawName = (nameResult?.stdout ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      let processName = rawName.isEmpty ? "unknown" : (rawName as NSString).lastPathComponent

      sections.append("=== child \(pid) (\(processName)) ===")

      let sampleResult = try? await env.shell.run(
        "/usr/bin/sample", arguments: [pid, "2", "-mayDie"], timeout: 10)
      if let out = sampleResult?.stdout, !out.isEmpty {
        sections.append(out)
      } else {
        sections.append("sample failed: \(sampleResult?.stderr ?? "no output")")
      }
    }

    return sections.joined(separator: "\n")
  }

  // MARK: - Private helpers

  private static func swbbuildserviceDeadlockPresent(in childSectionContent: String) -> Bool {
    // Split child content by child section headers: "=== child <pid> (<name>) ==="
    // Only look for the deadlock symbol in sections whose name contains "SWBBuildService".
    let headerPrefix = "=== child "
    var remaining = childSectionContent

    while let headerStart = remaining.range(of: headerPrefix) {
      // Find the end of the header line
      let afterPrefix = remaining[headerStart.upperBound...]
      guard let headerEnd = afterPrefix.range(of: "\n") else { break }

      let header = String(remaining[headerStart.lowerBound..<headerEnd.upperBound])
      remaining = String(remaining[headerEnd.upperBound...])

      // Find the start of the next child header (or end of content)
      let sectionBody: String
      if let nextHeader = remaining.range(of: headerPrefix) {
        sectionBody = String(remaining[remaining.startIndex..<nextHeader.lowerBound])
      } else {
        sectionBody = remaining
      }

      // Only check sections whose header names "SWBBuildService"
      if header.contains("SWBBuildService") && sectionBody.contains("swift_task_asyncMainDrainQueue") {
        return true
      }
    }

    return false
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

import Foundation

enum ConsoleRenderer {
  static func renderJSON(_ result: ConsoleResult) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(result)
    return String(data: data, encoding: .utf8) ?? "{}"
  }

  static func renderLaunch(_ result: ConsoleResult) -> String {
    var lines: [String] = []
    lines.append(result.message)
    if let bid = result.bundleId {
      lines.append("Bundle ID: \(bid)")
    }
    return lines.joined(separator: "\n")
  }

  static func renderRead(_ result: ConsoleResult, stream: String, cleared: Bool) -> String {
    var lines: [String] = []

    let status = (result.isRunning ?? false) ? "running" : "stopped"
    let header = "App: \(result.bundleId ?? "?") [\(status)]"
    lines.append(header)

    if stream == "stdout" || stream == "both" {
      let stdoutLines = result.stdout ?? []
      if stdoutLines.isEmpty {
        lines.append("")
        lines.append("=== STDOUT (empty) ===")
      } else {
        lines.append("")
        lines.append("=== STDOUT (\(stdoutLines.count) lines) ===")
        lines.append(stdoutLines.joined(separator: "\n"))
      }
    }

    if stream == "stderr" || stream == "both" {
      let stderrLines = result.stderr ?? []
      if stderrLines.isEmpty {
        lines.append("")
        lines.append("=== STDERR (empty) ===")
      } else {
        lines.append("")
        lines.append("=== STDERR (\(stderrLines.count) lines) ===")
        lines.append(stderrLines.joined(separator: "\n"))
      }
    }

    if cleared {
      lines.append("")
      lines.append("(buffer cleared)")
    }

    return lines.joined(separator: "\n")
  }

  static func renderStop(_ result: ConsoleResult) -> String {
    return result.message
  }

  static func renderError(_ message: String) -> String {
    return "Error: \(message)"
  }
}

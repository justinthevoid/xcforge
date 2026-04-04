import Foundation

enum LogRenderer {
  static func renderRead(summary: String, logs: String, lineCount: Int) -> String {
    var lines: [String] = []
    lines.append(summary)
    if !logs.isEmpty {
      lines.append(logs)
    }
    lines.append("\n\(lineCount) line(s) shown")
    return lines.joined(separator: "\n")
  }
}

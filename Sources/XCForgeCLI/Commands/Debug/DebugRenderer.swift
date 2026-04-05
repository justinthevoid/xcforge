import Foundation
import XCForgeKit

enum DebugRenderer {

  static func renderAttach(_ result: DebuggerProvider.AttachResult) -> String {
    var lines = [String]()
    lines.append("Attached to PID \(result.pid)")
    lines.append("Session: \(result.sessionId)")
    lines.append("Status: \(result.status)")
    return lines.joined(separator: "\n")
  }

  static func renderBreakpoint(_ result: DebuggerProvider.BreakpointResult) -> String {
    let resolvedStr = result.resolved ? "resolved" : "unresolved"
    return "Breakpoint \(result.breakpointId) set (\(resolvedStr))"
  }

  static func renderRemoveBreakpoint(_ result: DebuggerProvider.RemoveBreakpointResult) -> String {
    return result.removed ? "Breakpoint removed" : "Breakpoint not removed"
  }

  static func renderVariable(_ result: DebuggerProvider.InspectResult) -> String {
    var lines = [String]()
    lines.append("Expression: \(result.expression)")
    if !result.type.isEmpty {
      lines.append("Type: \(result.type)")
    }
    lines.append("Value: \(result.value)")
    if !result.summary.isEmpty {
      lines.append("Summary: \(result.summary)")
    }
    return lines.joined(separator: "\n")
  }

  static func renderBacktrace(_ frames: [DebuggerProvider.FrameInfo]) -> String {
    guard !frames.isEmpty else { return "(no frames)" }
    var lines = [String]()
    for frame in frames {
      var line = "  frame #\(frame.frameIndex): \(frame.address) \(frame.symbol)"
      if let file = frame.file {
        line += " at \(file)"
        if let ln = frame.line { line += ":\(ln)" }
      }
      lines.append(line)
    }
    return lines.joined(separator: "\n")
  }

  static func renderContinue(_ result: DebuggerProvider.ContinueResult) -> String {
    var lines = [String]()
    lines.append("Stop reason: \(result.stopReason)")
    lines.append("Thread: \(result.threadIndex), Frame: \(result.frameIndex)")
    return lines.joined(separator: "\n")
  }

  static func renderCommand(_ result: DebuggerProvider.CommandResult) -> String {
    return result.output
  }
}

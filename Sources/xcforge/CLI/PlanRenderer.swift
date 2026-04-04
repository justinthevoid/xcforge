import Foundation
import xcforgeCore

enum PlanRenderer {
    static func render(_ report: PlanReport) -> String {
        var lines: [String] = []

        if report.totalSteps == 0 {
            lines.append("Plan: (empty) — 0 steps")
            return lines.joined(separator: "\n")
        }

        lines.append("Plan Execution Report")
        lines.append(String(repeating: "─", count: 60))

        for step in report.steps {
            let icon = statusIcon(step.status)
            let dur = step.durationMs < 1000
                ? "\(step.durationMs)ms"
                : String(format: "%.1fs", Double(step.durationMs) / 1000)
            var line = "  \(icon) [\(step.index)] \(step.type) — \(dur)"
            if let detail = step.detail {
                line += "\n      \(detail)"
            }
            lines.append(line)
        }

        lines.append(String(repeating: "─", count: 60))

        let totalDur = report.totalDurationMs < 1000
            ? "\(report.totalDurationMs)ms"
            : String(format: "%.1fs", Double(report.totalDurationMs) / 1000)

        var summary = "\(report.passed) passed"
        if report.failed > 0 { summary += ", \(report.failed) failed" }
        if report.skipped > 0 { summary += ", \(report.skipped) skipped" }
        if report.suspended { summary += ", SUSPENDED" }
        summary += " — \(totalDur)"
        lines.append(summary)

        if let sessionId = report.sessionId {
            lines.append("")
            lines.append("⏸ Plan suspended. Session: \(sessionId)")
            if let q = report.suspendQuestion {
                lines.append("  Question: \(q)")
            }
            lines.append("  Resume: xcforge plan decide --session-id \(sessionId) --decision <accept|dismiss|skip|abort>")
        }

        return lines.joined(separator: "\n")
    }

    private static func statusIcon(_ status: StepStatus) -> String {
        switch status {
        case .passed:    return "✓"
        case .failed:    return "✗"
        case .skipped:   return "⏭"
        case .suspended: return "⏸"
        }
    }
}

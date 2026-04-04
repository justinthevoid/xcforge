import Foundation

enum ScreenshotRenderer {
    static func renderCapture(_ result: ScreenshotResult) -> String {
        var lines: [String] = []
        lines.append("Screenshot captured")
        lines.append("Path: \(result.path)")
        lines.append("Format: \(result.format)")
        lines.append("Size: \(result.sizeKB)KB")
        return lines.joined(separator: "\n")
    }

    static func renderBaseline(_ result: ScreenshotResult) -> String {
        var lines: [String] = []
        lines.append("Baseline saved")
        lines.append("Path: \(result.path)")
        lines.append("Size: \(result.sizeKB)KB")
        return lines.joined(separator: "\n")
    }

    static func renderCompare(_ result: VisualCompareResult, name: String) -> String {
        var lines: [String] = []

        let status = result.passed ? "PASS" : "FAIL"
        lines.append("[\(status)] Visual comparison: \(name)")
        lines.append(String(
            format: "Diff: %.2f%% (threshold: %.1f%%)",
            result.diffPercent, result.threshold
        ))
        lines.append("Changed pixels: \(result.changedPixels) / \(result.totalPixels)")
        lines.append("Baseline: \(result.baselinePath)")
        lines.append("Current:  \(result.currentPath)")
        if let diffPath = result.diffPath {
            lines.append("Diff:     \(diffPath)")
        }

        return lines.joined(separator: "\n")
    }
}

import Foundation

enum AccessibilityRenderer {
    static func renderDynamicType(_ result: DynamicTypeResult) -> String {
        var lines: [String] = []

        let status = result.passed ? "PASS" : "FAIL"
        lines.append("[\(status)] Dynamic Type Accessibility Check (\(result.elapsed)s)")
        lines.append(String(format: "Threshold: %.1f%%", result.threshold))
        lines.append("Sizes tested: \(result.sizesChecked)")
        if result.failures > 0 {
            lines.append("Failures: \(result.failures)")
        }
        lines.append("")

        for s in result.sizes {
            let icon: String
            if s.isBase {
                icon = "[BASE]"
            } else {
                icon = s.passed ? "[OK]" : "[FAIL]"
            }
            let diffStr = s.isBase ? "—" : String(format: "%.2f%%", s.diffPercent)
            lines.append("  \(icon) \(s.shortName) (\(s.width)x\(s.height)) diff: \(diffStr)")
            if let dp = s.diffPath {
                lines.append("       Diff: \(dp)")
            }
        }

        if !result.errors.isEmpty {
            lines.append("")
            lines.append("Errors:")
            for e in result.errors {
                lines.append("  [ERR] \(e.category): \(e.error)")
            }
        }

        return lines.joined(separator: "\n")
    }

    static func renderLocalization(_ result: LocalizationResult) -> String {
        var lines: [String] = []

        let status = result.passed ? "PASS" : "FAIL"
        lines.append("[\(status)] Localization Layout Check (\(result.elapsed)s)")
        lines.append(String(format: "Threshold: %.1f%%", result.threshold))
        lines.append("Locales tested: \(result.localesChecked)")
        if result.failures > 0 {
            lines.append("Failures: \(result.failures)")
        }
        lines.append("")

        for l in result.locales {
            let icon: String
            if l.isBase {
                icon = "[BASE]"
            } else {
                icon = l.passed ? "[OK]" : "[FAIL]"
            }
            let diffStr = l.isBase ? "—" : String(format: "%.2f%%", l.diffPercent)
            let rtlTag = l.isRTL ? " [RTL]" : ""
            lines.append("  \(icon) \(l.locale)\(rtlTag) (\(l.width)x\(l.height)) diff: \(diffStr)")
            if let dp = l.diffPath {
                lines.append("       Diff: \(dp)")
            }
        }

        if !result.errors.isEmpty {
            lines.append("")
            lines.append("Errors:")
            for e in result.errors {
                lines.append("  [ERR] \(e.locale): \(e.error)")
            }
        }

        return lines.joined(separator: "\n")
    }
}

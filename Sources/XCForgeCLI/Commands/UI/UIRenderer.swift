import Foundation

enum UIRenderer {
    static func render(_ result: UIResult) -> String {
        var lines: [String] = []

        lines.append(result.message)

        if let elementId = result.elementId {
            lines.append("Element: \(elementId)")
        }
        if let count = result.elementCount {
            lines.append("Count: \(count)")
        }

        return lines.joined(separator: "\n")
    }
}

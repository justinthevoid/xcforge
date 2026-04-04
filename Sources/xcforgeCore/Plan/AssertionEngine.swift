import Foundation

/// Result of a verification check.
public struct VerifyResult: Sendable {
    public let passed: Bool
    public let detail: String

    public init(passed: Bool, detail: String) {
        self.passed = passed
        self.detail = detail
    }
}

/// Stateless verification engine — each method queries WDA and returns a result.
public enum VerifyEngine {
    public static func verify(_ condition: VerifyCondition, wdaClient: WDAClient) async -> VerifyResult {
        switch condition {
        case .screenContains(let text):
            return await verifyScreenContains(text, wdaClient: wdaClient)
        case .elementLabel(let id, let op, let expected):
            return await verifyElementLabel(id: id, op: op, expected: expected, wdaClient: wdaClient)
        case .elementExists(let using, let value):
            return await verifyElementExists(using: using, value: value, wdaClient: wdaClient)
        case .elementNotExists(let using, let value):
            return await verifyElementNotExists(using: using, value: value, wdaClient: wdaClient)
        case .elementCount(let using, let value, let op, let expected):
            return await verifyElementCount(using: using, value: value, op: op, expected: expected, wdaClient: wdaClient)
        }
    }

    // MARK: - screenContains

    private static func verifyScreenContains(_ text: String, wdaClient: WDAClient) async -> VerifyResult {
        do {
            let source = try await wdaClient.getSource(format: "json")
            let needle = text.lowercased()
            // Extract label, value, and identifier strings from the JSON source tree
            // rather than substring-matching raw JSON (which would match keys and metadata)
            let textValues = extractTextValues(from: source)
            if textValues.contains(where: { $0.lowercased().contains(needle) }) {
                return VerifyResult(passed: true, detail: "Screen contains '\(text)'")
            } else {
                return VerifyResult(passed: false, detail: "Screen does NOT contain '\(text)'")
            }
        } catch {
            return VerifyResult(passed: false, detail: "Failed to get screen source: \(error)")
        }
    }

    /// Extract label, value, and identifier text from WDA JSON source tree.
    private static func extractTextValues(from jsonString: String) -> [String] {
        guard let data = jsonString.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        var values: [String] = []
        collectTextValues(from: root, into: &values)
        return values
    }

    private static func collectTextValues(from obj: [String: Any], into values: inout [String]) {
        for key in ["label", "value", "identifier", "name"] {
            if let str = obj[key] as? String, !str.isEmpty {
                values.append(str)
            }
        }
        // Recurse into children
        if let children = obj["children"] as? [[String: Any]] {
            for child in children {
                collectTextValues(from: child, into: &values)
            }
        }
    }

    // MARK: - elementLabel

    private static func verifyElementLabel(id: String, op: VerifyCondition.LabelOp, expected: String, wdaClient: WDAClient) async -> VerifyResult {
        do {
            let (elementId, _) = try await wdaClient.findElement(using: "accessibility id", value: id)
            let actual = try await wdaClient.getText(elementId: elementId)
            switch op {
            case .equals:
                if actual == expected {
                    return VerifyResult(passed: true, detail: "Element '\(id)' label equals '\(expected)'")
                }
                return VerifyResult(passed: false, detail: "Element '\(id)' label is '\(actual)', expected '\(expected)'")
            case .contains:
                if actual.contains(expected) {
                    return VerifyResult(passed: true, detail: "Element '\(id)' label contains '\(expected)'")
                }
                return VerifyResult(passed: false, detail: "Element '\(id)' label '\(actual)' does not contain '\(expected)'")
            }
        } catch {
            return VerifyResult(passed: false, detail: "Could not find element '\(id)': \(error)")
        }
    }

    // MARK: - elementExists

    private static func verifyElementExists(using: String, value: String, wdaClient: WDAClient) async -> VerifyResult {
        do {
            _ = try await wdaClient.findElement(using: using, value: value)
            return VerifyResult(passed: true, detail: "Element exists: \(using)='\(value)'")
        } catch {
            return VerifyResult(passed: false, detail: "Element NOT found: \(using)='\(value)'")
        }
    }

    // MARK: - elementNotExists

    private static func verifyElementNotExists(using: String, value: String, wdaClient: WDAClient) async -> VerifyResult {
        do {
            _ = try await wdaClient.findElement(using: using, value: value)
            return VerifyResult(passed: false, detail: "Element unexpectedly exists: \(using)='\(value)'")
        } catch {
            return VerifyResult(passed: true, detail: "Element correctly absent: \(using)='\(value)'")
        }
    }

    // MARK: - elementCount

    private static func verifyElementCount(using: String, value: String, op: VerifyCondition.CountOp, expected: Int, wdaClient: WDAClient) async -> VerifyResult {
        do {
            let elements = try await wdaClient.findElements(using: using, value: value)
            let count = elements.count
            switch op {
            case .equals:
                if count == expected {
                    return VerifyResult(passed: true, detail: "Element count \(count) == \(expected)")
                }
                return VerifyResult(passed: false, detail: "Element count \(count) != expected \(expected)")
            case .gte:
                if count >= expected {
                    return VerifyResult(passed: true, detail: "Element count \(count) >= \(expected)")
                }
                return VerifyResult(passed: false, detail: "Element count \(count) < expected \(expected)")
            }
        } catch {
            return VerifyResult(passed: false, detail: "Could not count elements: \(error)")
        }
    }
}

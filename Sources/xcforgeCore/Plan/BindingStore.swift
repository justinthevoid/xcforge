import Foundation

/// Stores element bindings during plan execution. Not thread-safe — used only from the executor's sequential loop.
public final class VariableStore: Sendable {
    public struct ElementBinding: Sendable, Codable {
        public let elementId: String
        public let label: String?

        public init(elementId: String, label: String? = nil) {
            self.elementId = elementId
            self.label = label
        }
    }

    // nonisolated(unsafe) because VariableStore is used single-threaded from PlanExecutor
    nonisolated(unsafe) private var bindings: [String: ElementBinding] = [:]

    public init() {}

    public func bind(_ name: String, _ binding: ElementBinding) {
        bindings[name] = binding
    }

    public func resolve(_ name: String) throws -> ElementBinding {
        guard let binding = bindings[name] else {
            let available = bindings.keys.sorted().map { "$\($0)" }.joined(separator: ", ")
            throw VariableError.undefinedVariable(
                name: "$\(name)",
                available: available.isEmpty ? "(none)" : available
            )
        }
        return binding
    }

    /// Resolve a StepTarget to an element ID. For variables, looks up the store.
    /// For labels, does a live WDA find using accessibility id OR label predicate.
    public func resolveTarget(_ target: StepTarget, wdaClient: WDAClient) async throws -> String {
        switch target {
        case .variable(let name):
            return try resolve(name).elementId
        case .label(let text):
            let escaped = text.replacingOccurrences(of: "'", with: "\\'")
            let predicate = "label == '\(escaped)' OR identifier == '\(escaped)'"
            let (eid, _) = try await wdaClient.findElement(
                using: "predicate string", value: predicate
            )
            return eid
        }
    }

    /// Export all bindings for session persistence (suspend/resume).
    public func exportAll() -> [String: ElementBinding] {
        bindings
    }

    /// Restore bindings from a previous session.
    public func restore(_ saved: [String: ElementBinding]) {
        bindings = saved
    }

    public var isEmpty: Bool { bindings.isEmpty }
    public var count: Int { bindings.count }
}

public enum VariableError: Error, LocalizedError {
    case undefinedVariable(name: String, available: String)

    public var errorDescription: String? {
        switch self {
        case .undefinedVariable(let name, let available):
            return "Undefined variable '\(name)'. Available: \(available)"
        }
    }
}

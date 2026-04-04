import MCP

/// Protocol for tool modules that register and dispatch their own tools.
/// Each conformer owns its tool definitions and dispatch logic locally,
/// eliminating the need for a central switch statement.
public protocol ToolProvider {
    /// The tools this module provides.
    static var tools: [Tool] { get }

    /// Group name for workflow management (enable/disable at runtime).
    /// Defaults to a lowercased version of the type name with "Tools" suffix stripped.
    static var group: String { get }

    /// Dispatch a tool call by name. Returns nil if this module doesn't handle the given name.
    static func dispatch(_ name: String, _ args: [String: Value]?, env: Environment) async -> CallTool.Result?
}

extension ToolProvider {
    public static var group: String {
        let name = String(describing: self)
        let stripped = name.hasSuffix("Tools") ? String(name.dropLast(5)) : name
        return stripped
            .replacing(/([a-z])([A-Z])/, with: { "\($0.output.1)-\($0.output.2)" })
            .lowercased()
    }
}

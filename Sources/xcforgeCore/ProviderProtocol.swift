import MCP

/// Protocol for tool modules that register and dispatch their own tools.
/// Each conformer owns its tool definitions and dispatch logic locally,
/// eliminating the need for a central switch statement.
public protocol ToolProvider {
    /// The tools this module provides.
    static var tools: [Tool] { get }

    /// Dispatch a tool call by name. Returns nil if this module doesn't handle the given name.
    static func dispatch(_ name: String, _ args: [String: Value]?, env: Environment) async -> CallTool.Result?
}

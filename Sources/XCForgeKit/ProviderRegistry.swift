import MCP

/// Central registry of all tools. Each module self-registers via ToolProvider conformance.
public enum ToolRegistry {
  static let providers: [any ToolProvider.Type] = [
    SessionState.self,
    BuildTools.self,
    SimTools.self,
    ScreenshotTools.self,
    UITools.self,
    LogTools.self,
    GitTools.self,
    ConsoleTools.self,
    TestTools.self,
    VisualTools.self,
    MultiDeviceTools.self,
    AccessibilityTools.self,
    DiagnoseTools.self,
    PlanTools.self,
    SwiftPackageTools.self,
    DeviceTools.self,
    DebuggerProvider.self,
  ]

  // MARK: - Tool Group Management (runtime-only, not persisted)

  /// Groups currently disabled. Access is nonisolated(unsafe) because MCP requests are serial.
  nonisolated(unsafe) private static var disabledGroups: Set<String> = []

  /// All valid group names derived from registered providers.
  public static var allGroups: [String] {
    Array(Set(providers.map { $0.group })).sorted()
  }

  /// Active (non-disabled) providers.
  private static var activeProviders: [any ToolProvider.Type] {
    providers.filter { !disabledGroups.contains($0.group) }
  }

  public static var allTools: [Tool] {
    var tools = activeProviders.flatMap { $0.tools }
    // Always include the tool_groups management tool
    tools.append(toolGroupsTool)
    assert(
      Set(tools.map(\.name)).count == tools.count,
      "Duplicate tool name detected in ToolProvider registrations")
    return tools
  }

  public static func dispatch(_ name: String, _ args: [String: Value]?, env: Environment = .live)
    async -> CallTool.Result
  {
    // Handle built-in tool_groups before checking providers
    if name == "tool_groups" { return handleToolGroups(args) }

    for provider in activeProviders {
      if let result = await provider.dispatch(name, args, env: env) {
        return result
      }
    }
    Log.warn("Unknown tool: \(name)")
    return .fail("Unknown tool: \(name)")
  }

  // MARK: - tool_groups Tool

  private static let toolGroupsTool = Tool(
    name: "tool_groups",
    description:
      "List, enable, or disable tool groups at runtime to reduce MCP tool surface. Changes are runtime-only (not persisted).",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        "list": .object([
          "type": .string("boolean"),
          "description": .string("List all groups with enabled/disabled status"),
        ]),
        "enable": .object([
          "type": .string("array"),
          "items": .object(["type": .string("string")]),
          "description": .string("Group names to enable"),
        ]),
        "disable": .object([
          "type": .string("array"),
          "items": .object(["type": .string("string")]),
          "description": .string("Group names to disable"),
        ]),
      ]),
    ])
  )

  private struct ToolGroupsInput: Decodable {
    let list: Bool?
    let enable: [String]?
    let disable: [String]?
  }

  private static func handleToolGroups(_ args: [String: Value]?) -> CallTool.Result {
    switch ToolInput.decode(ToolGroupsInput.self, from: args) {
    case .failure(let err): return err
    case .success(let input):
      let validGroups = Set(allGroups)

      // Process enable
      if let toEnable = input.enable {
        let unknown = toEnable.filter { !validGroups.contains($0) }
        if !unknown.isEmpty {
          return .fail(
            "Unknown group(s): \(unknown.joined(separator: ", ")). Valid: \(allGroups.joined(separator: ", "))"
          )
        }
        for g in toEnable { disabledGroups.remove(g) }
      }

      // Process disable (protect session-state group — it provides set_defaults and profile tools)
      if let toDisable = input.disable {
        let unknown = toDisable.filter { !validGroups.contains($0) }
        if !unknown.isEmpty {
          return .fail(
            "Unknown group(s): \(unknown.joined(separator: ", ")). Valid: \(allGroups.joined(separator: ", "))"
          )
        }
        let protected: Set<String> = ["session-state"]
        let blocked = toDisable.filter { protected.contains($0) }
        if !blocked.isEmpty {
          return .fail(
            "Cannot disable protected group(s): \(blocked.joined(separator: ", ")). These provide essential session management tools."
          )
        }
        for g in toDisable { disabledGroups.insert(g) }
      }

      // Always return current status
      var lines = ["Tool groups:"]
      for group in allGroups {
        let status = disabledGroups.contains(group) ? "disabled" : "enabled"
        let toolCount = providers.filter { $0.group == group }.flatMap { $0.tools }.count
        lines.append("  \(group): \(status) (\(toolCount) tools)")
      }
      return .ok(lines.joined(separator: "\n"))
    }
  }
}

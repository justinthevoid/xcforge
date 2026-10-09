import Foundation
import MCP
import os

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
    PoseTools.self,
    BlessTools.self,
    WaitReadyTools.self,
  ]

  // MARK: - Tool Group Management (runtime-only, not persisted)

  /// Groups disabled at start (`XCFORGE_TOOL_GROUPS`, yaml `toolGroups`, else the diagnose group)
  /// and problems with that setting.
  private static let startup = ToolSurface.disabledGroups(spec: ToolSurface.startupSpec(), allGroups: allGroups)

  /// Groups currently disabled. MCP requests run concurrently, so access goes through a lock.
  private static let disabledGroupsLock = OSAllocatedUnfairLock(initialState: startup.disabled)
  static var disabledGroups: Set<String> { disabledGroupsLock.withLock { $0 } }

  /// Called after tool_groups changes the list, to send `notifications/tools/list_changed`.
  private static let listChangedHandler = OSAllocatedUnfairLock<(@Sendable () async -> Void)?>(initialState: nil)

  public static func onToolListChanged(_ handler: @escaping @Sendable () async -> Void) {
    listChangedHandler.withLock { $0 = handler }
  }

  /// All valid group names derived from registered providers.
  public static var allGroups: [String] {
    Array(Set(providers.map { $0.group })).sorted()
  }

  /// Active (non-disabled) providers.
  private static var activeProviders: [any ToolProvider.Type] {
    let disabled = disabledGroups
    return providers.filter { !disabled.contains($0.group) }
  }

  /// The shared arguments every tool of a kind takes (build options, simulator, waits).
  static func augment(_ tool: Tool) -> Tool {
    BuildTools.augmentFor(UIWait.augment(UITarget.augment(XcodebuildOptions.augment(tool))))
  }

  /// The tools listed to clients: enabled groups, without deprecated aliases, every argument in
  /// camelCase, and read-only tools marked so clients can approve them without asking.
  public static var allTools: [Tool] {
    var tools = activeProviders.flatMap { $0.tools }
      .filter { ToolSurface.deprecatedAliases[$0.name] == nil }
      .map { ToolSurface.annotate(ToolSurface.canonicalize(augment($0))) }
    // Always include the tool_groups management tool
    tools.append(toolGroupsTool)
    assert(
      Set(tools.map(\.name)).count == tools.count,
      "Duplicate tool name detected in ToolProvider registrations")
    return tools
  }

  /// A registered tool with the argument names its implementation reads, enabled or not and
  /// including deprecated aliases.
  static func declaredTool(_ name: String) -> Tool? {
    if name == toolGroupsTool.name { return toolGroupsTool }
    for provider in providers {
      if let tool = provider.tools.first(where: { $0.name == name }) { return augment(tool) }
    }
    return nil
  }

  /// The group a registered tool belongs to.
  static func group(of name: String) -> String? {
    providers.first { provider in provider.tools.contains { $0.name == name } }?.group
  }

  public static func dispatch(_ name: String, _ args: [String: Value]?, env: Environment = .live)
    async -> CallTool.Result
  {
    // Handle built-in tool_groups before checking providers
    if name == "tool_groups" { return await handleToolGroups(args) }

    if let group = group(of: name), disabledGroups.contains(group) {
      return .fail(
        "\(name) is in the \(group) tool group, which is off. Turn it on with tool_groups (enable: [\"\(group)\"]) or XCFORGE_TOOL_GROUPS=+\(group)."
      )
    }

    // Either casing is accepted: includeConsole or include_console, derivedDataPath or derived_data_path.
    let arguments = declaredTool(name).map { ToolSurface.normalize(args, declared: $0.argumentNames) } ?? args

    // A misspelled argument would otherwise be ignored and the call would quietly use a default.
    if let rejection = unknownArgumentsError(name, arguments) { return rejection }

    // Per-call xcodebuild options (derivedDataPath, buildLock, ...) ride in a task-local so
    // every xcodebuild call made while serving this tool sees them.
    let options =
      XcodebuildOptions.mcpToolNames.contains(name)
      ? XcodebuildOptions.fromMCPArguments(arguments) : XcodebuildOptions()
    await UITarget.select(for: name, args: arguments, env: env)
    let result = await XcodebuildOptions.$current.withValue(options) { () async -> CallTool.Result? in
      for provider in activeProviders {
        if let result = await provider.dispatch(name, arguments, env: env) {
          return result
        }
      }
      return nil
    }
    if let result {
      let waited = await UIWait.afterAction(result, tool: name, args: arguments, env: env)
      return await withNotes(waited, tool: name, env: env)
    }
    Log.warn("Unknown tool: \(name)")
    return .fail("Unknown tool: \(name)")
  }

  /// `.xcforge.yaml` files whose warnings this process already showed.
  private static let shownConfigWarnings = OSAllocatedUnfairLock(initialState: Set<String>())

  /// Add short trailing notes: which project a build or test ran against (so work in a second
  /// worktree is visible), and `.xcforge.yaml` problems the first time each file is used.
  static func withNotes(_ result: CallTool.Result, tool: String, env: Environment) async -> CallTool.Result {
    var notes: [String] = []
    if XcodebuildOptions.mcpToolNames.contains(tool), let project = await env.session.activeProject {
      notes.append("project: \(absolutePath(project))")
    }
    if let deprecation = ToolSurface.deprecationNote(for: tool) { notes.append(deprecation) }
    let warnings = await env.session.configWarnings
    if !warnings.isEmpty, let path = await env.session.configPath,
      shownConfigWarnings.withLock({ $0.insert(path).inserted })
    {
      notes += warnings.map { "config warning: \($0)" }
    }
    guard !notes.isEmpty else { return result }
    let note = Tool.Content.text(text: notes.joined(separator: "\n"), annotations: nil, _meta: nil)
    return CallTool.Result(
      content: result.content + [note], structuredContent: result.structuredContent,
      isError: result.isError, _meta: result._meta)
  }

  private static func absolutePath(_ path: String) -> String {
    let expanded = (path as NSString).expandingTildeInPath
    guard !expanded.hasPrefix("/") else { return (expanded as NSString).standardizingPath }
    let cwd = FileManager.default.currentDirectoryPath as NSString
    return (cwd.appendingPathComponent(expanded) as NSString).standardizingPath
  }

  // MARK: - Argument validation

  /// An error naming arguments the tool doesn't declare, with close matches, or nil when all
  /// are known. Tools whose schema allows extra properties are not checked.
  static func unknownArgumentsError(_ name: String, _ args: [String: Value]?) -> CallTool.Result? {
    guard let args, !args.isEmpty,
      let tool = declaredTool(name),
      case .object(let schema) = tool.inputSchema,
      schema["additionalProperties"]?.boolValue != true,
      let properties = schema["properties"]?.objectValue
    else { return nil }
    let known = Array(properties.keys)
    let unknown = args.keys.filter { properties[$0] == nil }.sorted()
    guard !unknown.isEmpty else { return nil }
    var lines: [String] = []
    for key in unknown {
      if let close = closestArgument(key, in: known) {
        lines.append("Unknown argument '\(key)'; did you mean '\(close)'?")
      } else {
        lines.append("Unknown argument '\(key)'.")
      }
    }
    let valid = known.isEmpty ? "(no arguments)" : known.map(ToolSurface.camelCase).sorted().joined(separator: ", ")
    lines.append("\(name) accepts: \(valid)")
    return .fail(lines.joined(separator: "\n"))
  }

  /// `derived_data_path` → `derivedDataPath` (same letters ignoring case and underscores),
  /// else the nearest name by edit distance.
  private static func closestArgument(_ key: String, in known: [String]) -> String? {
    let folded = key.replacingOccurrences(of: "_", with: "").lowercased()
    if let same = known.first(where: { $0.replacingOccurrences(of: "_", with: "").lowercased() == folded }) {
      return same
    }
    return FuzzyMatch.fuzzyRank(needle: key, candidates: known, maxResults: 1).first?.candidate
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

  private static func handleToolGroups(_ args: [String: Value]?) async -> CallTool.Result {
    switch ToolInput.decode(ToolGroupsInput.self, from: args) {
    case .failure(let err): return err
    case .success(let input):
      let validGroups = Set(allGroups)
      let before = disabledGroups

      // Process enable
      if let toEnable = input.enable {
        let unknown = toEnable.filter { !validGroups.contains($0) }
        if !unknown.isEmpty {
          return .fail(
            "Unknown group(s): \(unknown.joined(separator: ", ")). Valid: \(allGroups.joined(separator: ", "))"
          )
        }
        disabledGroupsLock.withLock { $0.subtract(toEnable) }
      }

      // Process disable (protect session-state group — it provides set_defaults and profile tools)
      if let toDisable = input.disable {
        let unknown = toDisable.filter { !validGroups.contains($0) }
        if !unknown.isEmpty {
          return .fail(
            "Unknown group(s): \(unknown.joined(separator: ", ")). Valid: \(allGroups.joined(separator: ", "))"
          )
        }
        let protected = ToolSurface.protectedGroups
        let blocked = toDisable.filter { protected.contains($0) }
        if !blocked.isEmpty {
          return .fail(
            "Cannot disable protected group(s): \(blocked.joined(separator: ", ")). These provide essential session management tools."
          )
        }
        disabledGroupsLock.withLock { $0.formUnion(toDisable) }
      }

      // Always return current status
      var lines = ["Tool groups:"]
      let disabled = disabledGroups
      for group in allGroups {
        let status = disabled.contains(group) ? "disabled" : "enabled"
        let toolCount = providers.filter { $0.group == group }.flatMap { $0.tools }
          .filter { ToolSurface.deprecatedAliases[$0.name] == nil }.count
        lines.append("  \(group): \(status) (\(toolCount) tools)")
      }
      lines += startup.warnings
      if disabled != before, let handler = listChangedHandler.withLock({ $0 }) {
        await handler()
        lines.append("Clients that follow notifications/tools/list_changed now see the new list.")
      }
      return .ok(lines.joined(separator: "\n"))
    }
  }
}

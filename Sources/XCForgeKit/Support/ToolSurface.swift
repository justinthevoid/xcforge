import Foundation
import MCP

/// What the MCP tool list looks like to an agent: one argument casing, merged tools with
/// their old names kept as hidden aliases, read-only hints, and which groups start enabled.
enum ToolSurface {
  // MARK: - Tool groups

  /// Groups that start disabled. The diagnose workflow tools mostly repeat build_and_diagnose,
  /// test_sim and test_failures, so they cost context without adding much.
  static let defaultOffGroups: Set<String> = ["diagnose"]

  /// Groups that can't be disabled: they hold set_defaults and the profile tools.
  static let protectedGroups: Set<String> = ["session-state"]

  /// The groups disabled at start, from `XCFORGE_TOOL_GROUPS` or the yaml key `toolGroups`.
  ///
  /// A spec is a comma- or space-separated list. `+name` enables a group and `-name` disables
  /// one, starting from the defaults; bare names list the only groups to enable (protected
  /// groups always stay on); `all` enables everything.
  static func disabledGroups(spec: String?, allGroups: [String]) -> (disabled: Set<String>, warnings: [String]) {
    var disabled = defaultOffGroups.intersection(allGroups)
    guard let spec else { return (disabled, []) }
    let separators: Set<Character> = [",", " ", "\t", "[", "]"]
    let entries = spec.split(whereSeparator: { separators.contains($0) }).map(String.init)
    guard !entries.isEmpty else { return (disabled, []) }
    var warnings: [String] = []
    let known = Set(allGroups)
    let bare = entries.filter { !$0.hasPrefix("+") && !$0.hasPrefix("-") && $0 != "all" }
    if entries.contains("all") { disabled = [] }
    if !bare.isEmpty {
      disabled = known.subtracting(bare).subtracting(protectedGroups)
    }
    for entry in entries where entry != "all" {
      let name = entry.hasPrefix("+") || entry.hasPrefix("-") ? String(entry.dropFirst()) : entry
      guard known.contains(name) else {
        warnings.append("toolGroups: unknown group '\(name)'. Groups: \(allGroups.joined(separator: ", "))")
        continue
      }
      if entry.hasPrefix("+") { disabled.remove(name) }
      if entry.hasPrefix("-"), !protectedGroups.contains(name) { disabled.insert(name) }
    }
    return (disabled, warnings)
  }

  /// The start-up spec: the environment variable wins over `.xcforge.yaml`.
  static func startupSpec(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    cwd: String = FileManager.default.currentDirectoryPath
  ) -> String? {
    if let value = environment["XCFORGE_TOOL_GROUPS"], !value.isEmpty { return value }
    return RepoConfig.discover(from: cwd)?.toolGroups
  }

  // MARK: - Argument casing

  /// `include_console` → `includeConsole`. Names without underscores are returned unchanged.
  static func camelCase(_ name: String) -> String {
    guard name.contains("_") else { return name }
    let parts = name.split(separator: "_", omittingEmptySubsequences: true)
    guard let first = parts.first else { return name }
    return String(first) + parts.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
  }

  /// Folded form used to match a passed argument to a declared one: no underscores, lowercased.
  static func folded(_ name: String) -> String {
    name.replacingOccurrences(of: "_", with: "").lowercased()
  }

  /// The tool as listed: every top-level argument in camelCase. Implementations keep reading
  /// their own names; `normalize` maps arguments back.
  static func canonicalize(_ tool: Tool) -> Tool {
    guard case .object(var schema) = tool.inputSchema, case .object(let properties)? = schema["properties"],
      properties.keys.contains(where: { $0.contains("_") })
    else { return tool }
    var renamed: [String: Value] = [:]
    for (key, value) in properties {
      let camel = camelCase(key)
      renamed[properties[camel] == nil ? camel : key] = value
    }
    schema["properties"] = .object(renamed)
    if case .array(let required)? = schema["required"] {
      schema["required"] = .array(
        required.map { item in
          guard case .string(let key) = item, properties[camelCase(key)] == nil else { return item }
          return .string(camelCase(key))
        })
    }
    return tool.replacing(inputSchema: .object(schema))
  }

  /// Arguments renamed to the names the tool declares, accepting either casing
  /// (`derived_data_path` or `derivedDataPath`, `includeConsole` or `include_console`).
  /// Names that match nothing are left for the unknown-argument check.
  static func normalize(_ args: [String: Value]?, declared: [String]) -> [String: Value]? {
    guard let args, !args.isEmpty else { return args }
    let declaredSet = Set(declared)
    var byFolded: [String: String] = [:]
    for name in declared { byFolded[folded(name)] = name }
    var result: [String: Value] = [:]
    for (key, value) in args {
      if declaredSet.contains(key) {
        result[key] = value
      } else if let target = byFolded[folded(key)], args[target] == nil {
        result[target] = value
      } else {
        result[key] = value
      }
    }
    return result
  }

  // MARK: - Merged tools

  /// Old tool names still dispatched for one release, with the call that replaces them.
  static let deprecatedAliases: [String: String] = [
    "click_element": "tap with elementId",
    "tap_coordinates": "tap with x, y",
    "double_tap": "tap with x, y, count: 2",
    "long_press": "tap with x, y, durationMs",
    "ui_tap_pixel": "tap with x, y, pixels: true",
    "indigo_tap": "tap with x, y, hid: true",
    "tap_by_id": "tap with id",
    "tap_by": "tap with using, value",
    "indigo_swipe": "swipe with hid: true",
    "list_elements": "get_source with format: list",
    "find_elements": "find_element with all: true",
    "device_screenshot": "screenshot with device",
  ]

  static func deprecationNote(for name: String) -> String? {
    deprecatedAliases[name].map {
      "note: \(name) is deprecated and will be removed in the next release; use \($0)."
    }
  }

  // MARK: - Read-only hints

  /// Tools that only read state, so clients can approve them without asking.
  static let readOnlyTools: Set<String> = [
    "wda_status", "find_element", "get_text", "get_source", "clipboard_get", "screenshot",
    "list_sims", "sim_info", "list_devices", "device_info", "device_apps", "build_lock_status",
    "discover_projects", "list_schemes", "test_failures", "list_tests", "test_plan_inspect", "git_status",
    "git_diff", "git_log", "swift_package_list", "diagnose_status", "diagnose_evidence", "diagnose_inspect",
    "diagnose_result", "profile_list", "read_logs", "wait_for_log", "read_app_console", "wait_ready",
    "compare_visual", "app_container", "lldb_backtrace", "lldb_inspect_variable",
  ]

  static func annotate(_ tool: Tool) -> Tool {
    guard readOnlyTools.contains(tool.name), tool.annotations.readOnlyHint == nil else { return tool }
    var annotations = tool.annotations
    annotations.readOnlyHint = true
    return tool.replacing(annotations: annotations)
  }
}

extension Tool {
  /// A copy with a different schema or annotations.
  func replacing(inputSchema: Value? = nil, annotations: Tool.Annotations? = nil) -> Tool {
    Tool(
      name: name,
      title: title,
      description: description,
      inputSchema: inputSchema ?? self.inputSchema,
      annotations: annotations ?? self.annotations,
      outputSchema: outputSchema,
      icons: icons,
      _meta: _meta
    )
  }

  /// Top-level argument names in the schema.
  var argumentNames: [String] {
    guard case .object(let schema) = inputSchema, case .object(let properties)? = schema["properties"] else {
      return []
    }
    return Array(properties.keys)
  }
}

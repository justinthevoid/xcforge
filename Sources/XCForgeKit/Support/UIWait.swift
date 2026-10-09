import Foundation
import MCP

/// Waiting on the screen instead of sleeping: after an action, for an element to appear
/// or to go away.
enum UIWait {
  /// How many of several matches are listed with their labels and frames.
  static let listedMatches = 10
  static let pollNanoseconds: UInt64 = 250_000_000

  /// Poll `condition` until it holds or `timeout` seconds pass; checks at least once.
  static func until(timeout: Double, _ condition: () async -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(max(0, timeout))
    while true {
      if await condition() { return true }
      if Date() >= deadline || Task.isCancelled { return false }
      try? await Task.sleep(nanoseconds: pollNanoseconds)
    }
  }

  /// `label "Save" at (20,700 120x44)`, enough to tell matches apart.
  static func describe(elementId: String, wdaClient: WDAClient) async -> String {
    let label = (try? await wdaClient.getElementAttribute("label", elementId: elementId)) ?? ""
    var text = label.isEmpty ? elementId : "\"\(label)\" (\(elementId))"
    if let rect = try? await wdaClient.getElementRect(elementId: elementId) {
      text += " at (\(Int(rect.x)),\(Int(rect.y)) \(Int(rect.width))x\(Int(rect.height)))"
    }
    return text
  }

  // MARK: - After an action

  /// Action tools that accept `wait_for`, `until_gone` and `timeout`.
  static let actionToolNames: Set<String> = [
    "tap", "click_element", "tap_coordinates", "double_tap", "long_press", "swipe", "pinch", "drag_and_drop",
    "type_text", "tap_by_id", "tap_by", "indigo_tap", "indigo_swipe", "ui_tap_pixel", "handle_alert",
  ]

  static let actionProperties: [String: Value] = [
    "wait_for": .object([
      "type": .string("string"),
      "description": .string("After the action, wait until an element with this accessibility id or label appears."),
    ]),
    "until_gone": .object([
      "type": .string("string"),
      "description": .string("After the action, wait until no element has this accessibility id or label."),
    ]),
    "timeout": .object([
      "type": .string("number"),
      "description": .string("Seconds to wait for wait_for / until_gone. Default: 10"),
    ]),
  ]

  /// Add the wait arguments to action tools that don't declare them.
  static func augment(_ tool: Tool) -> Tool {
    guard actionToolNames.contains(tool.name), case .object(var schema) = tool.inputSchema else { return tool }
    var properties = schema["properties"]?.objectValue ?? [:]
    for (key, value) in actionProperties where properties[key] == nil {
      properties[key] = value
    }
    schema["properties"] = .object(properties)
    return Tool(
      name: tool.name,
      title: tool.title,
      description: tool.description,
      inputSchema: .object(schema),
      annotations: tool.annotations,
      outputSchema: tool.outputSchema,
      icons: tool.icons,
      _meta: tool._meta
    )
  }

  /// A predicate matching an element by accessibility id or label.
  static func predicate(for text: String) -> String {
    let escaped = text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
    return "name == '\(escaped)' OR label == '\(escaped)'"
  }

  /// When a successful action asked to wait, wait and add the outcome to its result. A
  /// wait that times out turns the result into a failure naming what didn't happen.
  static func afterAction(
    _ result: CallTool.Result, tool: String, args: [String: Value]?, env: Environment
  ) async -> CallTool.Result {
    guard actionToolNames.contains(tool), result.isError != true, let args else { return result }
    let appear = args["wait_for"]?.stringValue
    let gone = args["until_gone"]?.stringValue
    guard appear != nil || gone != nil else { return result }
    let timeout = args["timeout"]?.doubleValue ?? args["timeout"]?.intValue.map(Double.init) ?? 10

    let start = Date()
    var notes: [String] = []
    var failed = false
    if let appear {
      let seen = await until(timeout: timeout) {
        let ids = try? await env.wdaClient.findElements(using: "predicate string", value: predicate(for: appear))
        return !(ids ?? []).isEmpty
      }
      notes.append(seen ? "'\(appear)' appeared" : "'\(appear)' did not appear within \(Int(timeout))s")
      failed = failed || !seen
    }
    if let gone {
      let remaining = max(0, timeout - Date().timeIntervalSince(start))
      let cleared = await until(timeout: remaining) {
        let ids = try? await env.wdaClient.findElements(using: "predicate string", value: predicate(for: gone))
        return ids?.isEmpty == true
      }
      notes.append(cleared ? "'\(gone)' is gone" : "'\(gone)' still there after \(Int(timeout))s")
      failed = failed || !cleared
    }
    let elapsed = String(format: "%.1f", Date().timeIntervalSince(start))
    let note = Tool.Content.text(text: notes.joined(separator: "; ") + " (\(elapsed)s)", annotations: nil, _meta: nil)
    return CallTool.Result(
      content: result.content + [note], structuredContent: result.structuredContent,
      isError: failed ? true : result.isError, _meta: result._meta)
  }
}

import Foundation
import MCP

/// Every UI tool takes a `simulator`, and its WebDriverAgent calls go to that simulator's
/// own runner. Without it, two booted simulators shared one runner: the screenshot showed
/// one and the taps landed on the other.
enum UITarget {
  /// Tools whose WDA calls follow the selected simulator.
  static var toolNames: Set<String> { Set(UITools.tools.map(\.name)).union(["set_orientation"]) }

  static let simulatorProperty: Value = .object([
    "type": .string("string"),
    "description": .string(
      "Simulator name or UDID. Each simulator has its own WDA; the last one named is used when omitted."),
  ])

  /// Add `simulator` to a UI tool's schema when it doesn't declare one.
  static func augment(_ tool: Tool) -> Tool {
    guard toolNames.contains(tool.name), case .object(var schema) = tool.inputSchema else { return tool }
    var properties = schema["properties"]?.objectValue ?? [:]
    guard properties["simulator"] == nil else { return tool }
    properties["simulator"] = simulatorProperty
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

  /// Point the WDA client at the simulator this call names. The choice sticks for later
  /// calls that name none; until one is named, calls go to the booted simulator as before.
  /// Nothing changes when the name doesn't resolve; the tool reports that itself.
  static func select(for name: String, args: [String: Value]?, env: Environment) async {
    guard toolNames.contains(name), let simulator = args?["simulator"]?.stringValue, simulator != "booted",
      let udid = try? await SimTools.resolveSimulator(simulator, env: env)
    else { return }
    await env.wdaClient.selectSimulator(udid: udid)
  }
}

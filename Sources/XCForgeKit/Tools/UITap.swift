import Foundation
import MCP

/// One `tap` tool for every way of tapping: by element ID, accessibility id or query, or at a
/// point (points or screenshot pixels, single, double or long, through WDA or native HID).
/// The eight older tap tools stay callable as aliases for one release.
extension UITools {
  public static let tools: [Tool] = coreTools + [tapTool]

  static let tapTool = Tool(
    name: "tap",
    description: """
      Tap one target: elementId (from find_element), id (accessibility id, re-found and retried \
      once if stale), using + value (any WDA query), or x + y in points. With x + y: count: 2 \
      double-taps, durationMs long-presses, pixels: true reads x/y as screenshot pixels, hid: true \
      uses native HID on a simulator.
      """,
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        "elementId": .object([
          "type": .string("string"), "description": .string("Element ID from find_element."),
        ]),
        "id": .object([
          "type": .string("string"), "description": .string("Accessibility id to find and tap."),
        ]),
        "using": .object([
          "type": .string("string"),
          "description": .string(
            "Query strategy with value: 'accessibility id', 'class name', 'predicate string', 'class chain'."),
        ]),
        "value": .object([
          "type": .string("string"), "description": .string("Query value for using."),
        ]),
        "x": .object(["type": .string("number"), "description": .string("X in points (pixels with pixels: true).")]),
        "y": .object(["type": .string("number"), "description": .string("Y in points (pixels with pixels: true).")]),
        "count": .object([
          "type": .string("integer"), "description": .string("1 (default) or 2 for a double tap. Needs x, y."),
        ]),
        "durationMs": .object([
          "type": .string("number"), "description": .string("Hold for this long (a long press). Needs x, y."),
        ]),
        "pixels": .object([
          "type": .string("boolean"),
          "description": .string("x, y are screenshot pixels; converted with the simulator's scale."),
        ]),
        "hid": .object([
          "type": .string("boolean"),
          "description": .string("Tap with native HID events on a simulator (bypasses WDA, falls back to it)."),
        ]),
      ]),
    ])
  )

  /// Route a `tap` call to the implementation for its target, with that implementation's
  /// argument names.
  static func tap(_ args: [String: Value]?, env: Environment) async -> CallTool.Result {
    let input = args ?? [:]
    var forwarded: [String: Value] = [:]
    if let simulator = input["simulator"] { forwarded["simulator"] = simulator }

    let hasPoint = input["x"] != nil || input["y"] != nil
    let hasQuery = input["using"] != nil || input["value"] != nil
    let targets = [input["elementId"] != nil, input["id"] != nil, hasQuery, hasPoint].filter { $0 }.count
    guard targets == 1 else {
      return .fail("tap needs exactly one target: elementId, id, using + value, or x + y.")
    }

    let count = input["count"]?.intValue ?? 1
    let duration = input["durationMs"]
    let pixels = input["pixels"]?.boolValue == true
    let hid = input["hid"]?.boolValue == true
    if !hasPoint, count != 1 || duration != nil || pixels || hid {
      return .fail("count, durationMs, pixels and hid need x and y.")
    }

    if let elementId = input["elementId"] {
      forwarded["element_id"] = elementId
      return await clickElement(forwarded, env: env)
    }
    if let id = input["id"] {
      forwarded["id"] = id
      return await tapByID(forwarded, env: env)
    }
    if hasQuery {
      guard let using = input["using"], let value = input["value"] else {
        return .fail("using and value go together, e.g. using: 'predicate string', value: \"label == 'Save'\".")
      }
      forwarded["using"] = using
      forwarded["value"] = value
      return await tapBy(forwarded, env: env)
    }

    guard let x = input["x"], let y = input["y"] else { return .fail("x and y go together.") }
    forwarded["x"] = x
    forwarded["y"] = y
    guard count == 1 || count == 2 else { return .fail("count is 1 or 2.") }
    let modes = [count == 2, duration != nil, pixels, hid].filter { $0 }.count
    guard modes <= 1 else { return .fail("Use one of count: 2, durationMs, pixels or hid at a time.") }
    if count == 2 { return await doubleTap(forwarded, wdaClient: env.wdaClient) }
    if let duration {
      forwarded["duration_ms"] = duration
      return await longPress(forwarded, wdaClient: env.wdaClient)
    }
    if pixels { return await tapPixel(forwarded, env: env) }
    if hid { return await indigoTap(forwarded, wdaClient: env.wdaClient) }
    return await tapCoordinates(forwarded, wdaClient: env.wdaClient)
  }
}

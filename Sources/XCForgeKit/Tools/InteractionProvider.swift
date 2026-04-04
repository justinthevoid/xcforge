import Foundation
import MCP

enum UITools {
  public static let tools: [Tool] = [
    Tool(
      name: "wda_status",
      description: "Check if WebDriverAgent is running and reachable.",
      inputSchema: .object(["type": .string("object"), "properties": .object([:])])
    ),
    Tool(
      name: "handle_alert",
      description:
        "Handle iOS system alerts AND in-app dialogs. Searches Springboard, active app, and ContactsUI (iOS 18+). Actions: accept, dismiss, get_text, accept_all, dismiss_all. One call replaces screenshot→find→click.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "action": .object([
            "type": .string("string"),
            "description": .string(
              "Action: 'accept', 'dismiss', 'get_text', 'accept_all' (batch), or 'dismiss_all' (batch)"
            ),
          ]),
          "button_label": .object([
            "type": .string("string"),
            "description": .string(
              "Optional: specific button to tap (e.g. 'Allow While Using App'). If omitted, uses smart defaults."
            ),
          ]),
        ]),
        "required": .array([.string("action")]),
      ])
    ),
    Tool(
      name: "wda_create_session",
      description: "Create a new WDA session, optionally for a specific app.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "bundle_id": .object([
            "type": .string("string"), "description": .string("Optional bundle ID to activate"),
          ]),
          "wda_url": .object([
            "type": .string("string"),
            "description": .string("WDA base URL. Default: http://localhost:8100"),
          ]),
        ]),
      ])
    ),
    Tool(
      name: "find_element",
      description:
        "Find a UI element. With scroll: true, auto-scrolls the nearest ScrollView/List until the element appears (one call, no manual swipe loop needed).",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "using": .object([
            "type": .string("string"),
            "description": .string(
              "Strategy: 'accessibility id', 'class name', 'predicate string', 'class chain'"),
          ]),
          "value": .object(["type": .string("string"), "description": .string("Search value")]),
          "scroll": .object([
            "type": .string("boolean"),
            "description": .string("Auto-scroll to find off-screen elements. Default: false"),
          ]),
          "direction": .object([
            "type": .string("string"),
            "description": .string(
              "Scroll direction: 'auto' (smart — detects boundaries, reverses automatically), 'down', 'up', 'left', 'right'. Default: 'auto'"
            ),
          ]),
          "max_swipes": .object([
            "type": .string("number"), "description": .string("Max scroll attempts. Default: 10"),
          ]),
        ]),
        "required": .array([.string("using"), .string("value")]),
      ])
    ),
    Tool(
      name: "find_elements",
      description: "Find multiple UI elements matching a query.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "using": .object([
            "type": .string("string"),
            "description": .string(
              "Strategy: 'accessibility id', 'class name', 'xpath', 'predicate string', 'class chain'"
            ),
          ]),
          "value": .object(["type": .string("string"), "description": .string("Search value")]),
        ]),
        "required": .array([.string("using"), .string("value")]),
      ])
    ),
    Tool(
      name: "click_element",
      description: "Click/tap a UI element by its ID.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "element_id": .object([
            "type": .string("string"), "description": .string("Element ID from find_element"),
          ])
        ]),
        "required": .array([.string("element_id")]),
      ])
    ),
    Tool(
      name: "tap_coordinates",
      description: "Tap at specific x,y coordinates on screen.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "x": .object(["type": .string("number"), "description": .string("X coordinate")]),
          "y": .object(["type": .string("number"), "description": .string("Y coordinate")]),
        ]),
        "required": .array([.string("x"), .string("y")]),
      ])
    ),
    Tool(
      name: "double_tap",
      description: "Double-tap at specific coordinates.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "x": .object(["type": .string("number"), "description": .string("X coordinate")]),
          "y": .object(["type": .string("number"), "description": .string("Y coordinate")]),
        ]),
        "required": .array([.string("x"), .string("y")]),
      ])
    ),
    Tool(
      name: "long_press",
      description: "Long-press at specific coordinates.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "x": .object(["type": .string("number"), "description": .string("X coordinate")]),
          "y": .object(["type": .string("number"), "description": .string("Y coordinate")]),
          "duration_ms": .object([
            "type": .string("number"),
            "description": .string("Duration in milliseconds. Default: 1000"),
          ]),
        ]),
        "required": .array([.string("x"), .string("y")]),
      ])
    ),
    Tool(
      name: "swipe",
      description: "Swipe from one point to another.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "start_x": .object(["type": .string("number"), "description": .string("Start X")]),
          "start_y": .object(["type": .string("number"), "description": .string("Start Y")]),
          "end_x": .object(["type": .string("number"), "description": .string("End X")]),
          "end_y": .object(["type": .string("number"), "description": .string("End Y")]),
          "duration_ms": .object([
            "type": .string("number"), "description": .string("Swipe duration in ms. Default: 300"),
          ]),
        ]),
        "required": .array([
          .string("start_x"), .string("start_y"), .string("end_x"), .string("end_y"),
        ]),
      ])
    ),
    Tool(
      name: "pinch",
      description: "Pinch/zoom at a center point. scale > 1 = zoom in, scale < 1 = zoom out.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "center_x": .object([
            "type": .string("number"), "description": .string("Center X coordinate"),
          ]),
          "center_y": .object([
            "type": .string("number"), "description": .string("Center Y coordinate"),
          ]),
          "scale": .object([
            "type": .string("number"),
            "description": .string("Scale factor. >1 = zoom in, <1 = zoom out"),
          ]),
          "duration_ms": .object([
            "type": .string("number"), "description": .string("Duration in ms. Default: 500"),
          ]),
        ]),
        "required": .array([.string("center_x"), .string("center_y"), .string("scale")]),
      ])
    ),
    Tool(
      name: "drag_and_drop",
      description:
        "Drag from source to target. Works with element IDs, coordinates, or mixed. Smart defaults activate drag mode automatically — works for reorderable lists, Kanban boards, sliders, canvas dragging.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "source_element": .object([
            "type": .string("string"),
            "description": .string("Source element ID from find_element"),
          ]),
          "target_element": .object([
            "type": .string("string"),
            "description": .string("Target element ID from find_element"),
          ]),
          "from_x": .object([
            "type": .string("number"),
            "description": .string("Source X coordinate (alternative to source_element)"),
          ]),
          "from_y": .object([
            "type": .string("number"), "description": .string("Source Y coordinate"),
          ]),
          "to_x": .object([
            "type": .string("number"),
            "description": .string("Target X coordinate (alternative to target_element)"),
          ]),
          "to_y": .object([
            "type": .string("number"), "description": .string("Target Y coordinate"),
          ]),
          "press_duration_ms": .object([
            "type": .string("number"),
            "description": .string("Long-press duration to activate drag mode (ms). Default: 1000"),
          ]),
          "hold_duration_ms": .object([
            "type": .string("number"),
            "description": .string("Hold at target before drop (ms). Default: 300"),
          ]),
        ]),
      ])
    ),
    Tool(
      name: "type_text",
      description: "Type text into the currently focused element or a specified element.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "text": .object(["type": .string("string"), "description": .string("Text to type")]),
          "element_id": .object([
            "type": .string("string"), "description": .string("Optional element ID to type into"),
          ]),
          "clear_first": .object([
            "type": .string("boolean"),
            "description": .string("Clear existing text first. Default: false"),
          ]),
        ]),
        "required": .array([.string("text")]),
      ])
    ),
    Tool(
      name: "get_text",
      description: "Get text content of a UI element.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "element_id": .object([
            "type": .string("string"), "description": .string("Element ID from find_element"),
          ])
        ]),
        "required": .array([.string("element_id")]),
      ])
    ),
    Tool(
      name: "get_source",
      description: "Get the full view hierarchy (source tree) of the current screen.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "format": .object([
            "type": .string("string"),
            "description": .string("Format: json, xml, or description. Default: json"),
          ])
        ]),
      ])
    ),
    Tool(
      name: "indigo_tap",
      description:
        "Tap at x,y via native HID (sub-5ms, bypasses WDA). Falls back to WDA if unavailable.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "x": .object(["type": .string("number"), "description": .string("X coordinate (points)")]
          ),
          "y": .object(["type": .string("number"), "description": .string("Y coordinate (points)")]
          ),
          "simulator": .object([
            "type": .string("string"),
            "description": .string("Simulator UDID or 'booted'. Default: 'booted'"),
          ]),
        ]),
        "required": .array([.string("x"), .string("y")]),
      ])
    ),
    Tool(
      name: "clipboard_get",
      description: "Read the device clipboard (pasteboard) content via WDA.",
      inputSchema: .object(["type": .string("object"), "properties": .object([:])])
    ),
    Tool(
      name: "clipboard_set",
      description: "Write text to the device clipboard (pasteboard) via WDA.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "text": .object([
            "type": .string("string"), "description": .string("Text to copy to clipboard"),
          ])
        ]),
        "required": .array([.string("text")]),
      ])
    ),
    Tool(
      name: "indigo_swipe",
      description:
        "Swipe via native HID (sub-5ms per step, bypasses WDA). Falls back to WDA if unavailable.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "start_x": .object([
            "type": .string("number"), "description": .string("Start X (points)"),
          ]),
          "start_y": .object([
            "type": .string("number"), "description": .string("Start Y (points)"),
          ]),
          "end_x": .object(["type": .string("number"), "description": .string("End X (points)")]),
          "end_y": .object(["type": .string("number"), "description": .string("End Y (points)")]),
          "duration_ms": .object([
            "type": .string("number"), "description": .string("Swipe duration in ms. Default: 300"),
          ]),
          "simulator": .object([
            "type": .string("string"),
            "description": .string("Simulator UDID or 'booted'. Default: 'booted'"),
          ]),
        ]),
        "required": .array([
          .string("start_x"), .string("start_y"), .string("end_x"), .string("end_y"),
        ]),
      ])
    ),
  ]

  // MARK: - Input Types

  struct AlertInput: Decodable {
    let action: String
    let button_label: String?
  }

  struct SessionInput: Decodable {
    let bundle_id: String?
    let wda_url: String?
  }

  struct FindElementInput: Decodable {
    let using: String
    let value: String
    let scroll: Bool?
    let direction: String?
    let max_swipes: Int?
  }

  struct FindElementsInput: Decodable {
    let using: String
    let value: String
  }

  struct ElementInput: Decodable {
    let element_id: String
  }

  struct CoordinateInput: Decodable {
    let x: Double
    let y: Double
  }

  struct LongPressInput: Decodable {
    let x: Double
    let y: Double
    let duration_ms: Int?
  }

  struct SwipeInput: Decodable {
    let start_x: Double
    let start_y: Double
    let end_x: Double
    let end_y: Double
    let duration_ms: Int?
    let simulator: String?
  }

  struct PinchInput: Decodable {
    let center_x: Double
    let center_y: Double
    let scale: Double
    let duration_ms: Int?
  }

  struct DragAndDropInput: Decodable {
    let source_element: String?
    let target_element: String?
    let from_x: Double?
    let from_y: Double?
    let to_x: Double?
    let to_y: Double?
    let press_duration_ms: Int?
    let hold_duration_ms: Int?
  }

  struct TypeTextInput: Decodable {
    let text: String
    let element_id: String?
    let clear_first: Bool?
  }

  struct SourceInput: Decodable {
    let format: String?
  }

  struct ClipboardSetInput: Decodable {
    let text: String
  }

  struct IndigoTapInput: Decodable {
    let x: Double
    let y: Double
    let simulator: String?
  }

  // MARK: - Implementations

  static func handleAlert(_ args: [String: Value]?, session: SessionState, wdaClient: WDAClient)
    async -> CallTool.Result
  {
    switch ToolInput.decode(AlertInput.self, from: args) {
    case .failure(let err): return err
    case .success(let input):
      let action = input.action
      let buttonLabel = input.button_label

      switch action {
      case "get_text":
        guard let info = await wdaClient.getAlertText() else {
          Task {
            guard let udid = await DeviceStateStore.currentUDID(session: session) else { return }
            await DeviceStateStore.shared.update(.alert("none"), for: udid)
          }
          return .ok("No alert visible.")
        }
        Task {
          guard let udid = await DeviceStateStore.currentUDID(session: session) else { return }
          await DeviceStateStore.shared.update(.alert("visible: \(info.text)"), for: udid)
        }
        return .ok("Alert text: \(info.text)\nButtons: \(info.buttons.joined(separator: ", "))")

      case "accept":
        do {
          let info = try await wdaClient.acceptAlert(buttonLabel: buttonLabel)
          Task {
            guard let udid = await DeviceStateStore.currentUDID(session: session) else { return }
            await DeviceStateStore.shared.update(.alert("none"), for: udid)
          }
          var msg = "Alert accepted."
          if let info {
            msg +=
              "\nAlert was: \(info.text)\nButtons were: \(info.buttons.joined(separator: ", "))"
          }
          return .ok(msg)
        } catch {
          return .fail("Accept alert failed: \(error)")
        }

      case "dismiss":
        do {
          let info = try await wdaClient.dismissAlert(buttonLabel: buttonLabel)
          Task {
            guard let udid = await DeviceStateStore.currentUDID(session: session) else { return }
            await DeviceStateStore.shared.update(.alert("none"), for: udid)
          }
          var msg = "Alert dismissed."
          if let info {
            msg +=
              "\nAlert was: \(info.text)\nButtons were: \(info.buttons.joined(separator: ", "))"
          }
          return .ok(msg)
        } catch {
          return .fail("Dismiss alert failed: \(error)")
        }

      case "accept_all":
        do {
          let result = try await wdaClient.handleAllAlerts(accept: true)
          if result.count == 0 {
            return .ok("No alerts visible.")
          }
          var msg = "\(result.count) alert(s) accepted."
          for (i, alert) in result.alerts.enumerated() {
            msg +=
              "\n  [\(i + 1)] \(alert.text) → buttons: \(alert.buttons.joined(separator: ", ")) (source: \(alert.source))"
          }
          return .ok(msg)
        } catch {
          return .fail("Accept all alerts failed: \(error)")
        }

      case "dismiss_all":
        do {
          let result = try await wdaClient.handleAllAlerts(accept: false)
          if result.count == 0 {
            return .ok("No alerts visible.")
          }
          var msg = "\(result.count) alert(s) dismissed."
          for (i, alert) in result.alerts.enumerated() {
            msg +=
              "\n  [\(i + 1)] \(alert.text) → buttons: \(alert.buttons.joined(separator: ", ")) (source: \(alert.source))"
          }
          return .ok(msg)
        } catch {
          return .fail("Dismiss all alerts failed: \(error)")
        }

      default:
        return .fail(
          "Unknown action: '\(action)'. Use 'accept', 'dismiss', 'get_text', 'accept_all', or 'dismiss_all'."
        )
      }
    }
  }

  static func wdaStatus(_ args: [String: Value]?, session: SessionState, wdaClient: WDAClient) async
    -> CallTool.Result
  {
    let healthy = await wdaClient.isHealthy()
    let backendName = await wdaClient.backend.displayName
    let fallback = await wdaClient.fallbackInfo
    Task {
      guard let udid = await DeviceStateStore.currentUDID(session: session) else { return }
      await DeviceStateStore.shared.update(
        .wdaStatus(healthy ? "healthy (\(backendName))" : "not responding"), for: udid)
    }

    if healthy {
      do {
        let status = try await wdaClient.status()
        let sessionInfo = "Sessions tracked: \(await wdaClient.sessionCount)"
        var msg =
          "WDA Status: \(status.ready ? "READY" : "NOT READY")\nBackend: \(backendName)\nBundle: \(status.bundleId)\n\(sessionInfo)"
        if let info = fallback {
          msg += "\nInfo: \(info)"
        }
        return .ok(msg)
      } catch {
        return .ok("WDA reachable but status parse failed: \(error)")
      }
    } else {
      return .fail(
        "WDA not responding (health check timeout 2s). Backend: \(backendName). Try restarting WDA or the simulator."
      )
    }
  }

  static func wdaCreateSession(_ args: [String: Value]?, wdaClient: WDAClient) async
    -> CallTool.Result
  {
    switch ToolInput.decode(SessionInput.self, from: args) {
    case .failure(let err): return err
    case .success(let input):
      let customURL = input.wda_url
      let bundleId = input.bundle_id

      if let url = customURL {
        // Per-call override: try custom URL directly, NO deploy attempt.
        let previousURL = await wdaClient.getBaseURL()
        let healthBefore = await wdaClient.isHealthy()
        Log.warn(
          "wdaCreateSession: custom URL=\(url), previous=\(previousURL), healthBefore=\(healthBefore)"
        )
        await wdaClient.setBaseURL(url)

        do {
          // Skip ensureWDARunning — never deploy to a custom URL
          let sid = try await wdaClient.createSession(bundleId: bundleId)
          var msg = "Session created: \(sid) (custom WDA: \(url))"
          if let warning = await wdaClient.sessionWarning {
            msg += "\n\(warning)"
          }
          return .ok(msg)
        } catch {
          await wdaClient.setBaseURL(previousURL)
          let healthAfter = await wdaClient.isHealthy()
          Log.warn(
            "wdaCreateSession: custom URL failed: \(error). healthAfter=\(healthAfter), restored to \(previousURL)"
          )
          return .fail(
            "Connection to \(url) failed: \(error). Default URL (\(previousURL)) restored.")
        }
      }

      // Default path: ensureWDARunning + createSession
      do {
        try await wdaClient.ensureWDARunning()

        let sid = try await wdaClient.createSession(bundleId: bundleId)
        var msg = "Session created: \(sid)"

        if let warning = await wdaClient.sessionWarning {
          msg += "\n\(warning)"
        }
        return .ok(msg)
      } catch {
        return .fail("Session creation failed: \(error)")
      }
    }
  }

  /// AXP handle cache — maps real WDA element IDs to AXP handles for fast click/getText.
  /// Nonisolated because UITools dispatch is serial (MCP request handler).
  nonisolated(unsafe) private static var axpHandles: [String: AXPBridge.AXPHandle] = [:]

  static func findElement(_ args: [String: Value]?, env: Environment) async -> CallTool.Result {
    switch ToolInput.decode(FindElementInput.self, from: args) {
    case .failure(let err): return err
    case .success(let input):
      let scroll = input.scroll ?? false
      let direction = input.direction ?? "auto"
      let maxSwipes = input.max_swipes ?? 10

      // AXP pre-check: stash handle for later click/getText acceleration
      let axpStrategies: Set<String> = ["accessibility id", "class name"]
      var axpHandle: AXPBridge.AXPHandle?
      if !scroll, axpStrategies.contains(input.using), AXPBridge.isAvailable {
        do {
          axpHandle = try await env.axpBridge.findElement(
            strategy: input.using, value: input.value
          )
        } catch {
          Log.warn("AXPBridge findElement miss, falling back to WDA: \(error)")
        }
      }

      // Always obtain a real WDA element ID for fallback compatibility
      do {
        let start = CFAbsoluteTimeGetCurrent()
        let (elementId, swipes) = try await env.wdaClient.findElement(
          using: input.using, value: input.value, scroll: scroll, direction: direction,
          maxSwipes: maxSwipes
        )
        let elapsed = String(format: "%.0f", (CFAbsoluteTimeGetCurrent() - start) * 1000)
        // Stash AXP handle keyed by the real WDA element ID
        if let handle = axpHandle {
          axpHandles[elementId] = handle
        }
        let tag = axpHandle != nil ? "axp+wda" : "wda"
        var msg = "Element found: \(elementId) (\(tag), \(elapsed)ms)"
        if swipes > 0 {
          msg += " — scrolled \(swipes) time(s) \(direction)"
        }
        return .ok(msg)
      } catch {
        return .fail("Element not found: \(error)")
      }
    }
  }

  static func findElements(_ args: [String: Value]?, wdaClient: WDAClient) async -> CallTool.Result {
    switch ToolInput.decode(FindElementsInput.self, from: args) {
    case .failure(let err): return err
    case .success(let input):
      do {
        let start = CFAbsoluteTimeGetCurrent()
        let elements = try await wdaClient.findElements(using: input.using, value: input.value)
        let elapsed = String(format: "%.0f", (CFAbsoluteTimeGetCurrent() - start) * 1000)
        return .ok(
          "Found \(elements.count) elements (\(elapsed)ms):\n"
            + elements.enumerated().map { "  [\($0.offset)] \($0.element)" }.joined(separator: "\n")
        )
      } catch {
        return .fail("Find elements failed: \(error)")
      }
    }
  }

  static func clickElement(_ args: [String: Value]?, env: Environment) async -> CallTool.Result {
    switch ToolInput.decode(ElementInput.self, from: args) {
    case .failure(let err): return err
    case .success(let input):
      // AXP fast-path: try native click, consume handle regardless of outcome
      if let handle = axpHandles.removeValue(forKey: input.element_id) {
        let start = CFAbsoluteTimeGetCurrent()
        do {
          try await env.axpBridge.performClick(handle: handle)
          let elapsed = String(format: "%.0f", (CFAbsoluteTimeGetCurrent() - start) * 1000)
          return .ok("Clicked element \(input.element_id) (axp, \(elapsed)ms)")
        } catch {
          Log.warn("AXPBridge click failed, falling back to WDA: \(error)")
        }
      }

      // WDA path — element_id is always a real WDA handle
      do {
        let start = CFAbsoluteTimeGetCurrent()
        try await env.wdaClient.click(elementId: input.element_id)
        let elapsed = String(format: "%.0f", (CFAbsoluteTimeGetCurrent() - start) * 1000)
        return .ok("Clicked element \(input.element_id) (wda, \(elapsed)ms)")
      } catch {
        return .fail("Click failed: \(error)")
      }
    }
  }

  static func tapCoordinates(_ args: [String: Value]?, wdaClient: WDAClient) async
    -> CallTool.Result
  {
    switch ToolInput.decode(CoordinateInput.self, from: args) {
    case .failure(let err): return err
    case .success(let input):
      do {
        let start = CFAbsoluteTimeGetCurrent()
        try await wdaClient.tap(x: input.x, y: input.y)
        let elapsed = String(format: "%.0f", (CFAbsoluteTimeGetCurrent() - start) * 1000)
        return .ok("Tapped at (\(Int(input.x)), \(Int(input.y))) (\(elapsed)ms)")
      } catch {
        return .fail("Tap failed: \(error)")
      }
    }
  }

  static func doubleTap(_ args: [String: Value]?, wdaClient: WDAClient) async -> CallTool.Result {
    switch ToolInput.decode(CoordinateInput.self, from: args) {
    case .failure(let err): return err
    case .success(let input):
      do {
        try await wdaClient.doubleTap(x: input.x, y: input.y)
        return .ok("Double-tapped at (\(Int(input.x)), \(Int(input.y)))")
      } catch {
        return .fail("Double-tap failed: \(error)")
      }
    }
  }

  static func longPress(_ args: [String: Value]?, wdaClient: WDAClient) async -> CallTool.Result {
    switch ToolInput.decode(LongPressInput.self, from: args) {
    case .failure(let err): return err
    case .success(let input):
      let durationMs = input.duration_ms ?? 1000
      do {
        try await wdaClient.longPress(x: input.x, y: input.y, durationMs: durationMs)
        return .ok("Long-pressed at (\(Int(input.x)), \(Int(input.y))) for \(durationMs)ms")
      } catch {
        return .fail("Long-press failed: \(error)")
      }
    }
  }

  static func swipeAction(_ args: [String: Value]?, wdaClient: WDAClient) async -> CallTool.Result {
    switch ToolInput.decode(SwipeInput.self, from: args) {
    case .failure(let err): return err
    case .success(let input):
      let durationMs = input.duration_ms ?? 300
      do {
        try await wdaClient.swipe(
          startX: input.start_x, startY: input.start_y, endX: input.end_x, endY: input.end_y,
          durationMs: durationMs)
        return .ok(
          "Swiped from (\(Int(input.start_x)),\(Int(input.start_y))) to (\(Int(input.end_x)),\(Int(input.end_y)))"
        )
      } catch {
        return .fail("Swipe failed: \(error)")
      }
    }
  }

  static func pinchAction(_ args: [String: Value]?, wdaClient: WDAClient) async -> CallTool.Result {
    switch ToolInput.decode(PinchInput.self, from: args) {
    case .failure(let err): return err
    case .success(let input):
      let durationMs = input.duration_ms ?? 500
      do {
        try await wdaClient.pinch(
          centerX: input.center_x, centerY: input.center_y, scale: input.scale,
          durationMs: durationMs)
        return .ok("Pinch at (\(Int(input.center_x)),\(Int(input.center_y))) scale=\(input.scale)")
      } catch {
        return .fail("Pinch failed: \(error)")
      }
    }
  }

  static func dragAndDrop(_ args: [String: Value]?, wdaClient: WDAClient) async -> CallTool.Result {
    switch ToolInput.decode(DragAndDropInput.self, from: args) {
    case .failure(let err): return err
    case .success(let input):
      let pressDurationMs = input.press_duration_ms ?? 1000
      let holdDurationMs = input.hold_duration_ms ?? 300

      let hasSource = input.source_element != nil || (input.from_x != nil && input.from_y != nil)
      let hasTarget = input.target_element != nil || (input.to_x != nil && input.to_y != nil)
      guard hasSource, hasTarget else {
        return .fail(
          "Need source (source_element OR from_x+from_y) and target (target_element OR to_x+to_y)")
      }

      do {
        let start = CFAbsoluteTimeGetCurrent()
        try await wdaClient.dragAndDrop(
          sourceElement: input.source_element, targetElement: input.target_element,
          fromX: input.from_x, fromY: input.from_y, toX: input.to_x, toY: input.to_y,
          pressDurationMs: pressDurationMs, holdDurationMs: holdDurationMs
        )
        let elapsed = String(format: "%.0f", (CFAbsoluteTimeGetCurrent() - start) * 1000)
        let srcDesc = input.source_element ?? "(\(Int(input.from_x!)),\(Int(input.from_y!)))"
        let tgtDesc = input.target_element ?? "(\(Int(input.to_x!)),\(Int(input.to_y!)))"
        return .ok("Dragged \(srcDesc) → \(tgtDesc) (\(elapsed)ms)")
      } catch {
        return .fail("Drag failed: \(error)")
      }
    }
  }

  static func typeText(_ args: [String: Value]?, wdaClient: WDAClient) async -> CallTool.Result {
    switch ToolInput.decode(TypeTextInput.self, from: args) {
    case .failure(let err): return err
    case .success(let input):
      let clearFirst = input.clear_first ?? false

      do {
        if let eid = input.element_id {
          if clearFirst {
            try await wdaClient.clearElement(elementId: eid)
          }
          try await wdaClient.setValue(elementId: eid, text: input.text)
        } else {
          // Find first text field and type into it
          _ = try await wdaClient.ensureSession()
          let (eid, _) = try await wdaClient.findElement(
            using: "class name", value: "XCUIElementTypeTextField")
          if clearFirst {
            try await wdaClient.clearElement(elementId: eid)
          }
          try await wdaClient.setValue(elementId: eid, text: input.text)
        }
        return .ok("Typed '\(input.text)'")
      } catch {
        return .fail("Type failed: \(error)")
      }
    }
  }

  static func getText(_ args: [String: Value]?, env: Environment) async -> CallTool.Result {
    switch ToolInput.decode(ElementInput.self, from: args) {
    case .failure(let err): return err
    case .success(let input):
      // AXP fast-path: try native getText, consume handle to prevent unbounded growth
      if let handle = axpHandles.removeValue(forKey: input.element_id) {
        let start = CFAbsoluteTimeGetCurrent()
        do {
          let text = try await env.axpBridge.getText(handle: handle)
          let elapsed = String(format: "%.0f", (CFAbsoluteTimeGetCurrent() - start) * 1000)
          return .ok("Text (axp, \(elapsed)ms): \(text)")
        } catch {
          Log.warn("AXPBridge getText failed, falling back to WDA: \(error)")
        }
      }

      // WDA path — element_id is always a real WDA handle
      do {
        let start = CFAbsoluteTimeGetCurrent()
        let text = try await env.wdaClient.getText(elementId: input.element_id)
        let elapsed = String(format: "%.0f", (CFAbsoluteTimeGetCurrent() - start) * 1000)
        return .ok("Text (wda, \(elapsed)ms): \(text)")
      } catch {
        return .fail("Get text failed: \(error)")
      }
    }
  }

  // MARK: - Clipboard Tools

  static func clipboardGet(_ args: [String: Value]?, wdaClient: WDAClient) async -> CallTool.Result {
    do {
      let text = try await wdaClient.getPasteboard()
      if text.isEmpty {
        return .ok("Clipboard is empty.")
      }
      return .ok("Clipboard content: \(text)")
    } catch {
      return .fail("Clipboard read failed: \(error)")
    }
  }

  static func clipboardSet(_ args: [String: Value]?, wdaClient: WDAClient) async -> CallTool.Result {
    switch ToolInput.decode(ClipboardSetInput.self, from: args) {
    case .failure(let err): return err
    case .success(let input):
      do {
        try await wdaClient.setPasteboard(input.text)
        return .ok("Copied to clipboard: \(input.text)")
      } catch {
        return .fail("Clipboard write failed: \(error)")
      }
    }
  }

  // MARK: - IndigoHID Tools

  static func indigoTap(_ args: [String: Value]?, wdaClient: WDAClient) async -> CallTool.Result {
    switch ToolInput.decode(IndigoTapInput.self, from: args) {
    case .failure(let err): return err
    case .success(let input):
      let simulator = input.simulator ?? "booted"

      if IndigoHIDClient.isAvailable {
        do {
          let start = CFAbsoluteTimeGetCurrent()
          try await IndigoHIDClient.shared.tap(x: input.x, y: input.y, simulator: simulator)
          let elapsed = String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - start) * 1000)
          return .ok("Tapped at (\(Int(input.x)), \(Int(input.y))) via IndigoHID (\(elapsed)ms)")
        } catch {
          Log.warn("IndigoHID tap failed, falling back to WDA: \(error)")
          await IndigoHIDClient.shared.invalidateCache()
        }
      }

      // WDA fallback
      do {
        let start = CFAbsoluteTimeGetCurrent()
        try await wdaClient.tap(x: input.x, y: input.y)
        let elapsed = String(format: "%.0f", (CFAbsoluteTimeGetCurrent() - start) * 1000)
        return .ok("Tapped at (\(Int(input.x)), \(Int(input.y))) via WDA fallback (\(elapsed)ms)")
      } catch {
        return .fail("Tap failed: \(error)")
      }
    }
  }

  static func indigoSwipe(_ args: [String: Value]?, wdaClient: WDAClient) async -> CallTool.Result {
    switch ToolInput.decode(SwipeInput.self, from: args) {
    case .failure(let err): return err
    case .success(let input):
      let durationMs = input.duration_ms ?? 300
      let simulator = input.simulator ?? "booted"

      if IndigoHIDClient.isAvailable {
        do {
          let start = CFAbsoluteTimeGetCurrent()
          try await IndigoHIDClient.shared.swipe(
            startX: input.start_x, startY: input.start_y, endX: input.end_x, endY: input.end_y,
            durationMs: durationMs, simulator: simulator
          )
          let elapsed = String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - start) * 1000)
          return .ok(
            "Swiped from (\(Int(input.start_x)),\(Int(input.start_y))) to (\(Int(input.end_x)),\(Int(input.end_y))) via IndigoHID (\(elapsed)ms)"
          )
        } catch {
          Log.warn("IndigoHID swipe failed, falling back to WDA: \(error)")
          await IndigoHIDClient.shared.invalidateCache()
        }
      }

      // WDA fallback
      do {
        try await wdaClient.swipe(
          startX: input.start_x, startY: input.start_y, endX: input.end_x, endY: input.end_y,
          durationMs: durationMs)
        return .ok(
          "Swiped from (\(Int(input.start_x)),\(Int(input.start_y))) to (\(Int(input.end_x)),\(Int(input.end_y))) via WDA fallback"
        )
      } catch {
        return .fail("Swipe failed: \(error)")
      }
    }
  }

  static func getSource(_ args: [String: Value]?, env: Environment) async -> CallTool.Result {
    switch ToolInput.decode(SourceInput.self, from: args) {
    case .failure(let err): return err
    case .success(let input):
      let format = input.format ?? "json"

      // AXPBridge fast-path for JSON format
      if format == "json", AXPBridge.isAvailable {
        let start = CFAbsoluteTimeGetCurrent()
        do {
          let source = try await env.axpBridge.getSourceJSON()
          let elapsed = String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - start) * 1000)
          let elementCount = source.components(separatedBy: "\"type\"").count - 1
          Task {
            guard let udid = await DeviceStateStore.currentUDID(session: env.session) else {
              return
            }
            await DeviceStateStore.shared.update(
              .screen(elementCount: max(elementCount, 1), summary: "json"), for: udid)
          }
          let truncated =
            source.count > 50000 ? String(source.prefix(50000)) + "\n... [truncated]" : source
          return .ok("View hierarchy (axp, \(elapsed)ms, \(source.count) chars):\n\(truncated)")
        } catch {
          Log.warn("AXPBridge getSourceJSON failed, falling back to WDA: \(error)")
        }
      }

      do {
        let start = CFAbsoluteTimeGetCurrent()
        let source = try await env.wdaClient.getSource(format: format)
        let elapsed = String(format: "%.1f", CFAbsoluteTimeGetCurrent() - start)
        // Cache screen info
        let elementCount = source.components(separatedBy: "\"type\"").count - 1
        Task {
          guard let udid = await DeviceStateStore.currentUDID(session: env.session) else { return }
          await DeviceStateStore.shared.update(
            .screen(elementCount: max(elementCount, 1), summary: format), for: udid)
        }
        // Truncate if too large
        let truncated =
          source.count > 50000 ? String(source.prefix(50000)) + "\n... [truncated]" : source
        return .ok("View hierarchy (wda, \(elapsed)s, \(source.count) chars):\n\(truncated)")
      } catch {
        return .fail("Get source failed: \(error)")
      }
    }
  }
}

// MARK: - Value helpers

extension Value {
  var numberValue: Double? {
    switch self {
    case .double(let n): return n
    case .int(let n): return Double(n)
    case .string(let s): return Double(s)
    default: return nil
    }
  }

  var intValue: Int? {
    numberValue.map(Int.init)
  }

  var boolValue: Bool? {
    switch self {
    case .bool(let b): return b
    case .string(let s): return s == "true" || s == "1"
    default: return nil
    }
  }
}

extension UITools: ToolProvider {
  public static func dispatch(_ name: String, _ args: [String: Value]?, env: Environment) async
    -> CallTool.Result?
  {
    switch name {
    case "handle_alert":
      return await handleAlert(args, session: env.session, wdaClient: env.wdaClient)
    case "wda_status": return await wdaStatus(args, session: env.session, wdaClient: env.wdaClient)
    case "wda_create_session": return await wdaCreateSession(args, wdaClient: env.wdaClient)
    case "find_element": return await findElement(args, env: env)
    case "find_elements": return await findElements(args, wdaClient: env.wdaClient)
    case "click_element": return await clickElement(args, env: env)
    case "tap_coordinates": return await tapCoordinates(args, wdaClient: env.wdaClient)
    case "double_tap": return await doubleTap(args, wdaClient: env.wdaClient)
    case "long_press": return await longPress(args, wdaClient: env.wdaClient)
    case "swipe": return await swipeAction(args, wdaClient: env.wdaClient)
    case "pinch": return await pinchAction(args, wdaClient: env.wdaClient)
    case "indigo_tap": return await indigoTap(args, wdaClient: env.wdaClient)
    case "indigo_swipe": return await indigoSwipe(args, wdaClient: env.wdaClient)
    case "drag_and_drop": return await dragAndDrop(args, wdaClient: env.wdaClient)
    case "type_text": return await typeText(args, wdaClient: env.wdaClient)
    case "get_text": return await getText(args, env: env)
    case "get_source": return await getSource(args, env: env)
    case "clipboard_get": return await clipboardGet(args, wdaClient: env.wdaClient)
    case "clipboard_set": return await clipboardSet(args, wdaClient: env.wdaClient)
    default: return nil
    }
  }
}

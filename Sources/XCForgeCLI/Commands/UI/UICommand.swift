import ArgumentParser
import Foundation
import XCForgeKit

struct UIResult: Codable {
    let succeeded: Bool
    let message: String
    let elementId: String?
    let elementCount: Int?
}

struct UI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ui",
        abstract: "UI automation via WebDriverAgent.",
        subcommands: [
            UIStatus.self, UISession.self,
            UIFind.self, UIFindAll.self,
            UIClick.self, UITap.self, UIDoubleTap.self, UILongPress.self,
            UISwipe.self, UIPinch.self, UIDrag.self,
            UIType.self, UIGetText.self,
            UISource.self, UIAlert.self,
        ],
        defaultSubcommand: UIStatus.self
    )
}

// MARK: - Status

struct UIStatus: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Check if WebDriverAgent is running and reachable."
    )

    @Flag(help: "Emit the result as machine-readable JSON.")
    var json = false

    mutating func run() throws {
        let json = self.json

        try runAsync {
            let env = Environment.live
            let healthy = await env.wdaClient.isHealthy()
            let backendName = await env.wdaClient.backend.displayName

            if healthy {
                do {
                    let status = try await env.wdaClient.status()
                    let sessionCount = await env.wdaClient.sessionCount
                    let message = "WDA Status: \(status.ready ? "READY" : "NOT READY")\nBackend: \(backendName)\nBundle: \(status.bundleId)\nSessions tracked: \(sessionCount)"

                    if json {
                        let result = UIResult(succeeded: true, message: message, elementId: nil, elementCount: nil)
                        print(try WorkflowJSONRenderer.renderJSON(result))
                    } else {
                        print(message)
                    }
                } catch {
                    let message = "WDA reachable but status parse failed: \(error)"
                    if json {
                        let result = UIResult(succeeded: true, message: message, elementId: nil, elementCount: nil)
                        print(try WorkflowJSONRenderer.renderJSON(result))
                    } else {
                        print(message)
                    }
                }
            } else {
                let message = "WDA not responding (health check timeout 2s). Backend: \(backendName). Try restarting WDA or the simulator."
                if json {
                    let result = UIResult(succeeded: false, message: message, elementId: nil, elementCount: nil)
                    print(try WorkflowJSONRenderer.renderJSON(result))
                } else {
                    print(message)
                }
                throw ExitCode.failure
            }
        }
    }
}

// MARK: - Session

struct UISession: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "session",
        abstract: "Create a new WDA session, optionally for a specific app."
    )

    @Option(help: "Bundle ID to activate.")
    var bundleId: String?

    @Option(help: "WDA base URL. Default: http://localhost:8100")
    var wdaUrl: String?

    @Flag(help: "Emit the result as machine-readable JSON.")
    var json = false

    mutating func run() throws {
        let bundleId = self.bundleId
        let wdaUrl = self.wdaUrl
        let json = self.json

        try runAsync {
            let env = Environment.live
            if let url = wdaUrl {
                let previousURL = await env.wdaClient.getBaseURL()
                await env.wdaClient.setBaseURL(url)

                do {
                    let sid = try await env.wdaClient.createSession(bundleId: bundleId)
                    let message = "Session created: \(sid) (custom WDA: \(url))"
                    if json {
                        print(try WorkflowJSONRenderer.renderJSON(UIResult(succeeded: true, message: message, elementId: nil, elementCount: nil)))
                    } else {
                        print(message)
                    }
                } catch {
                    await env.wdaClient.setBaseURL(previousURL)
                    let message = "Connection to \(url) failed: \(error). Default URL (\(previousURL)) restored."
                    if json {
                        print(try WorkflowJSONRenderer.renderJSON(UIResult(succeeded: false, message: message, elementId: nil, elementCount: nil)))
                    } else {
                        print(message)
                    }
                    throw ExitCode.failure
                }
            } else {
                do {
                    try await env.wdaClient.ensureWDARunning()
                    let sid = try await env.wdaClient.createSession(bundleId: bundleId)
                    let message = "Session created: \(sid)"
                    if json {
                        print(try WorkflowJSONRenderer.renderJSON(UIResult(succeeded: true, message: message, elementId: nil, elementCount: nil)))
                    } else {
                        print(message)
                    }
                } catch {
                    let message = "Session creation failed: \(error)"
                    if json {
                        print(try WorkflowJSONRenderer.renderJSON(UIResult(succeeded: false, message: message, elementId: nil, elementCount: nil)))
                    } else {
                        print(message)
                    }
                    throw ExitCode.failure
                }
            }
        }
    }
}

// MARK: - Find

struct UIFind: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "find",
        abstract: "Find a UI element. With --scroll, auto-scrolls until the element appears."
    )

    @Option(help: "Strategy: 'accessibility id', 'class name', 'predicate string', 'class chain'.")
    var using: String

    @Option(help: "Search value.")
    var value: String

    @Flag(help: "Auto-scroll to find off-screen elements.")
    var scroll = false

    @Option(help: "Scroll direction: auto, down, up, left, right. Default: auto.")
    var direction: String = "auto"

    @Option(help: "Max scroll attempts. Default: 10.")
    var maxSwipes: Int = 10

    @Flag(help: "Emit the result as machine-readable JSON.")
    var json = false

    mutating func run() throws {
        let using = self.using
        let value = self.value
        let scroll = self.scroll
        let direction = self.direction
        let maxSwipes = self.maxSwipes
        let json = self.json

        try runAsync {
            let env = Environment.live
            do {
                let start = CFAbsoluteTimeGetCurrent()
                let (elementId, swipes) = try await env.wdaClient.findElement(
                    using: using, value: value, scroll: scroll, direction: direction, maxSwipes: maxSwipes
                )
                let elapsed = String(format: "%.0f", (CFAbsoluteTimeGetCurrent() - start) * 1000)
                var message = "Element found: \(elementId) (\(elapsed)ms)"
                if swipes > 0 {
                    message += " — scrolled \(swipes) time(s) \(direction)"
                }
                if json {
                    print(try WorkflowJSONRenderer.renderJSON(UIResult(succeeded: true, message: message, elementId: elementId, elementCount: nil)))
                } else {
                    print(message)
                }
            } catch {
                let message = "Element not found: \(error)"
                if json {
                    print(try WorkflowJSONRenderer.renderJSON(UIResult(succeeded: false, message: message, elementId: nil, elementCount: nil)))
                } else {
                    print(message)
                }
                throw ExitCode.failure
            }
        }
    }
}

// MARK: - Find All

struct UIFindAll: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "find-all",
        abstract: "Find multiple UI elements matching a query."
    )

    @Option(help: "Strategy: 'accessibility id', 'class name', 'predicate string', 'class chain'.")
    var using: String

    @Option(help: "Search value.")
    var value: String

    @Flag(help: "Emit the result as machine-readable JSON.")
    var json = false

    mutating func run() throws {
        let using = self.using
        let value = self.value
        let json = self.json

        try runAsync {
            let env = Environment.live
            do {
                let start = CFAbsoluteTimeGetCurrent()
                let elements = try await env.wdaClient.findElements(using: using, value: value)
                let elapsed = String(format: "%.0f", (CFAbsoluteTimeGetCurrent() - start) * 1000)
                let message = "Found \(elements.count) elements (\(elapsed)ms):\n" + elements.enumerated().map { "  [\($0.offset)] \($0.element)" }.joined(separator: "\n")
                if json {
                    print(try WorkflowJSONRenderer.renderJSON(UIResult(succeeded: true, message: message, elementId: nil, elementCount: elements.count)))
                } else {
                    print(message)
                }
            } catch {
                let message = "Find elements failed: \(error)"
                if json {
                    print(try WorkflowJSONRenderer.renderJSON(UIResult(succeeded: false, message: message, elementId: nil, elementCount: nil)))
                } else {
                    print(message)
                }
                throw ExitCode.failure
            }
        }
    }
}

// MARK: - Click

struct UIClick: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "click",
        abstract: "Click/tap a UI element by its ID."
    )

    @Option(help: "Element ID from find.")
    var elementId: String

    @Flag(help: "Emit the result as machine-readable JSON.")
    var json = false

    mutating func run() throws {
        let elementId = self.elementId
        let json = self.json

        try runAsync {
            let env = Environment.live
            do {
                let start = CFAbsoluteTimeGetCurrent()
                try await env.wdaClient.click(elementId: elementId)
                let elapsed = String(format: "%.0f", (CFAbsoluteTimeGetCurrent() - start) * 1000)
                let message = "Clicked element \(elementId) (\(elapsed)ms)"
                if json {
                    print(try WorkflowJSONRenderer.renderJSON(UIResult(succeeded: true, message: message, elementId: elementId, elementCount: nil)))
                } else {
                    print(message)
                }
            } catch {
                let message = "Click failed: \(error)"
                if json {
                    print(try WorkflowJSONRenderer.renderJSON(UIResult(succeeded: false, message: message, elementId: nil, elementCount: nil)))
                } else {
                    print(message)
                }
                throw ExitCode.failure
            }
        }
    }
}

// MARK: - Tap

struct UITap: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tap",
        abstract: "Tap at specific x,y coordinates on screen."
    )

    @Option(help: "X coordinate.")
    var x: Double

    @Option(help: "Y coordinate.")
    var y: Double

    @Flag(help: "Emit the result as machine-readable JSON.")
    var json = false

    mutating func run() throws {
        let x = self.x
        let y = self.y
        let json = self.json

        try runAsync {
            let env = Environment.live
            do {
                let start = CFAbsoluteTimeGetCurrent()
                try await env.wdaClient.tap(x: x, y: y)
                let elapsed = String(format: "%.0f", (CFAbsoluteTimeGetCurrent() - start) * 1000)
                let message = "Tapped at (\(Int(x)), \(Int(y))) (\(elapsed)ms)"
                if json {
                    print(try WorkflowJSONRenderer.renderJSON(UIResult(succeeded: true, message: message, elementId: nil, elementCount: nil)))
                } else {
                    print(message)
                }
            } catch {
                let message = "Tap failed: \(error)"
                if json {
                    print(try WorkflowJSONRenderer.renderJSON(UIResult(succeeded: false, message: message, elementId: nil, elementCount: nil)))
                } else {
                    print(message)
                }
                throw ExitCode.failure
            }
        }
    }
}

// MARK: - Double Tap

struct UIDoubleTap: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "double-tap",
        abstract: "Double-tap at specific coordinates."
    )

    @Option(help: "X coordinate.")
    var x: Double

    @Option(help: "Y coordinate.")
    var y: Double

    @Flag(help: "Emit the result as machine-readable JSON.")
    var json = false

    mutating func run() throws {
        let x = self.x
        let y = self.y
        let json = self.json

        try runAsync {
            let env = Environment.live
            do {
                try await env.wdaClient.doubleTap(x: x, y: y)
                let message = "Double-tapped at (\(Int(x)), \(Int(y)))"
                if json {
                    print(try WorkflowJSONRenderer.renderJSON(UIResult(succeeded: true, message: message, elementId: nil, elementCount: nil)))
                } else {
                    print(message)
                }
            } catch {
                let message = "Double-tap failed: \(error)"
                if json {
                    print(try WorkflowJSONRenderer.renderJSON(UIResult(succeeded: false, message: message, elementId: nil, elementCount: nil)))
                } else {
                    print(message)
                }
                throw ExitCode.failure
            }
        }
    }
}

// MARK: - Long Press

struct UILongPress: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "long-press",
        abstract: "Long-press at specific coordinates."
    )

    @Option(help: "X coordinate.")
    var x: Double

    @Option(help: "Y coordinate.")
    var y: Double

    @Option(help: "Duration in milliseconds. Default: 1000.")
    var durationMs: Int = 1000

    @Flag(help: "Emit the result as machine-readable JSON.")
    var json = false

    mutating func run() throws {
        let x = self.x
        let y = self.y
        let durationMs = self.durationMs
        let json = self.json

        try runAsync {
            let env = Environment.live
            do {
                try await env.wdaClient.longPress(x: x, y: y, durationMs: durationMs)
                let message = "Long-pressed at (\(Int(x)), \(Int(y))) for \(durationMs)ms"
                if json {
                    print(try WorkflowJSONRenderer.renderJSON(UIResult(succeeded: true, message: message, elementId: nil, elementCount: nil)))
                } else {
                    print(message)
                }
            } catch {
                let message = "Long-press failed: \(error)"
                if json {
                    print(try WorkflowJSONRenderer.renderJSON(UIResult(succeeded: false, message: message, elementId: nil, elementCount: nil)))
                } else {
                    print(message)
                }
                throw ExitCode.failure
            }
        }
    }
}

// MARK: - Swipe

struct UISwipe: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swipe",
        abstract: "Swipe from one point to another."
    )

    @Option(help: "Start X coordinate.")
    var startX: Double

    @Option(help: "Start Y coordinate.")
    var startY: Double

    @Option(help: "End X coordinate.")
    var endX: Double

    @Option(help: "End Y coordinate.")
    var endY: Double

    @Option(help: "Swipe duration in milliseconds. Default: 300.")
    var durationMs: Int = 300

    @Flag(help: "Emit the result as machine-readable JSON.")
    var json = false

    mutating func run() throws {
        let startX = self.startX
        let startY = self.startY
        let endX = self.endX
        let endY = self.endY
        let durationMs = self.durationMs
        let json = self.json

        try runAsync {
            let env = Environment.live
            do {
                try await env.wdaClient.swipe(startX: startX, startY: startY, endX: endX, endY: endY, durationMs: durationMs)
                let message = "Swiped from (\(Int(startX)),\(Int(startY))) to (\(Int(endX)),\(Int(endY)))"
                if json {
                    print(try WorkflowJSONRenderer.renderJSON(UIResult(succeeded: true, message: message, elementId: nil, elementCount: nil)))
                } else {
                    print(message)
                }
            } catch {
                let message = "Swipe failed: \(error)"
                if json {
                    print(try WorkflowJSONRenderer.renderJSON(UIResult(succeeded: false, message: message, elementId: nil, elementCount: nil)))
                } else {
                    print(message)
                }
                throw ExitCode.failure
            }
        }
    }
}

// MARK: - Pinch

struct UIPinch: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pinch",
        abstract: "Pinch/zoom at a center point. scale > 1 = zoom in, scale < 1 = zoom out."
    )

    @Option(help: "Center X coordinate.")
    var centerX: Double

    @Option(help: "Center Y coordinate.")
    var centerY: Double

    @Option(help: "Scale factor. >1 = zoom in, <1 = zoom out.")
    var scale: Double

    @Option(help: "Duration in milliseconds. Default: 500.")
    var durationMs: Int = 500

    @Flag(help: "Emit the result as machine-readable JSON.")
    var json = false

    mutating func run() throws {
        let centerX = self.centerX
        let centerY = self.centerY
        let scale = self.scale
        let durationMs = self.durationMs
        let json = self.json

        try runAsync {
            let env = Environment.live
            do {
                try await env.wdaClient.pinch(centerX: centerX, centerY: centerY, scale: scale, durationMs: durationMs)
                let message = "Pinch at (\(Int(centerX)),\(Int(centerY))) scale=\(scale)"
                if json {
                    print(try WorkflowJSONRenderer.renderJSON(UIResult(succeeded: true, message: message, elementId: nil, elementCount: nil)))
                } else {
                    print(message)
                }
            } catch {
                let message = "Pinch failed: \(error)"
                if json {
                    print(try WorkflowJSONRenderer.renderJSON(UIResult(succeeded: false, message: message, elementId: nil, elementCount: nil)))
                } else {
                    print(message)
                }
                throw ExitCode.failure
            }
        }
    }
}

// MARK: - Drag

struct UIDrag: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "drag",
        abstract: "Drag from source to target. Works with element IDs, coordinates, or mixed."
    )

    @Option(help: "Source element ID from find.")
    var sourceElement: String?

    @Option(help: "Target element ID from find.")
    var targetElement: String?

    @Option(help: "Source X coordinate (alternative to --source-element).")
    var fromX: Double?

    @Option(help: "Source Y coordinate.")
    var fromY: Double?

    @Option(help: "Target X coordinate (alternative to --target-element).")
    var toX: Double?

    @Option(help: "Target Y coordinate.")
    var toY: Double?

    @Option(help: "Long-press duration to activate drag mode (ms). Default: 1000.")
    var pressDurationMs: Int = 1000

    @Option(help: "Hold at target before drop (ms). Default: 300.")
    var holdDurationMs: Int = 300

    @Flag(help: "Emit the result as machine-readable JSON.")
    var json = false

    mutating func run() throws {
        let sourceElement = self.sourceElement
        let targetElement = self.targetElement
        let fromX = self.fromX
        let fromY = self.fromY
        let toX = self.toX
        let toY = self.toY
        let pressDurationMs = self.pressDurationMs
        let holdDurationMs = self.holdDurationMs
        let json = self.json

        let hasSource = sourceElement != nil || (fromX != nil && fromY != nil)
        let hasTarget = targetElement != nil || (toX != nil && toY != nil)
        guard hasSource, hasTarget else {
            print("Need source (--source-element OR --from-x + --from-y) and target (--target-element OR --to-x + --to-y)")
            throw ExitCode.validationFailure
        }

        try runAsync {
            let env = Environment.live
            do {
                let start = CFAbsoluteTimeGetCurrent()
                try await env.wdaClient.dragAndDrop(
                    sourceElement: sourceElement, targetElement: targetElement,
                    fromX: fromX, fromY: fromY, toX: toX, toY: toY,
                    pressDurationMs: pressDurationMs, holdDurationMs: holdDurationMs
                )
                let elapsed = String(format: "%.0f", (CFAbsoluteTimeGetCurrent() - start) * 1000)
                let srcDesc = sourceElement ?? "(\(Int(fromX!)),\(Int(fromY!)))"
                let tgtDesc = targetElement ?? "(\(Int(toX!)),\(Int(toY!)))"
                let message = "Dragged \(srcDesc) → \(tgtDesc) (\(elapsed)ms)"
                if json {
                    print(try WorkflowJSONRenderer.renderJSON(UIResult(succeeded: true, message: message, elementId: nil, elementCount: nil)))
                } else {
                    print(message)
                }
            } catch {
                let message = "Drag failed: \(error)"
                if json {
                    print(try WorkflowJSONRenderer.renderJSON(UIResult(succeeded: false, message: message, elementId: nil, elementCount: nil)))
                } else {
                    print(message)
                }
                throw ExitCode.failure
            }
        }
    }
}

// MARK: - Type

struct UIType: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "type",
        abstract: "Type text into the currently focused element or a specified element."
    )

    @Option(help: "Text to type.")
    var text: String

    @Option(help: "Optional element ID to type into.")
    var elementId: String?

    @Flag(help: "Clear existing text first.")
    var clearFirst = false

    @Flag(help: "Emit the result as machine-readable JSON.")
    var json = false

    mutating func run() throws {
        let text = self.text
        let elementId = self.elementId
        let clearFirst = self.clearFirst
        let json = self.json

        try runAsync {
            let env = Environment.live
            do {
                if let eid = elementId {
                    if clearFirst {
                        try await env.wdaClient.clearElement(elementId: eid)
                    }
                    try await env.wdaClient.setValue(elementId: eid, text: text)
                } else {
                    _ = try await env.wdaClient.ensureSession()
                    let (eid, _) = try await env.wdaClient.findElement(using: "class name", value: "XCUIElementTypeTextField")
                    if clearFirst {
                        try await env.wdaClient.clearElement(elementId: eid)
                    }
                    try await env.wdaClient.setValue(elementId: eid, text: text)
                }
                let message = "Typed '\(text)'"
                if json {
                    print(try WorkflowJSONRenderer.renderJSON(UIResult(succeeded: true, message: message, elementId: elementId, elementCount: nil)))
                } else {
                    print(message)
                }
            } catch {
                let message = "Type failed: \(error)"
                if json {
                    print(try WorkflowJSONRenderer.renderJSON(UIResult(succeeded: false, message: message, elementId: nil, elementCount: nil)))
                } else {
                    print(message)
                }
                throw ExitCode.failure
            }
        }
    }
}

// MARK: - Get Text

struct UIGetText: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "get-text",
        abstract: "Get text content of a UI element."
    )

    @Option(help: "Element ID from find.")
    var elementId: String

    @Flag(help: "Emit the result as machine-readable JSON.")
    var json = false

    mutating func run() throws {
        let elementId = self.elementId
        let json = self.json

        try runAsync {
            let env = Environment.live
            do {
                let text = try await env.wdaClient.getText(elementId: elementId)
                let message = "Text: \(text)"
                if json {
                    print(try WorkflowJSONRenderer.renderJSON(UIResult(succeeded: true, message: message, elementId: elementId, elementCount: nil)))
                } else {
                    print(message)
                }
            } catch {
                let message = "Get text failed: \(error)"
                if json {
                    print(try WorkflowJSONRenderer.renderJSON(UIResult(succeeded: false, message: message, elementId: nil, elementCount: nil)))
                } else {
                    print(message)
                }
                throw ExitCode.failure
            }
        }
    }
}

// MARK: - Source

struct UISource: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "source",
        abstract: "Get the full view hierarchy (source tree) of the current screen."
    )

    @Option(help: "Format: json, xml, or description. Default: json.")
    var format: String = "json"

    @Flag(help: "Emit the result as machine-readable JSON.")
    var json = false

    mutating func run() throws {
        let format = self.format
        let json = self.json

        try runAsync {
            let env = Environment.live
            do {
                let start = CFAbsoluteTimeGetCurrent()
                let source = try await env.wdaClient.getSource(format: format)
                let elapsed = String(format: "%.1f", CFAbsoluteTimeGetCurrent() - start)
                let truncated = source.count > 50000 ? String(source.prefix(50000)) + "\n... [truncated]" : source
                let message = "View hierarchy (\(elapsed)s, \(source.count) chars):\n\(truncated)"
                if json {
                    print(try WorkflowJSONRenderer.renderJSON(UIResult(succeeded: true, message: message, elementId: nil, elementCount: nil)))
                } else {
                    print(message)
                }
            } catch {
                let message = "Get source failed: \(error)"
                if json {
                    print(try WorkflowJSONRenderer.renderJSON(UIResult(succeeded: false, message: message, elementId: nil, elementCount: nil)))
                } else {
                    print(message)
                }
                throw ExitCode.failure
            }
        }
    }
}

// MARK: - Alert

struct UIAlert: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "alert",
        abstract: "Handle iOS system alerts and in-app dialogs."
    )

    @Option(help: "Action: accept, dismiss, get_text, accept_all, dismiss_all.")
    var action: String

    @Option(help: "Specific button to tap (e.g. 'Allow While Using App'). If omitted, uses smart defaults.")
    var buttonLabel: String?

    @Flag(help: "Emit the result as machine-readable JSON.")
    var json = false

    mutating func run() throws {
        let action = self.action
        let buttonLabel = self.buttonLabel
        let json = self.json

        try runAsync {
            let env = Environment.live
            var message: String
            var succeeded = true

            switch action {
            case "get_text":
                guard let info = await env.wdaClient.getAlertText() else {
                    message = "No alert visible."
                    break
                }
                message = "Alert text: \(info.text)\nButtons: \(info.buttons.joined(separator: ", "))"

            case "accept":
                do {
                    let info = try await env.wdaClient.acceptAlert(buttonLabel: buttonLabel)
                    message = "Alert accepted."
                    if let info {
                        message += "\nAlert was: \(info.text)\nButtons were: \(info.buttons.joined(separator: ", "))"
                    }
                } catch {
                    message = "Accept alert failed: \(error)"
                    succeeded = false
                }

            case "dismiss":
                do {
                    let info = try await env.wdaClient.dismissAlert(buttonLabel: buttonLabel)
                    message = "Alert dismissed."
                    if let info {
                        message += "\nAlert was: \(info.text)\nButtons were: \(info.buttons.joined(separator: ", "))"
                    }
                } catch {
                    message = "Dismiss alert failed: \(error)"
                    succeeded = false
                }

            case "accept_all":
                do {
                    let result = try await env.wdaClient.handleAllAlerts(accept: true)
                    if result.count == 0 {
                        message = "No alerts visible."
                    } else {
                        message = "\(result.count) alert(s) accepted."
                        for (i, alert) in result.alerts.enumerated() {
                            message += "\n  [\(i + 1)] \(alert.text) → buttons: \(alert.buttons.joined(separator: ", ")) (source: \(alert.source))"
                        }
                    }
                } catch {
                    message = "Accept all alerts failed: \(error)"
                    succeeded = false
                }

            case "dismiss_all":
                do {
                    let result = try await env.wdaClient.handleAllAlerts(accept: false)
                    if result.count == 0 {
                        message = "No alerts visible."
                    } else {
                        message = "\(result.count) alert(s) dismissed."
                        for (i, alert) in result.alerts.enumerated() {
                            message += "\n  [\(i + 1)] \(alert.text) → buttons: \(alert.buttons.joined(separator: ", ")) (source: \(alert.source))"
                        }
                    }
                } catch {
                    message = "Dismiss all alerts failed: \(error)"
                    succeeded = false
                }

            default:
                message = "Unknown action: '\(action)'. Use 'accept', 'dismiss', 'get_text', 'accept_all', or 'dismiss_all'."
                succeeded = false
            }

            if json {
                print(try WorkflowJSONRenderer.renderJSON(UIResult(succeeded: succeeded, message: message, elementId: nil, elementCount: nil)))
            } else {
                print(message)
            }

            if !succeeded {
                throw ExitCode.failure
            }
        }
    }
}

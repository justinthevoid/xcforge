import AppKit
import ApplicationServices
import Foundation

/// Direct accessibility tree bridge for Simulator via macOS AXUIElement API.
/// Reads the Simulator.app's accessibility tree directly — no WDA HTTP overhead.
/// Used for `getSource(format: "json")` acceleration only. Element IDs from this
/// bridge are NOT compatible with WDA session handles, so `findElement` is not accelerated.
public actor AXPBridge {

    public init() {}

    /// Whether accessibility API access is available (AX trusted check, cached at startup).
    nonisolated static let isAvailable: Bool = {
        let trusted = AXIsProcessTrusted()
        if !trusted {
            Log.warn("AXPBridge unavailable — process not trusted for accessibility. getSource will use WDA.")
        }
        return trusted
    }()

    // MARK: - Cached State

    private var cachedElements: [AXElement] = []
    private var cachedUDID: String?
    private var cachedAt: CFAbsoluteTime = 0
    private let cacheMaxAge: TimeInterval = 0.5
    private let treeBuildTimeout: TimeInterval = 5.0
    private let actionTimeout: TimeInterval = 3.0

    // MARK: - Public API

    struct AXElement: @unchecked Sendable {
        let label: String?
        let identifier: String?
        let elementType: String?
        let value: String?
        let frame: CGRect
        let handle: AXUIElement
    }

    /// Get the full accessibility tree as JSON string.
    /// - Parameter udid: Optional simulator UDID to scope the cache. When multiple
    ///   simulators are booted, each UDID gets its own cached tree.
    func getSourceJSON(udid: String? = nil) async throws -> String {
        let elements = try await snapshotTree(udid: udid)
        let dicts: [[String: Any]] = elements.map { el in
            var d: [String: Any] = [:]
            if let label = el.label { d["label"] = label }
            if let id = el.identifier { d["identifier"] = id }
            if let type = el.elementType { d["type"] = type }
            if let val = el.value { d["value"] = val }
            d["frame"] = [
                "x": Int(el.frame.origin.x),
                "y": Int(el.frame.origin.y),
                "width": Int(el.frame.width),
                "height": Int(el.frame.height),
            ]
            return d
        }
        let data = try JSONSerialization.data(withJSONObject: dicts, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    /// Opaque handle returned by `findElement` — valid only until the cache is invalidated.
    struct AXPHandle: @unchecked Sendable {
        fileprivate let element: AXUIElement
    }

    /// Find an element by accessibility strategy. Supports "accessibility id" and "class name".
    /// Returns an opaque handle for use with `performClick` / `getText`.
    func findElement(strategy: String, value: String, udid: String? = nil) async throws -> AXPHandle {
        let elements = try await snapshotTree(udid: udid)
        let match: AXElement? = switch strategy {
        case "accessibility id":
            elements.first { $0.identifier == value }
        case "class name":
            elements.first { $0.elementType == value }
        default:
            nil
        }
        guard let found = match else {
            throw AXPError.elementNotFound(strategy: strategy, value: value)
        }
        return AXPHandle(element: found.handle)
    }

    /// Click an element via its native accessibility action.
    /// Invalidates the tree cache only on success since the UI may change after interaction.
    func performClick(handle: AXPHandle) async throws {
        let timeout = actionTimeout
        try await runOffActor(timeout: timeout, timeoutError: { .actionFailed("AXPress timed out after \(Int(timeout))s") }) {
            let result = AXUIElementPerformAction(handle.element, kAXPressAction as CFString)
            guard result == .success else {
                throw AXPError.actionFailed("AXPress returned \(result.rawValue)")
            }
        }
        invalidateCache()
    }

    /// Read the text content of an element. Tries kAXValueAttribute first, then kAXTitleAttribute.
    func getText(handle: AXPHandle) async throws -> String {
        let timeout = actionTimeout
        return try await runOffActor(timeout: timeout, timeoutError: { .actionFailed("getText timed out after \(Int(timeout))s") }) {
            func stringAttr(_ attr: String) -> String? {
                var ref: CFTypeRef?
                guard AXUIElementCopyAttributeValue(handle.element, attr as CFString, &ref) == .success
                else { return nil }
                return ref as? String
            }
            if let text = stringAttr(kAXValueAttribute) { return text }
            if let text = stringAttr(kAXTitleAttribute) { return text }
            throw AXPError.actionFailed("No text content on element")
        }
    }

    /// Clear cached tree and handles. Called automatically after successful mutations.
    func invalidateCache() {
        cachedElements = []
        cachedUDID = nil
        cachedAt = 0
    }

    // MARK: - Tree Snapshot

    private func snapshotTree(udid: String? = nil) async throws -> [AXElement] {
        let simPID = try findSimulatorPID()
        let cacheKey = udid ?? "pid-\(simPID)"

        let now = CFAbsoluteTimeGetCurrent()
        if cacheKey == cachedUDID, now - cachedAt < cacheMaxAge, !cachedElements.isEmpty {
            return cachedElements
        }

        let timeout = treeBuildTimeout
        let elements: [AXElement] = try await runOffActor(timeout: timeout, timeoutError: { .treeBuildFailed("Tree traversal timed out after \(Int(timeout))s") }) {
            try Self.verifyBootedDevice()
            return try Self.buildTree(pid: simPID)
        }

        cachedElements = elements
        cachedUDID = cacheKey
        cachedAt = CFAbsoluteTimeGetCurrent()
        return elements
    }

    // MARK: - Off-Actor Dispatch

    /// Run a blocking closure on `DispatchQueue.global`, racing against a timeout.
    /// Prevents synchronous AX calls from starving the actor's serial executor.
    private nonisolated func runOffActor<T: Sendable>(
        timeout: TimeInterval,
        timeoutError: @Sendable @escaping () -> AXPError,
        _ body: @escaping @Sendable () throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
                    DispatchQueue.global(qos: .userInteractive).async {
                        do {
                            let result = try body()
                            continuation.resume(returning: result)
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw timeoutError()
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    // MARK: - AXUIElement Tree Traversal

    private static func buildTree(pid: pid_t) throws -> [AXElement] {
        let app = AXUIElementCreateApplication(pid)
        var elements: [AXElement] = []
        traverse(element: app, into: &elements, depth: 0, maxDepth: 40, maxElements: 5000)
        return elements
    }

    private static func traverse(
        element: AXUIElement, into elements: inout [AXElement],
        depth: Int, maxDepth: Int, maxElements: Int = 5000
    ) {
        guard elements.count < maxElements else { return }
        guard depth < maxDepth else { return }

        let axElement = extractElement(from: element)
        if axElement.identifier != nil || axElement.label != nil {
            elements.append(axElement)
        }

        var childrenRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element, kAXChildrenAttribute as CFString, &childrenRef)
        guard result == .success, let children = childrenRef as? [AXUIElement] else {
            return
        }

        for child in children {
            traverse(element: child, into: &elements, depth: depth + 1, maxDepth: maxDepth, maxElements: maxElements)
        }
    }

    private static func extractElement(from ref: AXUIElement) -> AXElement {
        func stringAttr(_ attr: String) -> String? {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(ref, attr as CFString, &value) == .success
            else { return nil }
            return value as? String
        }

        var frame = CGRect.zero
        if let pos = axValuePoint(ref, kAXPositionAttribute),
           let size = axValueSize(ref, kAXSizeAttribute)
        {
            frame = CGRect(origin: pos, size: size)
        }

        return AXElement(
            label: stringAttr(kAXTitleAttribute),
            identifier: stringAttr("AXIdentifier"),
            elementType: stringAttr(kAXRoleAttribute),
            value: stringAttr(kAXValueAttribute),
            frame: frame,
            handle: ref
        )
    }

    // MARK: - AXValue Helpers

    private static func axValuePoint(_ ref: AXUIElement, _ attr: String) -> CGPoint? {
        var valRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(ref, attr as CFString, &valRef) == .success,
              let val = valRef, CFGetTypeID(val) == AXValueGetTypeID()
        else { return nil }
        var point = CGPoint.zero
        // CFGetTypeID check above guarantees this is an AXValue
        AXValueGetValue(val as! AXValue, .cgPoint, &point)
        return point
    }

    private static func axValueSize(_ ref: AXUIElement, _ attr: String) -> CGSize? {
        var valRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(ref, attr as CFString, &valRef) == .success,
              let val = valRef, CFGetTypeID(val) == AXValueGetTypeID()
        else { return nil }
        var size = CGSize.zero
        AXValueGetValue(val as! AXValue, .cgSize, &size)
        return size
    }

    // MARK: - Simulator PID Discovery

    /// Synchronously checks that at least one simulator device is booted.
    private static func verifyBootedDevice() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "list", "devices", "booted", "-j"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let devices = json["devices"] as? [String: [[String: Any]]]
        else {
            throw AXPError.noBootedDevice
        }

        let hasBooted = devices.values.contains { runtimes in
            runtimes.contains { ($0["state"] as? String) == "Booted" }
        }
        guard hasBooted else {
            throw AXPError.noBootedDevice
        }
    }

    private func findSimulatorPID() throws -> pid_t {
        let ws = NSWorkspace.shared
        guard
            let app = ws.runningApplications.first(where: {
                $0.bundleIdentifier == "com.apple.iphonesimulator"
            })
        else {
            throw AXPError.simulatorNotRunning
        }
        return app.processIdentifier
    }

    // MARK: - Errors

    enum AXPError: Error, CustomStringConvertible {
        case simulatorNotRunning
        case noBootedDevice
        case treeBuildFailed(String)
        case elementNotFound(strategy: String, value: String)
        case actionFailed(String)

        var description: String {
            switch self {
            case .simulatorNotRunning:
                return "Simulator.app not running"
            case .noBootedDevice:
                return "Simulator.app is running but no device is booted. Boot a device with: xcrun simctl boot <UDID>"
            case .treeBuildFailed(let msg):
                return "AXP tree build failed: \(msg)"
            case .elementNotFound(let strategy, let value):
                return "AXP element not found: \(strategy) = '\(value)'"
            case .actionFailed(let msg):
                return "AXP action failed: \(msg)"
            }
        }
    }
}

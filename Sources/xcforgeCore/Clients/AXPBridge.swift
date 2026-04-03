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

    // MARK: - Public API

    struct AXElement {
        let label: String?
        let identifier: String?
        let elementType: String?
        let value: String?
        let frame: CGRect
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

    // MARK: - Tree Snapshot

    private func snapshotTree(udid: String? = nil) async throws -> [AXElement] {
        let simPID = try findSimulatorPID()
        let cacheKey = udid ?? "pid-\(simPID)"

        let now = CFAbsoluteTimeGetCurrent()
        if cacheKey == cachedUDID, now - cachedAt < cacheMaxAge, !cachedElements.isEmpty {
            return cachedElements
        }

        // Build tree on a non-cooperative thread (AX calls can block), with timeout
        let elements = try await withThrowingTaskGroup(of: [AXElement].self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation {
                    (continuation: CheckedContinuation<[AXElement], Error>) in
                    DispatchQueue.global(qos: .userInteractive).async {
                        do {
                            try Self.verifyBootedDevice()
                            let tree = try Self.buildTree(pid: simPID)
                            continuation.resume(returning: tree)
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                }
            }
            group.addTask { [treeBuildTimeout] in
                try await Task.sleep(nanoseconds: UInt64(treeBuildTimeout * 1_000_000_000))
                throw AXPError.treeBuildFailed("Tree traversal timed out after \(Int(treeBuildTimeout))s")
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }

        cachedElements = elements
        cachedUDID = cacheKey
        cachedAt = CFAbsoluteTimeGetCurrent()
        return elements
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
            frame: frame
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

        var description: String {
            switch self {
            case .simulatorNotRunning:
                return "Simulator.app not running"
            case .noBootedDevice:
                return "Simulator.app is running but no device is booted. Boot a device with: xcrun simctl boot <UDID>"
            case .treeBuildFailed(let msg):
                return "AXP tree build failed: \(msg)"
            }
        }
    }
}

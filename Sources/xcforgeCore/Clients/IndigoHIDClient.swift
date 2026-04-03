import Foundation

/// Direct HID input bridge for iOS Simulator via Mach IPC.
/// Sends touch events to the simulator's IndigoHID service port,
/// bypassing WDA HTTP overhead for sub-5ms gesture delivery.
/// Single-touch only — multi-touch (pinch) is not supported.
actor IndigoHIDClient {

    static let shared = IndigoHIDClient()

    /// Whether the required frameworks can be loaded.
    nonisolated static let isAvailable: Bool = {
        guard simKitHandle != nil else {
            Log.warn("IndigoHIDClient unavailable — SimulatorKit.framework not found.")
            return false
        }
        return true
    }()

    // MARK: - Framework Loading

    private static let developerDir: String = {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        process.arguments = ["-p"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            if let path = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
                return path
            }
        } catch {}
        return "/Applications/Xcode.app/Contents/Developer"
    }()

    nonisolated(unsafe) private static let simKitHandle: UnsafeMutableRawPointer? = {
        dlopen("\(developerDir)/Library/PrivateFrameworks/SimulatorKit.framework/SimulatorKit", RTLD_NOW)
    }()

    // MARK: - Cached State

    /// Cached Mach port for the simulator's HID service.
    private var cachedPort: mach_port_t = mach_port_t(MACH_PORT_NULL)
    private var cachedUDID: String?

    /// Serialization flag to prevent gesture interleaving from concurrent callers.
    private var gestureInProgress = false

    /// Cached screen dimensions (points) for coordinate normalization.
    private var cachedScreenWidth: Double = 0
    private var cachedScreenHeight: Double = 0
    private var cachedScreenScale: Double = 0

    // MARK: - Public API

    /// Tap at point coordinates (in points, same coordinate space as WDA).
    func tap(x: Double, y: Double, simulator: String = "booted") async throws {
        let port = try await resolvePort(simulator: simulator)
        let (xRatio, yRatio) = try normalizeCoordinates(x: x, y: y)

        try await sendOnHIDQueue {
            try Self.sendTouch(port: port, xRatio: xRatio, yRatio: yRatio, direction: .down)
        }
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms hold
        try await sendOnHIDQueue {
            try Self.sendTouch(port: port, xRatio: xRatio, yRatio: yRatio, direction: .up)
        }
    }

    /// Double-tap at point coordinates.
    func doubleTap(x: Double, y: Double, simulator: String = "booted") async throws {
        while gestureInProgress { try await Task.sleep(nanoseconds: 1_000_000) }
        gestureInProgress = true
        defer { gestureInProgress = false }

        let port = try await resolvePort(simulator: simulator)
        let (xRatio, yRatio) = try normalizeCoordinates(x: x, y: y)

        // First tap
        try await sendOnHIDQueue {
            try Self.sendTouch(port: port, xRatio: xRatio, yRatio: yRatio, direction: .down)
        }
        try await Task.sleep(nanoseconds: 30_000_000) // 30ms hold
        try await sendOnHIDQueue {
            try Self.sendTouch(port: port, xRatio: xRatio, yRatio: yRatio, direction: .up)
        }

        try await Task.sleep(nanoseconds: 50_000_000) // 50ms gap

        // Second tap
        try await sendOnHIDQueue {
            try Self.sendTouch(port: port, xRatio: xRatio, yRatio: yRatio, direction: .down)
        }
        try await Task.sleep(nanoseconds: 30_000_000) // 30ms hold
        try await sendOnHIDQueue {
            try Self.sendTouch(port: port, xRatio: xRatio, yRatio: yRatio, direction: .up)
        }
    }

    /// Long press at point coordinates.
    func longPress(x: Double, y: Double, durationMs: Int = 1000, simulator: String = "booted") async throws {
        let port = try await resolvePort(simulator: simulator)
        let (xRatio, yRatio) = try normalizeCoordinates(x: x, y: y)

        try await sendOnHIDQueue {
            try Self.sendTouch(port: port, xRatio: xRatio, yRatio: yRatio, direction: .down)
        }
        let clampedDuration = max(0, durationMs)
        try await Task.sleep(nanoseconds: UInt64(clampedDuration) * 1_000_000)
        try await sendOnHIDQueue {
            try Self.sendTouch(port: port, xRatio: xRatio, yRatio: yRatio, direction: .up)
        }
    }

    /// Swipe from one point to another with decomposed move steps.
    func swipe(
        startX: Double, startY: Double,
        endX: Double, endY: Double,
        durationMs: Int = 300,
        simulator: String = "booted"
    ) async throws {
        while gestureInProgress { try await Task.sleep(nanoseconds: 1_000_000) }
        gestureInProgress = true
        defer { gestureInProgress = false }

        let port = try await resolvePort(simulator: simulator)
        let (sxR, syR) = try normalizeCoordinates(x: startX, y: startY)
        let (exR, eyR) = try normalizeCoordinates(x: endX, y: endY)

        // Calculate steps (~10px per step in point space)
        let dx = endX - startX
        let dy = endY - startY
        let distance = sqrt(dx * dx + dy * dy)
        let stepCount = max(1, Int(distance / 10.0))
        let clampedDuration = max(0, durationMs)
        let stepDelayNs = UInt64(Double(clampedDuration) * 1_000_000 / Double(stepCount + 2))

        // Touch down at start
        try await sendOnHIDQueue {
            try Self.sendTouch(port: port, xRatio: sxR, yRatio: syR, direction: .down)
        }
        try await Task.sleep(nanoseconds: stepDelayNs)

        // Move steps
        for i in 1...stepCount {
            let t = Float(i) / Float(stepCount)
            let mx = sxR + (exR - sxR) * t
            let my = syR + (eyR - syR) * t
            try await sendOnHIDQueue {
                try Self.sendTouch(port: port, xRatio: mx, yRatio: my, direction: .down)
            }
            try await Task.sleep(nanoseconds: stepDelayNs)
        }

        // Touch up at end
        try await sendOnHIDQueue {
            try Self.sendTouch(port: port, xRatio: exR, yRatio: eyR, direction: .up)
        }
    }

    /// Invalidate cached port (call after simulator reboot or when operations fail).
    func invalidateCache() {
        cachedPort = mach_port_t(MACH_PORT_NULL)
        cachedUDID = nil
        cachedScreenWidth = 0
        cachedScreenHeight = 0
        cachedScreenScale = 0
    }

    // MARK: - Port Resolution

    private func resolvePort(simulator: String) async throws -> mach_port_t {
        let udid = try await resolveUDID(simulator: simulator)

        if udid == cachedUDID, cachedPort != mach_port_t(MACH_PORT_NULL) {
            return cachedPort
        }

        // Clear screen info when switching devices so fetchScreenInfo re-resolves
        if udid != cachedUDID {
            cachedScreenWidth = 0
            cachedScreenHeight = 0
            cachedScreenScale = 0
        }

        let port = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<mach_port_t, Error>) in
            DispatchQueue.global(qos: .userInteractive).async {
                do {
                    let p = try Self.lookupHIDPort(udid: udid)
                    continuation.resume(returning: p)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        cachedPort = port
        cachedUDID = udid

        // Fetch screen info for coordinate normalization
        try await fetchScreenInfo(udid: udid)

        return port
    }

    /// Resolve "booted" or UDID to a concrete UDID.
    private func resolveUDID(simulator: String) async throws -> String {
        if simulator != "booted" { return simulator }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            DispatchQueue.global(qos: .userInteractive).async {
                do {
                    let udid = try Self.findBootedUDID()
                    continuation.resume(returning: udid)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Screen Info

    /// Fetch screen dimensions from `simctl list devices -j`, then try dynamic devicetype lookup,
    /// falling back to the hardcoded table if the dynamic query fails.
    private func fetchScreenInfo(udid: String) async throws {
        if cachedScreenWidth > 0, cachedScreenScale > 0 { return }

        // Get device type from simctl, then look up screen dimensions
        let result = try await Shell.xcrun(timeout: 5, "simctl", "list", "devices", "-j")
        guard let data = result.stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let runtimes = json["devices"] as? [String: [[String: Any]]] else {
            throw IndigoHIDError.screenInfoUnavailable
        }

        for (_, devices) in runtimes {
            for device in devices {
                guard let devUDID = device["udid"] as? String, devUDID == udid,
                      let deviceTypeId = device["deviceTypeIdentifier"] as? String else { continue }

                // Try dynamic lookup first, fall back to hardcoded table
                if let dynamic = try? await Self.dynamicScreenDimensions(for: deviceTypeId) {
                    cachedScreenWidth = dynamic.width
                    cachedScreenHeight = dynamic.height
                    cachedScreenScale = dynamic.scale
                } else {
                    let dims = Self.screenDimensions(for: deviceTypeId)
                    Log.warn("IndigoHID: dynamic screen lookup failed for \(deviceTypeId), using hardcoded fallback")
                    cachedScreenWidth = dims.width
                    cachedScreenHeight = dims.height
                    cachedScreenScale = dims.scale
                }
                return
            }
        }

        throw IndigoHIDError.screenInfoUnavailable
    }

    /// Known screen dimensions for common device types.
    /// IndigoHID needs (point * scale) / (screenPoints * scale) = point / screenPoints.
    static func screenDimensions(for deviceType: String) -> (width: Double, height: Double, scale: Double) {
        // Extract model from identifier like "com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro"
        let model = deviceType.replacingOccurrences(of: "com.apple.CoreSimulator.SimDeviceType.", with: "")

        switch model {
        // iPhone SE (3rd gen)
        case let m where m.contains("iPhone-SE"):
            return (375, 667, 2.0)
        // iPhone 14/15/16 standard
        case let m where m.contains("iPhone-14") && !m.contains("Pro") && !m.contains("Plus"),
             let m where m.contains("iPhone-15") && !m.contains("Pro") && !m.contains("Plus"),
             let m where m.contains("iPhone-16") && !m.contains("Pro") && !m.contains("Plus"):
            return (390, 844, 3.0)
        // iPhone 14/15/16 Pro
        case let m where m.contains("iPhone-14-Pro") && !m.contains("Max"),
             let m where m.contains("iPhone-15-Pro") && !m.contains("Max"),
             let m where m.contains("iPhone-16-Pro") && !m.contains("Max"):
            return (393, 852, 3.0)
        // iPhone Pro Max / Plus
        case let m where m.contains("Pro-Max") || m.contains("Plus"):
            return (430, 932, 3.0)
        // iPad standard
        case let m where m.contains("iPad") && !m.contains("Pro") && !m.contains("Air"):
            return (810, 1080, 2.0)
        // iPad Air / Pro 11"
        case let m where m.contains("iPad-Air") || (m.contains("iPad-Pro") && m.contains("11")):
            return (820, 1180, 2.0)
        // iPad Pro 12.9" / 13"
        case let m where m.contains("iPad-Pro") && (m.contains("12") || m.contains("13")):
            return (1024, 1366, 2.0)
        // Fallback: iPhone 16 Pro dimensions
        default:
            return (393, 852, 3.0)
        }
    }

    /// Query simctl for device type screen dimensions at runtime.
    /// Returns nil if the query fails or the device type is not found.
    static func dynamicScreenDimensions(for deviceType: String) async throws -> (width: Double, height: Double, scale: Double) {
        let result = try await Shell.xcrun(timeout: 5, "simctl", "list", "devicetypes", "-j")
        guard let data = result.stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let deviceTypes = json["devicetypes"] as? [[String: Any]] else {
            throw IndigoHIDError.screenInfoUnavailable
        }

        for dt in deviceTypes {
            guard let identifier = dt["identifier"] as? String,
                  identifier == deviceType else { continue }
            // simctl exposes minRuntimeVersionString but screen dimensions may be in
            // the productFamily or derived from the identifier. Newer Xcode versions
            // include mainScreenWidth/mainScreenHeight/mainScreenScale directly.
            if let width = dt["mainScreenWidth"] as? Double,
               let height = dt["mainScreenHeight"] as? Double,
               let scale = dt["mainScreenScale"] as? Double,
               width > 0, height > 0, scale > 0 {
                return (width, height, scale)
            }
        }

        throw IndigoHIDError.screenInfoUnavailable
    }

    // MARK: - Coordinate Normalization

    private func normalizeCoordinates(x: Double, y: Double) throws -> (Float, Float) {
        guard cachedScreenWidth > 0, cachedScreenHeight > 0 else {
            throw IndigoHIDError.screenInfoUnavailable
        }
        let xRatio = Float(x / cachedScreenWidth)
        let yRatio = Float(y / cachedScreenHeight)
        return (min(max(xRatio, 0), 1), min(max(yRatio, 0), 1))
    }

    // MARK: - Mach IPC

    /// IndigoHID message structure for touch events.
    /// Based on FBSimulatorControl reverse engineering of the Indigo protocol.
    private struct IndigoMessage {
        var header: mach_msg_header_t
        var innerSize: UInt32
        var eventType: UInt32
        var field1: UInt32
        var padding1: UInt32
        var timestamp: UInt64
        var xRatio: Float
        var yRatio: Float
        var touchField1: UInt32  // 0x00000001
        var touchField2: UInt32  // 0x00000002
        // Remaining padding to fill out the ~320 byte message
        var padding: (UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64,
                      UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64,
                      UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64,
                      UInt64, UInt64, UInt64, UInt64, UInt64)

        static let messageSize: mach_msg_size_t = mach_msg_size_t(MemoryLayout<IndigoMessage>.size)
    }

    private enum TouchDirection: UInt32 {
        case down = 1
        case up = 2
    }

    /// Build and send an IndigoHID touch message via Mach IPC.
    private static func sendTouch(port: mach_port_t, xRatio: Float, yRatio: Float, direction: TouchDirection) throws {
        var msg = IndigoMessage(
            header: mach_msg_header_t(
                msgh_bits: UInt32(MACH_MSG_TYPE_COPY_SEND),
                msgh_size: IndigoMessage.messageSize,
                msgh_remote_port: port,
                msgh_local_port: mach_port_t(MACH_PORT_NULL),
                msgh_voucher_port: mach_port_t(MACH_PORT_NULL),
                msgh_id: 0
            ),
            innerSize: 0x90,
            eventType: 2, // touch
            field1: 0x0000000b,
            padding1: 0,
            timestamp: mach_absolute_time(),
            xRatio: xRatio,
            yRatio: yRatio,
            touchField1: direction.rawValue,
            touchField2: 0x00000002,
            padding: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        )

        let result = withUnsafeMutablePointer(to: &msg) { ptr in
            ptr.withMemoryRebound(to: mach_msg_header_t.self, capacity: 1) { headerPtr in
                mach_msg(
                    headerPtr,
                    Int32(MACH_SEND_MSG) | Int32(MACH_SEND_TIMEOUT),
                    IndigoMessage.messageSize,
                    0,
                    mach_port_t(MACH_PORT_NULL),
                    5000,
                    mach_port_t(MACH_PORT_NULL)
                )
            }
        }

        guard result == MACH_MSG_SUCCESS else {
            if result == MACH_SEND_TIMED_OUT {
                throw IndigoHIDError.sendTimedOut
            }
            throw IndigoHIDError.machSendFailed(result)
        }
    }

    /// Look up the simulator's HID Mach port via CoreSimulator.
    private static func lookupHIDPort(udid: String) throws -> mach_port_t {
        // Use SimServiceContext to find the device, then get its IndigoHID port
        guard let ctxClass = NSClassFromString("SimServiceContext") as? NSObject.Type else {
            throw IndigoHIDError.frameworkNotFound
        }

        let devDir = developerDir as NSString
        var error: NSError?
        let ctx: NSObject? = withUnsafeMutablePointer(to: &error) { errPtr in
            let result = (ctxClass as AnyObject).perform(
                Selector(("sharedServiceContextForDeveloperDir:error:")), with: devDir, with: errPtr)
            return result?.takeUnretainedValue() as? NSObject
        }

        guard let serviceContext = ctx else {
            throw IndigoHIDError.portLookupFailed("SimServiceContext creation failed: \(error?.localizedDescription ?? "unknown")")
        }

        var devSetError: NSError?
        let deviceSet: NSObject? = withUnsafeMutablePointer(to: &devSetError) { errPtr in
            let result = serviceContext.perform(Selector(("defaultDeviceSetWithError:")), with: errPtr)
            return result?.takeUnretainedValue() as? NSObject
        }

        guard let devSet = deviceSet,
              let devices = devSet.perform(Selector(("devices")))?.takeUnretainedValue() as? [NSObject] else {
            throw IndigoHIDError.portLookupFailed("Cannot enumerate devices")
        }

        for device in devices {
            guard let devUDID = device.perform(Selector(("UDID")))?.takeUnretainedValue() as? NSUUID,
                  devUDID.uuidString == udid else { continue }

            // Get the device's HID port via lookup: service
            var lookupError: NSError?
            let portObj: NSObject? = withUnsafeMutablePointer(to: &lookupError) { errPtr in
                let result = device.perform(
                    Selector(("lookup:error:")),
                    with: "PurpleWorkspacePort" as NSString,
                    with: errPtr
                )
                return result?.takeUnretainedValue() as? NSObject
            }

            if let portObj = portObj {
                // The result should be an NSMachPort or similar — extract the port number
                if let machPort = portObj as? NSMachPort {
                    let port = machPort.machPort
                    if port != mach_port_t(MACH_PORT_NULL) {
                        return port
                    }
                }
                // Try extracting as NSNumber
                if let num = portObj as? NSNumber {
                    let port = mach_port_t(num.uint32Value)
                    if port != mach_port_t(MACH_PORT_NULL) {
                        return port
                    }
                }
            }

            throw IndigoHIDError.portLookupFailed(
                "PurpleWorkspacePort lookup failed for \(udid): \(lookupError?.localizedDescription ?? "port object not usable")"
            )
        }

        throw IndigoHIDError.noBootedSimulator
    }

    /// Find the UDID of the first booted simulator.
    private static func findBootedUDID() throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "list", "devices", "booted", "-j"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let runtimes = json["devices"] as? [String: [[String: Any]]] else {
            throw IndigoHIDError.noBootedSimulator
        }

        for (_, devices) in runtimes {
            for device in devices {
                if let state = device["state"] as? String, state == "Booted",
                   let udid = device["udid"] as? String {
                    return udid
                }
            }
        }

        throw IndigoHIDError.noBootedSimulator
    }

    // MARK: - Async Dispatch

    /// Run blocking HID operations on a dedicated POSIX thread, not the cooperative pool.
    private func sendOnHIDQueue(_ work: @escaping @Sendable () throws -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInteractive).async {
                do {
                    try work()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Errors

    enum IndigoHIDError: Error, CustomStringConvertible {
        case frameworkNotFound
        case noBootedSimulator
        case portLookupFailed(String)
        case machSendFailed(kern_return_t)
        case sendTimedOut
        case screenInfoUnavailable

        var description: String {
            switch self {
            case .frameworkNotFound:
                return "SimulatorKit.framework not found — Xcode not installed?"
            case .noBootedSimulator:
                return "No booted simulator found"
            case .portLookupFailed(let msg):
                return "IndigoHID port lookup failed: \(msg)"
            case .machSendFailed(let code):
                return "Mach message send failed: \(code)"
            case .sendTimedOut:
                return "Mach message send timed out (5s)"
            case .screenInfoUnavailable:
                return "Cannot determine screen dimensions for coordinate normalization"
            }
        }
    }
}

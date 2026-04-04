import Foundation

// MARK: - Time formatting

enum ElapsedTime {
    static func format(since timestamp: ContinuousClock.Instant?) -> String? {
        guard let ts = timestamp else { return nil }
        let seconds = Int((ContinuousClock.now - ts).components.seconds)
        if seconds < 60 { return "\(seconds)s ago" }
        let m = seconds / 60
        if m < 60 { return "\(m)m ago" }
        return "\(m / 60)h \(m % 60)m ago"
    }

    static func uptime(from iso8601: String?) -> String? {
        guard let str = iso8601 else { return nil }
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let boot = fmt.date(from: str) else { return nil }
        let s = Int(Date().timeIntervalSince(boot))
        if s < 60 { return "\(s)s" }
        let m = s / 60
        if m < 60 { return "\(m)m" }
        return "\(m / 60)h \(m % 60)m"
    }
}

// MARK: - Snapshot

/// Point-in-time snapshot of a single simulator's observable state.
public struct DeviceSnapshot: Sendable {
    public var state: String?
    public var name: String?
    public var runtime: String?
    public var lastBootedAt: String?
    public var simctlTimestamp: ContinuousClock.Instant?

    public var runningApp: String?
    public var runningAppTimestamp: ContinuousClock.Instant?

    public var orientation: String?
    public var orientationTimestamp: ContinuousClock.Instant?

    public var alertState: String?
    public var alertTimestamp: ContinuousClock.Instant?

    public var screenSummary: String?
    public var screenTimestamp: ContinuousClock.Instant?

    public var consoleErrorCount: Int?
    public var consoleTimestamp: ContinuousClock.Instant?

    public var wdaStatus: String?
    public var wdaTimestamp: ContinuousClock.Instant?

    public var lastScreenshotAt: ContinuousClock.Instant?

    /// Field-level update descriptor for batch mutations.
    public enum Field {
        case boot(name: String, runtime: String)
        case shutdown
        case appLaunch(bundleId: String)
        case appTerminate
        case orientation(String)
        case alert(String)
        case screenshot
        case screen(elementCount: Int, summary: String)
        case consoleErrors(Int)
        case wdaStatus(String)
    }

    mutating func apply(_ field: Field) {
        let now = ContinuousClock.now
        switch field {
        case .boot(let name, let runtime):
            state = "Booted"
            if !name.isEmpty { self.name = name }
            if !runtime.isEmpty { self.runtime = runtime }
            simctlTimestamp = now
        case .shutdown:
            state = "Shutdown"
            simctlTimestamp = now
            clearToolFields()
        case .appLaunch(let bundleId):
            runningApp = bundleId
            runningAppTimestamp = now
        case .appTerminate:
            runningApp = nil
            runningAppTimestamp = now
        case .orientation(let value):
            orientation = value
            orientationTimestamp = now
        case .alert(let value):
            alertState = value
            alertTimestamp = now
        case .screenshot:
            lastScreenshotAt = now
        case .screen(let count, let summary):
            screenSummary = "\(summary) — \(count) elements"
            screenTimestamp = now
        case .consoleErrors(let count):
            consoleErrorCount = count
            consoleTimestamp = now
        case .wdaStatus(let status):
            wdaStatus = status
            wdaTimestamp = now
        }
    }

    private mutating func clearToolFields() {
        runningApp = nil; runningAppTimestamp = nil
        orientation = nil; orientationTimestamp = nil
        alertState = nil; alertTimestamp = nil
        screenSummary = nil; screenTimestamp = nil
        consoleErrorCount = nil; consoleTimestamp = nil
        wdaStatus = nil; wdaTimestamp = nil
        lastScreenshotAt = nil
    }
}

// MARK: - Store

/// Cached device state — the observable surface that gives the LLM eyes.
/// Updated reactively by tool handlers (fire-and-forget), read by status/inspect flows.
public actor DeviceStateStore {
    public static let shared = DeviceStateStore()

    private var entries: [String: DeviceSnapshot] = [:]

    // MARK: - Bulk ingest from simctl

    public func ingest(simctlDevices devices: [String: [[String: Any]]]) {
        let now = ContinuousClock.now
        for (runtime, deviceList) in devices {
            let runtimeName = runtime.split(separator: ".").last.map(String.init) ?? runtime
            for device in deviceList {
                guard let udid = device["udid"] as? String else { continue }
                var snap = entries[udid] ?? DeviceSnapshot()
                snap.name = device["name"] as? String
                snap.state = device["state"] as? String
                snap.runtime = runtimeName
                snap.lastBootedAt = device["lastBootedAt"] as? String
                snap.simctlTimestamp = now
                if snap.state == "Shutdown" {
                    snap.apply(.shutdown)
                }
                entries[udid] = snap
            }
        }
    }

    // MARK: - Field-level update

    public func update(_ field: DeviceSnapshot.Field, for udid: String) {
        var snap = entries[udid] ?? DeviceSnapshot()
        snap.apply(field)
        entries[udid] = snap
    }

    // MARK: - Reads

    public func snapshot(for udid: String) -> DeviceSnapshot? { entries[udid] }
    public func allSnapshots() -> [String: DeviceSnapshot] { entries }

    /// Resolve a short UDID prefix (4+ chars) to full UDIDs.
    public func resolveShortUDID(_ prefix: String) -> [String] {
        let p = prefix.uppercased()
        return entries.keys.filter { $0.uppercased().hasPrefix(p) }
    }

    // MARK: - Formatting pass-through

    public func age(_ timestamp: ContinuousClock.Instant?) -> String? {
        ElapsedTime.format(since: timestamp)
    }

    public func uptime(from lastBootedAt: String?) -> String? {
        ElapsedTime.uptime(from: lastBootedAt)
    }

    // MARK: - Session helper

    public static func currentUDID(session: SessionState) async -> String? {
        guard let sim = try? await session.resolveSimulator(nil) else { return nil }
        return try? await SimTools.resolveSimulator(sim)
    }
}

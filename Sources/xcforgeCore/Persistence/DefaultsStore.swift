import Foundation

/// Persists lightweight workflow defaults to disk so they survive process restarts.
/// Storage location: `{baseDir}/defaults.json` where baseDir defaults to `~/.xcforge/`.
public struct DefaultsStore: Sendable {
    let fileURL: URL

    public init(baseDirectory: URL? = nil) {
        let base: URL
        if let baseDirectory {
            base = baseDirectory
        } else if let override = ProcessInfo.processInfo.environment["XCFORGE_RUN_STORE_DIR"],
            !override.isEmpty
        {
            let expanded = (override as NSString).expandingTildeInPath
            let url = URL(fileURLWithPath: expanded, isDirectory: true)
            // The env var typically points to .xcforge/runs — go up one level for the base.
            // If the path doesn't end with "runs", use it directly to avoid surprising behavior.
            base = url.lastPathComponent == "runs" ? url.deletingLastPathComponent() : url
        } else {
            base = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent(".xcforge", isDirectory: true)
        }
        self.fileURL = base.appendingPathComponent("defaults.json", isDirectory: false)
    }

    public func load() -> PersistedDefaults? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(PersistedDefaults.self, from: data)
        } catch {
            Log.warn("Failed to read defaults from \(fileURL.path): \(error.localizedDescription). Starting with empty defaults.")
            return nil
        }
    }

    public func save(_ defaults: PersistedDefaults) {
        do {
            let dir = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: dir, withIntermediateDirectories: true, attributes: nil
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(defaults)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Log.warn("Failed to save defaults to \(fileURL.path): \(error.localizedDescription)")
        }
    }

    public func clear() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            Log.warn("Failed to remove defaults file at \(fileURL.path): \(error.localizedDescription)")
        }
    }
}

/// Codable representation of persisted workflow defaults.
public struct PersistedDefaults: Codable, Sendable, Equatable {
    public var project: String?
    public var scheme: String?
    public var simulator: String?
    public var bundleId: String?
    public var appPath: String?

    public init(
        project: String? = nil,
        scheme: String? = nil,
        simulator: String? = nil,
        bundleId: String? = nil,
        appPath: String? = nil
    ) {
        self.project = project
        self.scheme = scheme
        self.simulator = simulator
        self.bundleId = bundleId
        self.appPath = appPath
    }

    /// True when all fields are nil (nothing to persist).
    public var isEmpty: Bool {
        project == nil && scheme == nil && simulator == nil && bundleId == nil && appPath == nil
    }
}

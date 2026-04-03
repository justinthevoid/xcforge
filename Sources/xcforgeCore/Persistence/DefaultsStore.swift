import Foundation

/// Persists lightweight workflow defaults to disk so they survive process restarts.
/// Storage location: `{baseDir}/defaults.json` where baseDir defaults to `~/.xcforge/`.
///
/// All reads and writes use POSIX advisory file locking (`flock`) to prevent
/// cross-process race conditions between the long-running MCP server and CLI invocations.
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
        return withFileLock(.shared) { _ in
            readFromDisk()
        } ?? nil
    }

    public func save(_ defaults: PersistedDefaults) {
        do {
            let dir = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: dir, withIntermediateDirectories: true, attributes: nil
            )
        } catch {
            Log.warn("Failed to create directory for defaults at \(fileURL.path): \(error.localizedDescription)")
            return
        }

        withFileLock(.exclusive) { lockFD in
            // Re-read current disk state under the lock to avoid clobbering
            // concurrent writes from other processes.
            let existing = readFromDisk() ?? PersistedDefaults()
            let merged = existing.merging(defaults)

            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(merged)
                try data.write(to: fileURL, options: .atomic)
            } catch {
                Log.warn("Failed to save defaults to \(fileURL.path): \(error.localizedDescription)")
            }
        }
    }

    public func clear() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        withFileLock(.exclusive) { _ in
            do {
                try FileManager.default.removeItem(at: fileURL)
            } catch {
                Log.warn("Failed to remove defaults file at \(fileURL.path): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - File locking

    private enum LockMode {
        case shared, exclusive

        var flockFlag: Int32 {
            switch self {
            case .shared: return LOCK_SH
            case .exclusive: return LOCK_EX
            }
        }
    }

    /// Acquires a POSIX advisory lock on a `.lock` sibling file, executes the closure,
    /// then releases. The lock auto-releases if the process crashes.
    @discardableResult
    private func withFileLock<T>(_ mode: LockMode, body: (Int32) -> T) -> T? {
        let lockPath = fileURL.path + ".lock"
        let fd = open(lockPath, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else {
            Log.warn("Failed to open lock file at \(lockPath)")
            return nil
        }
        defer {
            flock(fd, LOCK_UN)
            close(fd)
        }
        guard flock(fd, mode.flockFlag) == 0 else {
            Log.warn("Failed to acquire lock on \(lockPath)")
            return nil
        }
        return body(fd)
    }

    /// Reads and decodes the defaults file without locking (caller must hold lock).
    private func readFromDisk() -> PersistedDefaults? {
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

    // MARK: - Named Profiles

    private var profilesURL: URL {
        fileURL.deletingLastPathComponent().appendingPathComponent("profiles.json", isDirectory: false)
    }

    public func listProfiles() -> [String: PersistedDefaults] {
        guard FileManager.default.fileExists(atPath: profilesURL.path) else { return [:] }
        do {
            let data = try Data(contentsOf: profilesURL)
            return try JSONDecoder().decode([String: PersistedDefaults].self, from: data)
        } catch {
            Log.warn("Failed to read profiles from \(profilesURL.path): \(error.localizedDescription)")
            return [:]
        }
    }

    public func saveProfile(name: String, defaults: PersistedDefaults) {
        do {
            let dir = profilesURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            Log.warn("Failed to create profiles directory: \(error.localizedDescription)")
            return
        }

        var profiles = listProfiles()
        profiles[name] = defaults
        writeProfiles(profiles)
    }

    public func loadProfile(name: String) -> PersistedDefaults? {
        listProfiles()[name]
    }

    public func deleteProfile(name: String) -> Bool {
        var profiles = listProfiles()
        guard profiles.removeValue(forKey: name) != nil else { return false }
        writeProfiles(profiles)
        return true
    }

    private func writeProfiles(_ profiles: [String: PersistedDefaults]) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(profiles)
            try data.write(to: profilesURL, options: .atomic)
        } catch {
            Log.warn("Failed to write profiles to \(profilesURL.path): \(error.localizedDescription)")
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

    /// Returns a new value where non-nil fields from `other` overwrite `self`,
    /// and nil fields in `other` preserve `self`'s values.
    func merging(_ other: PersistedDefaults) -> PersistedDefaults {
        PersistedDefaults(
            project: other.project ?? project,
            scheme: other.scheme ?? scheme,
            simulator: other.simulator ?? simulator,
            bundleId: other.bundleId ?? bundleId,
            appPath: other.appPath ?? appPath
        )
    }
}

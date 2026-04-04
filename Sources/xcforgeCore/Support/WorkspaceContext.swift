import Foundation
import MCP

struct WorkflowDefaultsSnapshot: Sendable {
    let project: String?
    let scheme: String?
    let simulator: String?
    let bundleId: String?
    let appPath: String?
}

/// Session state actor — caches resolved project/scheme/simulator defaults.
/// Resolution order: explicit parameter → session default → auto-detect → error with options.
public actor SessionState {
    // MARK: - Stored defaults

    private(set) var project: String?
    private(set) var scheme: String?
    private(set) var simulator: String?
    public private(set) var bundleId: String?
    public private(set) var appPath: String?

    // Auto-promotion: consecutive explicit values become defaults
    private var projectStreak: (value: String, count: Int) = ("", 0)
    private var schemeStreak: (value: String, count: Int) = ("", 0)
    private var simulatorStreak: (value: String, count: Int) = ("", 0)
    private let promotionThreshold = 3

    // Persistence
    private let defaultsStore: DefaultsStore

    public init(defaultsStore: DefaultsStore = DefaultsStore()) {
        self.defaultsStore = defaultsStore

        // Load persisted defaults eagerly from disk.
        // Only restore the three user-managed fields; build info (bundleId/appPath)
        // is populated by workflow execution, not persisted defaults.
        if let persisted = defaultsStore.load() {
            self.project = persisted.project
            self.scheme = persisted.scheme
            self.simulator = persisted.simulator
        }
    }

    // MARK: - Resolution (explicit → default → auto-detect)

    /// Resolve project path. Caches auto-detected result for the session.
    public func resolveProject(_ explicit: String?) async throws -> String {
        if let explicit {
            trackUsage(value: explicit, streak: &projectStreak, stored: &project)
            return explicit
        }
        if let stored = project { return stored }

        let detected = try await AutoDetect.project()
        self.project = detected
        Log.warn("Auto-detected project: \((detected as NSString).lastPathComponent)")
        return detected
    }

    /// Resolve scheme name. Caches auto-detected result for the session.
    public func resolveScheme(_ explicit: String?, project: String) async throws -> String {
        if let explicit {
            trackUsage(value: explicit, streak: &schemeStreak, stored: &scheme)
            return explicit
        }
        if let stored = scheme { return stored }

        let detected = try await AutoDetect.scheme(project: project)
        self.scheme = detected
        Log.warn("Auto-detected scheme: \(detected)")
        return detected
    }

    /// Resolve simulator. NOT cached — booted state can change between calls.
    public func resolveSimulator(_ explicit: String?) async throws -> String {
        if let explicit {
            trackUsage(value: explicit, streak: &simulatorStreak, stored: &simulator)
            return explicit
        }
        if let stored = simulator { return stored }
        return try await AutoDetect.simulator()
    }

    // MARK: - Build info (populated after successful build_sim)

    func setBuildInfo(bundleId: String, appPath: String?) {
        self.bundleId = bundleId
        self.appPath = appPath
    }

    public func resolveBundleId(_ explicit: String?) -> String? {
        explicit ?? bundleId
    }

    func resolveAppPath(_ explicit: String?) -> String? {
        explicit ?? appPath
    }

    func clearBuildInfo() {
        bundleId = nil
        appPath = nil
    }

    func workflowDefaultsSnapshot() -> WorkflowDefaultsSnapshot {
        WorkflowDefaultsSnapshot(
            project: project,
            scheme: scheme,
            simulator: simulator,
            bundleId: bundleId,
            appPath: appPath
        )
    }

    // MARK: - Manual defaults (set_defaults escape hatch)

    public func setDefaults(project: String?, scheme: String?, simulator: String?) {
        if let p = project { self.project = p }
        if let s = scheme { self.scheme = s }
        if let sim = simulator { self.simulator = sim }
        persistCurrentDefaults()
    }

    public func showDefaults() -> String {
        var lines = ["Session defaults:"]
        lines.append("  project:   \(project ?? "(auto-detect)")")
        lines.append("  scheme:    \(scheme ?? "(auto-detect)")")
        lines.append("  simulator: \(simulator ?? "(auto-detect — queries booted sim each call)")")
        lines.append("  bundle_id: \(bundleId ?? "(from last build)")")
        lines.append("  app_path:  \(appPath ?? "(from last build)")")
        return lines.joined(separator: "\n")
    }

    public func clearDefaults() {
        project = nil
        scheme = nil
        simulator = nil
        clearBuildInfo()
        projectStreak = ("", 0)
        schemeStreak = ("", 0)
        simulatorStreak = ("", 0)
        defaultsStore.clear()
    }

    // MARK: - Persistence write-through

    private func persistCurrentDefaults() {
        // Only persist the three user-managed fields. Build info (bundleId/appPath)
        // is set by workflow execution and must not leak into persisted defaults.
        let defaults = PersistedDefaults(
            project: project,
            scheme: scheme,
            simulator: simulator
        )
        if defaults.isEmpty {
            defaultsStore.clear()
        } else {
            defaultsStore.save(defaults)
        }
    }

    // MARK: - Auto-promotion

    private func trackUsage(
        value: String, streak: inout (value: String, count: Int), stored: inout String?
    ) {
        if value == streak.value {
            streak.count += 1
        } else {
            streak = (value, 1)
        }
        if streak.count >= promotionThreshold && stored != value {
            stored = value
            Log.warn("Auto-promoted session default: \(value) (used \(streak.count)x consecutively)")
        }
    }

    // MARK: - Tool definition

    public static let tools: [Tool] = [
        Tool(
            name: "set_defaults",
            description: """
                Set, show, or clear session defaults for project, scheme, and simulator. \
                These defaults are used when parameters are omitted from tool calls. \
                Usually not needed — the server auto-detects from the environment. \
                Use as escape hatch when auto-detection picks the wrong target.
                """,
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project": .object([
                        "type": .string("string"),
                        "description": .string("Default project path (.xcodeproj or .xcworkspace)"),
                    ]),
                    "scheme": .object([
                        "type": .string("string"),
                        "description": .string("Default scheme name"),
                    ]),
                    "simulator": .object([
                        "type": .string("string"),
                        "description": .string("Default simulator name or UDID"),
                    ]),
                    "action": .object([
                        "type": .string("string"),
                        "description": .string("'set' (default), 'show', or 'clear'"),
                        "enum": .array([.string("set"), .string("show"), .string("clear")]),
                    ]),
                ]),
            ])
        ),
    ]

    struct SetDefaultsInput: Decodable {
        let project: String?
        let scheme: String?
        let simulator: String?
        let action: String?
    }

    static func handleSetDefaults(_ args: [String: Value]?, env: Environment) async -> CallTool.Result {
        switch ToolInput.decode(SetDefaultsInput.self, from: args) {
        case .failure(let err): return err
        case .success(let input):
            let action = input.action ?? "set"
            let state = env.session

            switch action {
            case "show":
                return .ok(await state.showDefaults())
            case "clear":
                await state.clearDefaults()
                return .ok("Session defaults cleared. Auto-detection will be used for all parameters.")
            default:
                if input.project == nil && input.scheme == nil && input.simulator == nil {
                    return .ok(await state.showDefaults())
                }

                await state.setDefaults(project: input.project, scheme: input.scheme, simulator: input.simulator)
                return .ok(await state.showDefaults())
            }
        }
    }
}

extension SessionState: ToolProvider {
    public static func dispatch(_ name: String, _ args: [String: Value]?, env: Environment) async -> CallTool.Result? {
        switch name {
        case "set_defaults": return await handleSetDefaults(args, env: env)
        default: return nil
        }
    }
}

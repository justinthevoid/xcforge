import Foundation
import MCP

struct WorkflowDefaultsSnapshot: Sendable {
  let project: String?
  let scheme: String?
  let simulator: String?
  let bundleId: String?
  let appPath: String?
}

enum DefaultsSource: String, Sendable {
  case persisted = "persisted"
  case autoPromoted = "auto-promoted"
  case explicit = "explicit"
  case repoConfig = "repo-config"
  case autoDetected = "auto-detect"
  case buildDerived = "from last build"
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

  // Source tracking for showDefaults annotations
  private var projectSource: DefaultsSource = .autoDetected
  private var schemeSource: DefaultsSource = .autoDetected
  private var simulatorSource: DefaultsSource = .autoDetected

  // Repo-level config (.xcforge.yaml)
  private var repoDefaults: PersistedDefaults?

  // Persistence
  private let defaultsStore: DefaultsStore

  public init(defaultsStore: DefaultsStore = DefaultsStore(), cwd: String? = nil) {
    self.defaultsStore = defaultsStore

    // Load repo-level config from .xcforge.yaml (walk up from CWD to .git root).
    let startDir = cwd ?? FileManager.default.currentDirectoryPath
    self.repoDefaults = RepoConfig.discover(from: startDir)

    // Load persisted defaults eagerly from disk.
    // Only restore the three user-managed fields; build info (bundleId/appPath)
    // is populated by workflow execution, not persisted defaults.
    if let persisted = defaultsStore.load() {
      self.project = persisted.project
      self.scheme = persisted.scheme
      self.simulator = persisted.simulator
      if persisted.project != nil { projectSource = .persisted }
      if persisted.scheme != nil { schemeSource = .persisted }
      if persisted.simulator != nil { simulatorSource = .persisted }
    }
  }

  // MARK: - Resolution (explicit → default → auto-detect)

  /// Resolve project path. Caches auto-detected result for the session.
  public func resolveProject(_ explicit: String?) async throws -> String {
    if let explicit {
      trackUsage(value: explicit, streak: &projectStreak, stored: &project, source: &projectSource)
      return explicit
    }
    if let stored = project { return stored }
    if let repo = repoDefaults?.project {
      self.project = repo
      self.projectSource = .repoConfig
      return repo
    }

    let detected = try await AutoDetect.project()
    self.project = detected
    self.projectSource = .autoDetected
    Log.warn("Auto-detected project: \((detected as NSString).lastPathComponent)")
    return detected
  }

  /// Resolve scheme name. Caches auto-detected result for the session.
  public func resolveScheme(_ explicit: String?, project: String) async throws -> String {
    if let explicit {
      trackUsage(value: explicit, streak: &schemeStreak, stored: &scheme, source: &schemeSource)
      return explicit
    }
    if let stored = scheme { return stored }
    if let repo = repoDefaults?.scheme {
      self.scheme = repo
      self.schemeSource = .repoConfig
      return repo
    }

    let detected = try await AutoDetect.scheme(project: project)
    self.scheme = detected
    self.schemeSource = .autoDetected
    Log.warn("Auto-detected scheme: \(detected)")
    return detected
  }

  /// Resolve simulator. NOT cached — booted state can change between calls.
  public func resolveSimulator(_ explicit: String?) async throws -> String {
    if let explicit {
      trackUsage(
        value: explicit, streak: &simulatorStreak, stored: &simulator, source: &simulatorSource)
      return explicit
    }
    if let stored = simulator { return stored }
    if let repo = repoDefaults?.simulator {
      self.simulator = repo
      self.simulatorSource = .repoConfig
      return repo
    }
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
    if let p = project {
      self.project = p
      self.projectSource = .explicit
    }
    if let s = scheme {
      self.scheme = s
      self.schemeSource = .explicit
    }
    if let sim = simulator {
      self.simulator = sim
      self.simulatorSource = .explicit
    }
    persistCurrentDefaults()
  }

  public func showDefaults() -> String {
    var lines = ["Session defaults:"]
    lines.append("  project:   \(annotated(project, source: projectSource))")
    lines.append("  scheme:    \(annotated(scheme, source: schemeSource))")
    lines.append(
      "  simulator: \(annotated(simulator, source: simulatorSource, nilLabel: "(auto-detect — queries booted sim each call)"))"
    )
    lines.append("  bundle_id: \(bundleId ?? "(from last build)")")
    lines.append("  app_path:  \(appPath ?? "(from last build)")")
    return lines.joined(separator: "\n")
  }

  private func annotated(
    _ value: String?, source: DefaultsSource, nilLabel: String = "(auto-detect)"
  ) -> String {
    guard let value else { return nilLabel }
    return "\(value) (\(source.rawValue))"
  }

  public func clearDefaults() {
    project = nil
    scheme = nil
    simulator = nil
    clearBuildInfo()
    projectStreak = ("", 0)
    schemeStreak = ("", 0)
    simulatorStreak = ("", 0)
    projectSource = .autoDetected
    schemeSource = .autoDetected
    simulatorSource = .autoDetected
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

  // MARK: - Named Profiles

  private static func validateProfileName(_ name: String) -> String? {
    guard !name.isEmpty, name.count <= 32,
      name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }),
      name.lowercased() == name,
      !name.hasPrefix("-"), !name.hasSuffix("-")
    else {
      return "Invalid profile name '\(name)'. Use kebab-case (a-z, 0-9, hyphens), max 32 chars."
    }
    return nil
  }

  public func profileSave(name: String) -> String {
    if let err = Self.validateProfileName(name) { return err }
    let snapshot = PersistedDefaults(project: project, scheme: scheme, simulator: simulator)
    if snapshot.isEmpty {
      return "No defaults to save. Set project/scheme/simulator first."
    }
    let existed = defaultsStore.loadProfile(name: name) != nil
    defaultsStore.saveProfile(name: name, defaults: snapshot)
    return existed
      ? "Profile '\(name)' updated: \(profileSummary(snapshot))"
      : "Profile '\(name)' saved: \(profileSummary(snapshot))"
  }

  public func profileSwitch(name: String) -> String {
    guard let loaded = defaultsStore.loadProfile(name: name) else {
      let names = defaultsStore.listProfiles().keys.sorted()
      if names.isEmpty { return "Profile '\(name)' not found. No profiles saved yet." }
      return "Profile '\(name)' not found. Available: \(names.joined(separator: ", "))"
    }
    if let p = loaded.project {
      self.project = p
      self.projectSource = .persisted
    }
    if let s = loaded.scheme {
      self.scheme = s
      self.schemeSource = .persisted
    }
    if let sim = loaded.simulator {
      self.simulator = sim
      self.simulatorSource = .persisted
    }
    persistCurrentDefaults()
    return "Switched to profile '\(name)': \(profileSummary(loaded))"
  }

  public func profileList() -> String {
    let profiles = defaultsStore.listProfiles()
    if profiles.isEmpty { return "No profiles saved." }
    var lines = ["Saved profiles:"]
    for name in profiles.keys.sorted() {
      lines.append("  \(name): \(profileSummary(profiles[name]!))")
    }
    return lines.joined(separator: "\n")
  }

  public func profileDelete(name: String) -> String {
    if defaultsStore.deleteProfile(name: name) {
      return "Profile '\(name)' deleted."
    }
    return "Profile '\(name)' not found."
  }

  private func profileSummary(_ d: PersistedDefaults) -> String {
    var parts: [String] = []
    if let p = d.project { parts.append("project=\((p as NSString).lastPathComponent)") }
    if let s = d.scheme { parts.append("scheme=\(s)") }
    if let sim = d.simulator { parts.append("sim=\(sim)") }
    return parts.isEmpty ? "(empty)" : parts.joined(separator: ", ")
  }

  // MARK: - Auto-promotion

  private func trackUsage(
    value: String, streak: inout (value: String, count: Int), stored: inout String?,
    source: inout DefaultsSource
  ) {
    if value == streak.value {
      streak.count += 1
    } else {
      streak = (value, 1)
    }
    if streak.count >= promotionThreshold && stored != value {
      stored = value
      source = .autoPromoted
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
    Tool(
      name: "profile_save",
      description: "Save current session defaults as a named profile for quick switching.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "name": .object([
            "type": .string("string"),
            "description": .string("Profile name (kebab-case, max 32 chars, e.g. 'iphone-debug')"),
          ])
        ]),
        "required": .array([.string("name")]),
      ])
    ),
    Tool(
      name: "profile_switch",
      description: "Switch session defaults to a previously saved profile.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "name": .object([
            "type": .string("string"),
            "description": .string("Profile name to activate"),
          ])
        ]),
        "required": .array([.string("name")]),
      ])
    ),
    Tool(
      name: "profile_list",
      description: "List all saved session profiles.",
      inputSchema: .object(["type": .string("object"), "properties": .object([:])])
    ),
    Tool(
      name: "profile_delete",
      description: "Delete a saved session profile.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "name": .object([
            "type": .string("string"),
            "description": .string("Profile name to delete"),
          ])
        ]),
        "required": .array([.string("name")]),
      ])
    ),
  ]

  struct SetDefaultsInput: Decodable {
    let project: String?
    let scheme: String?
    let simulator: String?
    let action: String?
  }

  struct ProfileNameInput: Decodable {
    let name: String
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

        await state.setDefaults(
          project: input.project, scheme: input.scheme, simulator: input.simulator)
        return .ok(await state.showDefaults())
      }
    }
  }

  static func handleProfileSave(_ args: [String: Value]?, env: Environment) async -> CallTool.Result {
    switch ToolInput.decode(ProfileNameInput.self, from: args) {
    case .failure(let err): return err
    case .success(let input): return .ok(await env.session.profileSave(name: input.name))
    }
  }

  static func handleProfileSwitch(_ args: [String: Value]?, env: Environment) async
    -> CallTool.Result
  {
    switch ToolInput.decode(ProfileNameInput.self, from: args) {
    case .failure(let err): return err
    case .success(let input): return .ok(await env.session.profileSwitch(name: input.name))
    }
  }

  static func handleProfileList(_ args: [String: Value]?, env: Environment) async -> CallTool.Result {
    .ok(await env.session.profileList())
  }

  static func handleProfileDelete(_ args: [String: Value]?, env: Environment) async
    -> CallTool.Result
  {
    switch ToolInput.decode(ProfileNameInput.self, from: args) {
    case .failure(let err): return err
    case .success(let input): return .ok(await env.session.profileDelete(name: input.name))
    }
  }
}

extension SessionState: ToolProvider {
  public static func dispatch(_ name: String, _ args: [String: Value]?, env: Environment) async
    -> CallTool.Result?
  {
    switch name {
    case "set_defaults": return await handleSetDefaults(args, env: env)
    case "profile_save": return await handleProfileSave(args, env: env)
    case "profile_switch": return await handleProfileSwitch(args, env: env)
    case "profile_list": return await handleProfileList(args, env: env)
    case "profile_delete": return await handleProfileDelete(args, env: env)
    default: return nil
    }
  }
}

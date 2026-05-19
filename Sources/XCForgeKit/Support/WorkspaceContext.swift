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
  private var buildScheme: String?

  // Auto-promotion: consecutive explicit values become defaults
  private var projectStreak: (value: String, count: Int) = ("", 0)
  private var schemeStreak: (value: String, count: Int) = ("", 0)
  private var simulatorStreak: (value: String, count: Int) = ("", 0)
  private let promotionThreshold = 3

  // Source tracking for showDefaults annotations
  private var projectSource: DefaultsSource = .autoDetected
  private var schemeSource: DefaultsSource = .autoDetected
  private var simulatorSource: DefaultsSource = .autoDetected

  // Repo-level config (.xcforge.yaml) — repo-scoped, outranks persisted.
  private var repoDefaults: RepoConfig.Values?

  // Per-project persisted record. Loaded lazily after the active project is
  // resolved (canonical-keyed in `~/.xcforge/defaults.json`). Cached so we do
  // not re-read disk every resolution.
  private var loadedRecordForProject: String?
  private var persistedScheme: String?
  private var persistedSimulator: String?

  // Persistence
  private let defaultsStore: DefaultsStore

  public init(defaultsStore: DefaultsStore = DefaultsStore(), cwd: String? = nil) {
    self.defaultsStore = defaultsStore

    // Load repo-level config from .xcforge.yaml (walk up from CWD to .git root).
    let startDir = cwd ?? FileManager.default.currentDirectoryPath
    self.repoDefaults = RepoConfig.discover(from: startDir)

    // Persisted project/scheme/simulator + build info are NOT pre-loaded.
    // They are resolved per-project after `resolveProject` settles, so an
    // App A build cannot bleed bundleId/appPath into an App B session.
  }

  /// Lazy-load the persisted record for the currently active project. Cached
  /// for the rest of the session — set/clear/buildInfo paths refresh it.
  private func loadRecordIfNeeded(forProject project: String) {
    guard let key = DefaultsStore.validCanonicalKey(project) else {
      Log.debug("loadRecordIfNeeded: rejecting invalid project key '\(project)'")
      return
    }
    if loadedRecordForProject == key { return }
    let record = defaultsStore.load(forProject: key)
    loadedRecordForProject = key
    persistedScheme = record?.scheme
    persistedSimulator = record?.simulator
    bundleId = record?.bundleId
    appPath = record?.appPath
    buildScheme = record?.buildScheme
  }

  /// Returns the canonical key for the currently active project, or nil when
  /// no project has been resolved yet OR when the resolved project canonicalizes
  /// to an invalid sentinel (empty input, `/`). Used by setBuildInfo / persist paths.
  private func activeProjectKey() -> String? {
    if let p = project, let key = DefaultsStore.validCanonicalKey(p) { return key }
    if let cached = loadedRecordForProject, !cached.isEmpty { return cached }
    return nil
  }

  // MARK: - Resolution (explicit → default → auto-detect)

  /// Resolve project path. Caches auto-detected result for the session.
  /// Order: explicit → session cache → `.xcforge.yaml` → AutoDetect.
  /// There is no longer a "global persisted project" fallback — project
  /// identity must come from a source the user controls.
  public func resolveProject(_ explicit: String?) async throws -> String {
    if let explicit {
      trackUsage(value: explicit, streak: &projectStreak, stored: &project, source: &projectSource)
      loadRecordIfNeeded(forProject: explicit)
      return explicit
    }
    if let stored = project {
      loadRecordIfNeeded(forProject: stored)
      return stored
    }
    if let repo = repoDefaults?.project {
      self.project = repo
      self.projectSource = .repoConfig
      loadRecordIfNeeded(forProject: repo)
      return repo
    }

    let detected = try await AutoDetect.project()
    self.project = detected
    self.projectSource = .autoDetected
    loadRecordIfNeeded(forProject: detected)
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
    loadRecordIfNeeded(forProject: project)
    if let persisted = persistedScheme {
      self.scheme = persisted
      self.schemeSource = .persisted
      return persisted
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
    if let persisted = persistedSimulator {
      self.simulator = persisted
      self.simulatorSource = .persisted
      return persisted
    }
    return try await AutoDetect.simulator()
  }

  // MARK: - Repo-only resolvers (configuration / testPlan)

  /// Resolve build configuration. Repo-only — never persisted.
  /// Order: explicit → `.xcforge.yaml` `configuration` → `"Debug"`.
  public func resolveConfiguration(_ explicit: String?) -> String {
    explicit ?? repoDefaults?.configuration ?? "Debug"
  }

  /// Resolve test plan. Repo-only — never persisted.
  /// Order: explicit → `.xcforge.yaml` `testPlan` → nil (no test plan).
  public func resolveTestPlan(_ explicit: String?) -> String? {
    explicit ?? repoDefaults?.testPlan
  }

  /// Resolve test watchdog timeout (seconds). Repo-only — never persisted.
  ///
  /// Order: explicit > `.xcforge.yaml` `testTimeout` > `long ? 1800 : 180`.
  ///
  /// `explicit` must be a positive integer. A value `<= 0` is symmetric with the
  /// YAML path's rejection of non-positive values: it falls through to the
  /// repo default and then to the long/short baseline, with a warning. (P8)
  public func resolveTestTimeout(explicit: Int?, long: Bool) -> TimeInterval {
    if let explicit {
      if explicit > 0 {
        return TimeInterval(explicit)
      }
      Log.warn(
        "resolveTestTimeout: ignoring non-positive explicit timeout \(explicit); falling back."
      )
    }
    if let repo = repoDefaults?.testTimeout { return TimeInterval(repo) }
    return long ? 1800 : 180
  }

  /// Resolve simulator and return both its display name and UDID.
  ///
  /// Calls `resolveSimulator` first, then resolves to a UDID via `AutoDetect.resolveSimulatorNameAndUDID`.
  /// The existing `resolveSimulator` signature is unchanged for backward compatibility.
  public func resolveSimulatorWithUDID(_ explicit: String?) async throws -> (
    name: String, udid: String
  ) {
    let resolved = try await resolveSimulator(explicit)
    return try await AutoDetect.resolveSimulatorNameAndUDID(resolved)
  }

  // MARK: - Build info (populated after successful build_sim)

  func setBuildInfo(bundleId: String, appPath: String?, scheme: String) {
    self.bundleId = bundleId
    self.appPath = appPath
    self.buildScheme = scheme
    // Build product info is *always* keyed to the active project. If no
    // project has been resolved yet, this is a programmer error in the caller
    // (build paths resolve project before bundleId), so we no-op rather than
    // write an unkeyed blob.
    guard let key = activeProjectKey() else {
      Log.warn("setBuildInfo called with no active project; skipping persist")
      return
    }
    defaultsStore.save(
      PersistedDefaults(
        project: key, bundleId: bundleId, appPath: appPath, buildScheme: scheme),
      forProject: key
    )
  }

  public func resolveBundleId(_ explicit: String?) -> String? {
    if let explicit { return explicit }
    // scheme is no longer eagerly cached from persisted at init, so the
    // build-scheme mismatch guard must consult the effective scheme
    // (session cache → repo config → persisted) to keep stale bundle ids
    // from a different scheme's build from leaking into launch/install.
    let effScheme = scheme ?? repoDefaults?.scheme ?? persistedScheme
    if let buildScheme, let effScheme, buildScheme != effScheme { return nil }
    return bundleId
  }

  func resolveAppPath(_ explicit: String?) -> String? {
    if let explicit { return explicit }
    let effScheme = scheme ?? repoDefaults?.scheme ?? persistedScheme
    if let buildScheme, let effScheme, buildScheme != effScheme { return nil }
    return appPath
  }

  func clearBuildInfo() {
    bundleId = nil
    appPath = nil
    buildScheme = nil
    if let key = activeProjectKey() {
      defaultsStore.clearBuildInfo(forProject: key)
    } else {
      Log.debug("clearBuildInfo with no active project; in-memory only")
    }
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

  /// Set one or more session defaults explicitly. Returns `true` when the
  /// values were persisted to disk, `false` when no active project key could
  /// be resolved (the values still apply in-memory for this session). Handlers
  /// surface the `false` case so the user is not silently misled. (P7)
  ///
  /// Resetting matching streaks (P9): explicitly overriding a field zeroes the
  /// auto-promotion streak for that field so an accidental future use of the
  /// *old* value does not immediately re-promote it.
  @discardableResult
  public func setDefaults(project: String?, scheme: String?, simulator: String?) -> Bool {
    if let p = project {
      self.project = p
      self.projectSource = .explicit
      projectStreak = ("", 0)
      loadRecordIfNeeded(forProject: p)
    }
    if let s = scheme {
      self.scheme = s
      self.schemeSource = .explicit
      schemeStreak = ("", 0)
    }
    if let sim = simulator {
      self.simulator = sim
      self.simulatorSource = .explicit
      simulatorStreak = ("", 0)
    }
    return persistCurrentDefaults()
  }

  public func showDefaults() -> String {
    // When the session cache is empty, surface what *would* resolve next
    // (repo config outranks persisted) so labels stay accurate before the
    // first build/test resolves and caches a value.
    let projectEffective = effectiveProject(cached: project, source: projectSource)
    let schemeEffective = effective(scheme, schemeSource, repoDefaults?.scheme, persistedScheme)
    let simulatorEffective = effective(
      simulator, simulatorSource, repoDefaults?.simulator, persistedSimulator)

    var lines = ["Session defaults:"]
    if let key = activeProjectKey() {
      lines.append("  active project key: \(key)")
    }
    lines.append("  project:   \(annotated(projectEffective.0, source: projectEffective.1))")
    lines.append("  scheme:    \(annotated(schemeEffective.0, source: schemeEffective.1))")
    lines.append(
      "  simulator: \(annotated(simulatorEffective.0, source: simulatorEffective.1, nilLabel: "(auto-detect — queries booted sim each call)"))"
    )
    lines.append("  bundle_id: \(bundleId ?? "(from last build)")")
    lines.append("  app_path:  \(appPath ?? "(from last build)")")
    if let config = repoDefaults?.configuration {
      lines.append("  configuration: \(config) (repo-config)")
    }
    if let plan = repoDefaults?.testPlan {
      lines.append("  test_plan: \(plan) (repo-config)")
    }
    if let t = repoDefaults?.testTimeout {
      lines.append("  test_timeout: \(t)s (repo-config)")
    }
    if let ap = repoDefaults?.autoPromote {
      lines.append("  auto_promote: \(ap) (repo-config)")
    }
    if projectSource == .autoPromoted || schemeSource == .autoPromoted
      || simulatorSource == .autoPromoted
    {
      lines.append(
        "  note: one or more defaults were auto-promoted from repeated explicit use.")
    }
    return lines.joined(separator: "\n")
  }

  /// Pick the value/source to display for scheme/simulator: a cached session
  /// value (with its tracked source) wins; otherwise fall back to repo config,
  /// then to this project's persisted record.
  private func effective(
    _ cached: String?, _ cachedSource: DefaultsSource, _ repo: String?, _ persisted: String?
  ) -> (String?, DefaultsSource) {
    if let cached { return (cached, cachedSource) }
    if let repo { return (repo, .repoConfig) }
    if let persisted { return (persisted, .persisted) }
    return (nil, .autoDetected)
  }

  /// Project-effective resolution does NOT have a persisted-per-project layer:
  /// project identity is what we look records up *by*, so a persisted-project
  /// fallback would be circular. Explicit overload to keep that invariant
  /// from being silently reintroduced. (P12)
  private func effectiveProject(
    cached: String?, source cachedSource: DefaultsSource
  ) -> (String?, DefaultsSource) {
    if let cached { return (cached, cachedSource) }
    if let repo = repoDefaults?.project { return (repo, .repoConfig) }
    return (nil, .autoDetected)
  }

  private func annotated(
    _ value: String?, source: DefaultsSource, nilLabel: String = "(auto-detect)"
  ) -> String {
    guard let value else { return nilLabel }
    return "\(value) (\(source.rawValue))"
  }

  /// True when a repo `.xcforge.yaml` is in effect. Used so `clear` does not
  /// falsely claim pure auto-detection while repo config still applies.
  public func hasRepoConfig() -> Bool { repoDefaults != nil }

  /// Clear the *active* project's persisted record (and in-memory caches).
  /// Other projects' records on disk are not touched.
  public func clearDefaults() {
    let activeKey = activeProjectKey()
    project = nil
    scheme = nil
    simulator = nil
    persistedScheme = nil
    persistedSimulator = nil
    loadedRecordForProject = nil
    bundleId = nil
    appPath = nil
    buildScheme = nil
    projectStreak = ("", 0)
    schemeStreak = ("", 0)
    simulatorStreak = ("", 0)
    projectSource = .autoDetected
    schemeSource = .autoDetected
    simulatorSource = .autoDetected
    if let key = activeKey {
      defaultsStore.clear(forProject: key)
    }
  }

  /// Clear every project's record (the entire defaults file).
  public func clearAllDefaults() {
    project = nil
    scheme = nil
    simulator = nil
    persistedScheme = nil
    persistedSimulator = nil
    loadedRecordForProject = nil
    bundleId = nil
    appPath = nil
    buildScheme = nil
    projectStreak = ("", 0)
    schemeStreak = ("", 0)
    simulatorStreak = ("", 0)
    projectSource = .autoDetected
    schemeSource = .autoDetected
    simulatorSource = .autoDetected
    defaultsStore.clearAll()
  }

  // MARK: - Persistence write-through

  /// Persist the three user-managed fields. Returns `true` when the write
  /// reached disk, `false` when no active project key could be resolved (the
  /// in-memory session state still applies). Build info (bundleId/appPath) is
  /// set by workflow execution and must not leak into persisted defaults. (P7)
  @discardableResult
  private func persistCurrentDefaults() -> Bool {
    guard let key = activeProjectKey() else {
      Log.warn("persistCurrentDefaults: no active project; defaults applied in-memory only")
      return false
    }
    let defaults = PersistedDefaults(
      project: key,
      scheme: scheme,
      simulator: simulator
    )
    if defaults.scheme == nil && defaults.simulator == nil {
      defaultsStore.clear(forProject: key)
    } else {
      defaultsStore.save(defaults, forProject: key)
    }
    return true
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

    // P6: switching projects must invalidate any per-project caches inherited
    // from the previous active project. Without this, `resolveBundleId(nil)`
    // after switching from A to B would return A's bundleId — the precise
    // cross-project bleed the v2 envelope is designed to prevent. We clear
    // every per-project cached field BEFORE installing the new project, and
    // re-prime via `loadRecordIfNeeded` so persistedScheme/persistedSimulator
    // for the *new* project are filled in.
    if loaded.project != nil {
      bundleId = nil
      appPath = nil
      buildScheme = nil
      persistedScheme = nil
      persistedSimulator = nil
      loadedRecordForProject = nil
    }

    if let p = loaded.project {
      self.project = p
      self.projectSource = .persisted
      projectStreak = ("", 0)
      loadRecordIfNeeded(forProject: p)
    }
    if let s = loaded.scheme {
      self.scheme = s
      self.schemeSource = .persisted
      schemeStreak = ("", 0)
    }
    if let sim = loaded.simulator {
      self.simulator = sim
      self.simulatorSource = .persisted
      simulatorStreak = ("", 0)
    }

    let persisted = persistCurrentDefaults()
    var msg = "Switched to profile '\(name)': \(profileSummary(loaded))"
    if !persisted {
      msg += "\nNote: no active project detected, defaults applied in-memory only."
    }
    return msg
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
    // `.xcforge.yaml autoPromote: false` opts out of the 3-strikes promotion.
    // When disabled, do not touch the streak counter at all (P10): toggling
    // autoPromote on later — or persisting/reloading state — would otherwise
    // trip the threshold from a single use.
    let autoPromoteEnabled = repoDefaults?.autoPromote ?? true
    guard autoPromoteEnabled else {
      streak = ("", 0)
      return
    }
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
        if await state.hasRepoConfig() {
          return .ok(
            "Session defaults cleared. The repo .xcforge.yaml still applies; "
              + "fields it does not set fall back to auto-detection.")
        }
        return .ok("Session defaults cleared. Auto-detection will be used for all parameters.")
      default:
        if input.project == nil && input.scheme == nil && input.simulator == nil {
          return .ok(await state.showDefaults())
        }

        let persisted = await state.setDefaults(
          project: input.project, scheme: input.scheme, simulator: input.simulator)
        var body = await state.showDefaults()
        if !persisted {
          body +=
            "\nNote: no active project detected, defaults applied in-memory only."
        }
        return .ok(body)
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

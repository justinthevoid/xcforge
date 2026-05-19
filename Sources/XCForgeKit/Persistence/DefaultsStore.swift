import Foundation

/// Persists lightweight workflow defaults to disk so they survive process restarts.
/// Storage location: `{baseDir}/defaults.json` where baseDir defaults to `~/.xcforge/`.
///
/// On disk we keep a v2 envelope keyed by canonical project path so that running
/// builds for different apps from different working directories cannot stomp on
/// each other's bundleId / appPath / buildScheme. The legacy flat shape (v1) is
/// migrated on first load.
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

  // MARK: - Canonicalization

  /// Sentinel returned by `canonicalKey(_:)` when the input cannot be turned into
  /// a usable project key (empty string, or normalizes to `/`). Callers MUST
  /// treat this as "no active project" and refuse to read/write the file under it.
  static let invalidCanonicalKey: String = ""

  /// Canonical key for a project/workspace path. Used as the dictionary key for
  /// the v2 envelope.
  ///
  /// Algorithm:
  /// 1. Reject `""` and post-normalization `"/"` (return the empty sentinel — the
  ///    cwd-bleed footgun if we let `URL(fileURLWithPath:)` fall through).
  /// 2. Resolve symlinks + standardize (collapses `/./`, `/foo/../`, trailing `/`).
  /// 3. For paths that exist on disk, ask the filesystem for the canonical
  ///    casing via `URL.canonicalPath` (a no-op on case-sensitive volumes; on
  ///    APFS-default case-insensitive volumes this returns the on-disk casing
  ///    so two casings of the same project collapse to one key).
  /// 4. For paths that do NOT exist (tests, freshly-typed paths), walk up to
  ///    the nearest existing ancestor: if that ancestor lives on a
  ///    case-insensitive volume, lowercase the remaining tail so the key still
  ///    collapses across casings; otherwise leave the tail as typed.
  /// 5. Apply Unicode NFC (`precomposedStringWithCanonicalMapping`) so a path
  ///    typed in NFC and one returned from APFS in NFD produce the same key.
  /// 6. Strip a redundant trailing slash (already handled by `standardizedFileURL`
  ///    but defensive for the symlink-resolved string path).
  public static func canonicalKey(_ rawPath: String) -> String {
    if rawPath.isEmpty { return invalidCanonicalKey }
    let url = URL(fileURLWithPath: rawPath).standardizedFileURL.resolvingSymlinksInPath()
    var path = url.path
    while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
    if path.isEmpty || path == "/" { return invalidCanonicalKey }

    let fm = FileManager.default
    if fm.fileExists(atPath: path) {
      // Existing path: prefer the on-disk canonical casing.
      let resolvedURL = URL(fileURLWithPath: path)
      if let values = try? resolvedURL.resourceValues(forKeys: [.canonicalPathKey]),
        let canonical = values.canonicalPath, !canonical.isEmpty
      {
        path = canonical
      }
    } else {
      // Non-existing path: walk up to find a real ancestor whose volume we can
      // inspect. If the volume is case-insensitive, lowercase the synthetic tail.
      var anchor = (path as NSString).deletingLastPathComponent
      var tailParts: [String] = [(path as NSString).lastPathComponent]
      while !anchor.isEmpty, anchor != "/", !fm.fileExists(atPath: anchor) {
        tailParts.insert((anchor as NSString).lastPathComponent, at: 0)
        anchor = (anchor as NSString).deletingLastPathComponent
      }
      let anchorURL = URL(fileURLWithPath: anchor.isEmpty ? "/" : anchor)
      let caseSensitive: Bool = {
        if let v = try? anchorURL.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey]),
          let supported = v.volumeSupportsCaseSensitiveNames
        {
          return supported
        }
        // Conservative default for macOS: APFS is case-insensitive by default.
        return false
      }()
      if !caseSensitive {
        let tail = tailParts.map { $0.lowercased() }.joined(separator: "/")
        let base = anchor.isEmpty || anchor == "/" ? "" : anchor
        path = base + "/" + tail
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
      }
    }

    // Unicode NFC: collapse precomposed/decomposed variants.
    path = path.precomposedStringWithCanonicalMapping
    return path
  }

  /// Returns `nil` if `rawPath` cannot be turned into a valid canonical key
  /// (empty input or normalizes to `/`). Use this at any boundary that accepts
  /// a user-supplied path and must refuse to act on a pathological key.
  static func validCanonicalKey(_ rawPath: String) -> String? {
    let key = canonicalKey(rawPath)
    return key == invalidCanonicalKey ? nil : key
  }

  // MARK: - Per-project load/save/clear

  /// Load the persisted record for `project` (canonical-keyed) and apply the
  /// stale-path filter. Returns `nil` if the file is missing or contains no
  /// record for that project.
  public func load(forProject project: String) -> PersistedDefaults? {
    guard let key = Self.validCanonicalKey(project) else {
      Log.debug("DefaultsStore.load: rejecting invalid project key '\(project)'")
      return nil
    }
    guard let envelope = loadEnvelope() else { return nil }
    guard let record = envelope.projects[key] else { return nil }
    return filteringStalePaths(record)
  }

  /// Merge `defaults` into the record stored under `project`'s canonical key.
  /// Other projects' records are untouched. Performed atomically under an
  /// exclusive POSIX file lock.
  public func save(_ defaults: PersistedDefaults, forProject project: String) {
    guard let key = Self.validCanonicalKey(project) else {
      Log.warn("DefaultsStore.save: refusing to save under invalid project key '\(project)'")
      return
    }
    do {
      let dir = fileURL.deletingLastPathComponent()
      try FileManager.default.createDirectory(
        at: dir, withIntermediateDirectories: true, attributes: nil
      )
    } catch {
      Log.warn(
        "Failed to create directory for defaults at \(fileURL.path): \(error.localizedDescription)")
      return
    }

    withFileLock(.exclusive) { _ in
      let readResult = readEnvelopeFromDisk()
      switch readResult {
      case .envelope(let env):
        var envelope = env
        let existing = envelope.projects[key] ?? PersistedDefaults()
        var merged = existing.merging(defaults)
        // Always pin the in-record `project` to its canonical key for parity
        // with the envelope key (helps round-trip + debugging).
        merged.project = key
        envelope.projects[key] = merged
        writeEnvelope(envelope)
      case .empty:
        var envelope = StoredEnvelope.empty
        var merged = defaults
        merged.project = key
        envelope.projects[key] = merged
        writeEnvelope(envelope)
      case .unrecognized:
        // P2: refuse to overwrite an unreadable / forward-version file. Back
        // it up first so future xcforge versions (or human inspection) can
        // recover, then write the new envelope. If backup fails, abort the
        // write to preserve the original bytes.
        if backupUnrecognizedFile() {
          var envelope = StoredEnvelope.empty
          var merged = defaults
          merged.project = key
          envelope.projects[key] = merged
          writeEnvelope(envelope)
        } else {
          Log.warn(
            "DefaultsStore.save: backup of unrecognized defaults.json failed; refusing to overwrite."
          )
        }
      }
    }
  }

  /// Remove the persisted build info (bundleId, appPath, buildScheme) for
  /// `project` only. Other projects' records are untouched.
  public func clearBuildInfo(forProject project: String) {
    guard let key = Self.validCanonicalKey(project) else {
      Log.debug(
        "DefaultsStore.clearBuildInfo: rejecting invalid project key '\(project)'")
      return
    }
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
    withFileLock(.exclusive) { _ in
      guard case .envelope(var envelope) = readEnvelopeFromDisk(),
        var record = envelope.projects[key]
      else {
        return
      }
      record.bundleId = nil
      record.appPath = nil
      record.buildScheme = nil
      if record.isEmpty {
        envelope.projects.removeValue(forKey: key)
      } else {
        envelope.projects[key] = record
      }
      if envelope.projects.isEmpty {
        removeFileLogging()
      } else {
        writeEnvelope(envelope)
      }
    }
  }

  /// Remove only `project`'s record from the envelope. Other projects survive.
  public func clear(forProject project: String) {
    guard let key = Self.validCanonicalKey(project) else {
      Log.debug("DefaultsStore.clear: rejecting invalid project key '\(project)'")
      return
    }
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
    withFileLock(.exclusive) { _ in
      guard case .envelope(var envelope) = readEnvelopeFromDisk() else { return }
      envelope.projects.removeValue(forKey: key)
      if envelope.projects.isEmpty {
        removeFileLogging()
      } else {
        writeEnvelope(envelope)
      }
    }
  }

  /// Remove the entire defaults file (every project's record). Equivalent to
  /// the historical `clear()` behavior.
  public func clearAll() {
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
    withFileLock(.exclusive) { _ in
      removeFileLogging()
    }
  }

  // MARK: - Legacy compatibility shims (no project context)

  /// Legacy single-record load. Returns the first record in the envelope when
  /// exactly one project is stored, else nil. Preferred call site is
  /// `load(forProject:)`; this exists for code paths that need a peek without
  /// having resolved a project yet (currently none in production code).
  public func load() -> PersistedDefaults? {
    guard let envelope = loadEnvelope() else { return nil }
    guard envelope.projects.count == 1, let only = envelope.projects.first else { return nil }
    return filteringStalePaths(only.value)
  }

  /// Legacy whole-file delete preserved for callers that genuinely want to
  /// nuke everything. Use `clear(forProject:)` for the per-project semantics.
  public func clear() { clearAll() }

  // MARK: - Envelope read/write

  /// Result of a single read attempt against `defaults.json`.
  ///
  /// `unrecognized` lets write-side callers tell the difference between
  /// "file doesn't exist / decoded cleanly as v2" (safe to overwrite) and
  /// "file exists but we can't decode it" (must back up before overwriting,
  /// or refuse the write entirely — see P2).
  enum ReadResult {
    case envelope(StoredEnvelope)
    case empty
    case unrecognized
  }

  /// Two-phase load with promotion: a shared-lock read decides whether the
  /// file is already v2 (fast path) or needs v1 migration. If v1, drop the
  /// shared lock, re-acquire `.exclusive`, re-read (in case another process
  /// migrated it in the gap), then migrate+write under the exclusive hold.
  ///
  /// This is the P1 fix: writing under a shared lock allows concurrent
  /// readers to both attempt the migration and race the rewrite.
  func loadEnvelope() -> StoredEnvelope? {
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }

    // Phase 1: shared lock, read-only decode. `withFileLock` returns `T?`
    // (nil only when the lock itself fails), so flat-map the inner result.
    let firstRead: RawReadResult? = withFileLock(.shared) { _ in readRawEnvelopeFromDisk() }
    guard let firstRead else { return nil }

    switch firstRead {
    case .envelope(let env):
      return env
    case .unrecognized, .empty:
      // `empty` happens only when the file disappeared between exists() and
      // open(); `unrecognized` means a v3+/garbled shape. Both are "no v2
      // envelope to return" — callers should treat as nil from a read-side
      // perspective. (Save paths re-check via readEnvelopeFromDisk and act on
      // the .unrecognized case explicitly.)
      return nil
    case .needsV1Migration(let v1, let v1Project):
      // Phase 2: drop the shared lock and re-acquire `.exclusive`. We must
      // re-read once we hold it — the file may have been migrated by another
      // process in the gap between the two acquisitions.
      let migrated: StoredEnvelope? = withFileLock(.exclusive) { _ in
        if case .envelope(let env) = readEnvelopeFromDisk() {
          // Another process migrated it while we were promoting — no-op.
          return env
        }
        let key = Self.canonicalKey(v1Project)
        guard key != Self.invalidCanonicalKey else {
          Log.warn(
            "DefaultsStore: v1 project '\(v1Project)' canonicalized to invalid key; discarding."
          )
          return Optional<StoredEnvelope>.none
        }
        var migratedRecord = v1
        migratedRecord.project = key
        var envelope = StoredEnvelope.empty
        envelope.projects[key] = migratedRecord
        writeEnvelope(envelope)
        return envelope
      }.flatMap { $0 }
      return migrated
    }
  }

  /// Phase-1 read variant: returns the same v2 envelope a normal read would,
  /// but flags v1-needing-migration separately so the caller can drop the
  /// shared lock and re-acquire exclusively. Caller must hold *some* lock.
  private enum RawReadResult {
    case envelope(StoredEnvelope)
    case needsV1Migration(PersistedDefaults, v1Project: String)
    case unrecognized
    case empty
  }

  private func readRawEnvelopeFromDisk() -> RawReadResult {
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return .empty }
    let data: Data
    do {
      data = try Data(contentsOf: fileURL)
    } catch {
      Log.warn(
        "Failed to read defaults from \(fileURL.path): \(error.localizedDescription)."
      )
      return .unrecognized
    }

    let decoder = JSONDecoder()
    if let envelope = try? decoder.decode(StoredEnvelope.self, from: data), envelope.version == 2 {
      return .envelope(envelope)
    }

    // v1 fallback: require a non-nil `project` field. `PersistedDefaults` has
    // every field optional, so `{}` and forward-version v3 shapes would
    // otherwise decode successfully and invite a clobber. (P2)
    if let v1 = try? decoder.decode(PersistedDefaults.self, from: data),
      let v1Project = v1.project, !v1Project.isEmpty
    {
      return .needsV1Migration(v1, v1Project: v1Project)
    }

    Log.warn(
      "defaults.json at \(fileURL.path) is not recognizable v1 or v2; treating as unrecognized."
    )
    return .unrecognized
  }

  /// Decode the file under an *exclusive* lock, returning a structured result.
  /// Used by save / clear paths that may need to act on the `.unrecognized`
  /// case (back up the file rather than blindly overwrite). Caller must hold
  /// the exclusive lock.
  private func readEnvelopeFromDisk() -> ReadResult {
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return .empty }
    switch readRawEnvelopeFromDisk() {
    case .envelope(let env): return .envelope(env)
    case .needsV1Migration(let v1, let v1Project):
      // Caller holds the exclusive lock — safe to migrate in place.
      let key = Self.canonicalKey(v1Project)
      guard key != Self.invalidCanonicalKey else {
        Log.warn(
          "DefaultsStore: v1 project '\(v1Project)' canonicalized to invalid key; discarding."
        )
        return .unrecognized
      }
      var migrated = v1
      migrated.project = key
      var envelope = StoredEnvelope.empty
      envelope.projects[key] = migrated
      writeEnvelope(envelope)
      return .envelope(envelope)
    case .unrecognized: return .unrecognized
    case .empty: return .empty
    }
  }

  /// Move the current `defaults.json` to a timestamped `defaults.json.unrecognized-*`
  /// sibling so a forward-version or corrupt file isn't silently lost when a
  /// later save needs to write a fresh envelope. Returns true on success or
  /// when there's nothing to back up (no file).
  private func backupUnrecognizedFile() -> Bool {
    let fm = FileManager.default
    guard fm.fileExists(atPath: fileURL.path) else { return true }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.dateFormat = "yyyyMMdd'T'HHmmss"
    let stamp = formatter.string(from: Date())
    let dest = fileURL.deletingLastPathComponent()
      .appendingPathComponent("defaults.json.unrecognized-\(stamp)", isDirectory: false)
    do {
      // Use copy + remove rather than move so a partial failure leaves the
      // original intact (we'll just refuse the write upstream).
      try fm.copyItem(at: fileURL, to: dest)
      Log.warn(
        "DefaultsStore: backed up unrecognized defaults.json to \(dest.lastPathComponent)"
      )
      return true
    } catch {
      Log.warn(
        "DefaultsStore: failed to back up unrecognized defaults.json: \(error.localizedDescription)"
      )
      return false
    }
  }

  /// Remove the defaults file and log on failure (rather than swallowing via `try?`).
  /// Caller must hold the exclusive lock when applicable.
  private func removeFileLogging() {
    let fm = FileManager.default
    guard fm.fileExists(atPath: fileURL.path) else { return }
    do {
      try fm.removeItem(at: fileURL)
    } catch {
      Log.warn(
        "Failed to remove defaults file at \(fileURL.path): \(error.localizedDescription)")
    }
  }

  /// Encode and atomically write the envelope. Caller must hold the lock.
  private func writeEnvelope(_ envelope: StoredEnvelope) {
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(envelope)
      try data.write(to: fileURL, options: .atomic)
    } catch {
      Log.warn("Failed to save defaults to \(fileURL.path): \(error.localizedDescription)")
    }
  }

  /// Drops `project` and `appPath` when those paths no longer exist on disk so
  /// downstream code falls through to autodetect instead of failing on stale state
  /// (e.g. a `defaults.json` shipped from another machine, or pointing at a now-deleted
  /// build product). `scheme`/`simulator`/`bundleId`/`buildScheme` are not path-shaped
  /// and are kept as-is.
  private func filteringStalePaths(_ defaults: PersistedDefaults) -> PersistedDefaults {
    var out = defaults
    let fm = FileManager.default
    if let p = out.project, !fm.fileExists(atPath: p) {
      Log.debug("DefaultsStore: ignoring stale project path '\(p)' (no such file)")
      out.project = nil
    }
    if let p = out.appPath, !fm.fileExists(atPath: p) {
      Log.debug("DefaultsStore: ignoring stale appPath '\(p)' (no such file)")
      out.appPath = nil
    }
    return out
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

// MARK: - Repo-level config (.xcforge.yaml)

/// Discovers and parses a `.xcforge.yaml` file by walking up from `startDir`
/// toward the repo root (`.git` boundary). Returns repo-scoped defaults or `nil`.
///
/// Repo config is intentionally decoupled from `PersistedDefaults`: it carries
/// repo-only keys (`configuration`, `testPlan`) that must never flow into
/// `~/.xcforge/defaults.json` or named profiles.
public enum RepoConfig {
  static let fileName = ".xcforge.yaml"

  /// Repo-scoped configuration values parsed from `.xcforge.yaml`.
  ///
  /// Distinct from `PersistedDefaults` so that `configuration`/`testPlan`
  /// (repo-only) cannot leak into the persisted/global JSON model or profiles.
  public struct Values: Sendable, Equatable {
    public var project: String?
    public var scheme: String?
    public var simulator: String?
    public var configuration: String?
    public var testPlan: String?
    /// Default test watchdog timeout in seconds, applied when no explicit
    /// `timeoutSeconds` is passed. Overrides the built-in 180s/1800s bimodal.
    public var testTimeout: Int?
    /// When `false`, suppresses the 3-strikes silent promotion of explicit
    /// values to sticky session defaults. Defaults to `true` (legacy behavior)
    /// when the key is omitted.
    public var autoPromote: Bool?

    public init(
      project: String? = nil,
      scheme: String? = nil,
      simulator: String? = nil,
      configuration: String? = nil,
      testPlan: String? = nil,
      testTimeout: Int? = nil,
      autoPromote: Bool? = nil
    ) {
      self.project = project
      self.scheme = scheme
      self.simulator = simulator
      self.configuration = configuration
      self.testPlan = testPlan
      self.testTimeout = testTimeout
      self.autoPromote = autoPromote
    }

    /// True when every field is nil (nothing to apply).
    public var isEmpty: Bool {
      project == nil && scheme == nil && simulator == nil && configuration == nil
        && testPlan == nil && testTimeout == nil && autoPromote == nil
    }
  }

  /// Discover `.xcforge.yaml` by walking up from `startDir` to the repo root.
  /// Returns parsed values with relative `project` path resolved, or `nil`.
  public static func discover(from startDir: String) -> Values? {
    guard !startDir.isEmpty else { return nil }
    let fm = FileManager.default
    let repoRoot = RepoRoot.discover(from: startDir)
    var dir = startDir
    while dir != "/" {
      let candidate = (dir as NSString).appendingPathComponent(fileName)
      if fm.fileExists(atPath: candidate) {
        return load(from: candidate, configDir: dir)
      }
      if let repoRoot, dir == repoRoot {
        break
      }
      dir = (dir as NSString).deletingLastPathComponent
    }
    return nil
  }

  /// Parse flat YAML (`key: value` lines, `#` comments, blank lines skipped).
  /// Resolves relative `project` paths against `configDir`.
  static func load(from path: String, configDir: String) -> Values? {
    let contents: String
    do {
      contents = try String(contentsOfFile: path, encoding: .utf8)
    } catch {
      Log.warn("Failed to read \(RepoConfig.fileName) at \(path): \(error.localizedDescription)")
      return nil
    }

    var dict: [String: String] = [:]
    let normalized = contents.replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
    for line in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
      guard let colonIdx = trimmed.firstIndex(of: ":") else { continue }
      let key = trimmed[trimmed.startIndex..<colonIdx].trimmingCharacters(in: .whitespaces)
      let value = trimmed[trimmed.index(after: colonIdx)...].trimmingCharacters(in: .whitespaces)
      if !key.isEmpty && !value.isEmpty {
        dict[key] = value
      }
    }

    if dict.isEmpty { return nil }

    let allowedKeys: Set<String> = [
      "project", "scheme", "simulator", "configuration", "testPlan",
      "testTimeout", "autoPromote",
    ]
    for key in dict.keys where !allowedKeys.contains(key) {
      Log.warn("\(RepoConfig.fileName): ignoring unknown key '\(key)'")
    }

    // Resolve relative project path against config file directory
    var project = dict["project"]
    if let p = project, !p.hasPrefix("/") {
      let resolved = (configDir as NSString).appendingPathComponent(p)
      let normalized = (resolved as NSString).standardizingPath
      if FileManager.default.fileExists(atPath: normalized) {
        project = normalized
      } else {
        Log.warn(
          "\(RepoConfig.fileName): project path '\(p)' resolved to '\(normalized)' which does not exist — ignoring"
        )
        project = nil
      }
    }

    // testTimeout: positive integer seconds. Anything non-numeric or <= 0
    // is warned + dropped, so a typo never silently becomes a 0-second watchdog.
    var testTimeout: Int?
    if let raw = dict["testTimeout"] {
      if let parsed = Int(raw), parsed > 0 {
        testTimeout = parsed
      } else {
        Log.warn(
          "\(RepoConfig.fileName): ignoring non-numeric or non-positive testTimeout '\(raw)'")
      }
    }

    // autoPromote: strict true/false. Other values warn + drop.
    var autoPromote: Bool?
    if let raw = dict["autoPromote"] {
      switch raw.lowercased() {
      case "true": autoPromote = true
      case "false": autoPromote = false
      default:
        Log.warn(
          "\(RepoConfig.fileName): ignoring non-boolean autoPromote '\(raw)' (expected true/false)")
      }
    }

    let result = Values(
      project: project,
      scheme: dict["scheme"],
      simulator: dict["simulator"],
      configuration: dict["configuration"],
      testPlan: dict["testPlan"],
      testTimeout: testTimeout,
      autoPromote: autoPromote
    )
    return result.isEmpty ? nil : result
  }

  /// Build a documented `.xcforge.yaml` body with commented keys.
  ///
  /// Detected values are pre-filled and active; keys with no detected value are
  /// emitted as commented placeholders so the file is valid as written.
  public static func scaffold(
    project: String?,
    scheme: String?,
    simulator: String?
  ) -> String {
    func entry(_ key: String, _ value: String?, _ comment: String) -> String {
      // The flat parser splits on the first ":" and has no quoting. A value
      // containing ":" or a newline would not round-trip, so emit it as a
      // commented placeholder instead of writing a silently-broken file.
      if let value, !value.isEmpty, !value.contains(":"), !value.contains("\n") {
        return "# \(comment)\n\(key): \(value)\n"
      }
      return "# \(comment)\n# \(key):\n"
    }

    var lines = [
      "# .xcforge.yaml — repo-scoped defaults for xcforge.",
      "#",
      "# Committed team config for THIS repo. It outranks the machine-global",
      "# ~/.xcforge/defaults.json (precedence: explicit arg > in-session",
      "# set_defaults > .xcforge.yaml > persisted defaults > auto-detect).",
      "#",
      "# Flat `key: value` syntax only — no nesting, no quoting needed.",
      "# Lines starting with '#' are comments. Unknown keys are ignored.",
      "",
    ]
    lines.append(
      entry(
        "project", project,
        "Path to .xcodeproj/.xcworkspace. Relative paths resolve from this file's directory."
      ).trimmingCharacters(in: .newlines))
    lines.append("")
    lines.append(
      entry("scheme", scheme, "Xcode scheme to build/test.").trimmingCharacters(in: .newlines))
    lines.append("")
    lines.append(
      entry("simulator", simulator, "Simulator name or UDID (e.g. iPhone 16 Pro).")
        .trimmingCharacters(in: .newlines))
    lines.append("")
    lines.append(
      entry("configuration", nil, "Build configuration (Debug/Release). Default: Debug.")
        .trimmingCharacters(in: .newlines))
    lines.append("")
    lines.append(
      entry("testPlan", nil, "Default .xctestplan name for test runs.")
        .trimmingCharacters(in: .newlines))
    lines.append("")
    lines.append(
      entry(
        "testTimeout", nil,
        "Default test watchdog timeout in seconds (e.g. 600). Overrides 180s/1800s bimodal."
      ).trimmingCharacters(in: .newlines))
    lines.append("")
    lines.append(
      entry(
        "autoPromote", nil,
        "Set to false to disable 3-strikes auto-promotion of explicit values. Default: true."
      ).trimmingCharacters(in: .newlines))
    return lines.joined(separator: "\n") + "\n"
  }
}

// MARK: - Best-effort detection for `xcforge init`

/// Public, non-throwing detection facade over the internal `AutoDetect`.
///
/// `xcforge init` pre-fills `.xcforge.yaml` with whatever can be detected and
/// leaves the rest as commented placeholders — so detection must never throw
/// or block the scaffold. Ambiguous/missing results simply return `nil`.
public enum InitDetect {
  /// Detected project/scheme/simulator (any may be nil when ambiguous/absent).
  public struct Result: Sendable {
    public let project: String?
    public let scheme: String?
    public let simulator: String?
  }

  /// Best-effort detection rooted at `startDir`. Never throws.
  public static func detect(startDir: String) async -> Result {
    let project = try? await AutoDetect.project()
    var scheme: String?
    if let project {
      scheme = try? await AutoDetect.scheme(project: project)
    }
    let simulator = try? await AutoDetect.simulator()
    return Result(project: project, scheme: scheme, simulator: simulator)
  }
}

/// Codable representation of persisted workflow defaults.
public struct PersistedDefaults: Codable, Sendable, Equatable {
  public var project: String?
  public var scheme: String?
  public var simulator: String?
  public var bundleId: String?
  public var appPath: String?
  public var buildScheme: String?

  public init(
    project: String? = nil,
    scheme: String? = nil,
    simulator: String? = nil,
    bundleId: String? = nil,
    appPath: String? = nil,
    buildScheme: String? = nil
  ) {
    self.project = project
    self.scheme = scheme
    self.simulator = simulator
    self.bundleId = bundleId
    self.appPath = appPath
    self.buildScheme = buildScheme
  }

  /// True when all fields are nil (nothing to persist).
  public var isEmpty: Bool {
    project == nil && scheme == nil && simulator == nil && bundleId == nil && appPath == nil
      && buildScheme == nil
  }

  /// Returns a new value where non-nil fields from `other` overwrite `self`,
  /// and nil fields in `other` preserve `self`'s values.
  func merging(_ other: PersistedDefaults) -> PersistedDefaults {
    PersistedDefaults(
      project: other.project ?? project,
      scheme: other.scheme ?? scheme,
      simulator: other.simulator ?? simulator,
      bundleId: other.bundleId ?? bundleId,
      appPath: other.appPath ?? appPath,
      buildScheme: other.buildScheme ?? buildScheme
    )
  }
}

// MARK: - v2 on-disk envelope

/// On-disk shape of `defaults.json` for schema version 2. Each project's
/// `PersistedDefaults` record is stored under its canonical path key so two
/// apps built from the same machine cannot stomp on each other's build info.
///
/// Internal by design: external code goes through `DefaultsStore`'s
/// per-project APIs. Test code reaches in via `@testable import`.
struct StoredEnvelope: Codable, Equatable {
  var version: Int
  var projects: [String: PersistedDefaults]

  static let empty = StoredEnvelope(version: 2, projects: [:])
}

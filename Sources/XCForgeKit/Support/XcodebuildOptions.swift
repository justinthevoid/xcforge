import Foundation
import MCP

/// Per-invocation knobs applied to every `xcodebuild` call xcforge makes.
///
/// Values come from three layers, most specific first:
/// 1. The task-local `current` value, set by a CLI flag or MCP argument for one call.
/// 2. Environment variables (`XCFORGE_DERIVED_DATA_PATH`, `XCFORGE_BUILD_LOCK`, ...).
/// 3. `.xcforge.yaml` keys (`derivedDataPath`, `buildLock`, `artifactDir`, `minFreeGB`).
///
/// Every field is optional: with nothing set, xcforge behaves exactly as before.
public struct XcodebuildOptions: Sendable, Equatable {
  /// Passed as `-derivedDataPath` to every build/test action.
  public var derivedDataPath: String?
  /// Exact `-resultBundlePath` for the final phase of a build or test run.
  public var resultBundlePath: String?
  /// Extra arguments inserted before the xcodebuild action (flags, `KEY=VALUE` settings).
  public var extraArgs: [String]
  /// File to `flock` around every xcodebuild call. Same lock as macOS `lockf(1)`.
  public var lockPath: String?
  /// Maximum seconds to wait in the lock queue before giving up.
  public var lockWaitSeconds: TimeInterval?
  /// Refuse to start a build when the DerivedData volume has less free space than this.
  public var minFreeGB: Double?
  /// Directory for xcforge-generated result bundles and diagnostics.
  public var artifactDir: String?
  /// Kill xcodebuild after this many seconds without any output. 0 disables it.
  public var idleTimeoutSeconds: TimeInterval?
  /// Keep compiling other files and targets after the first error so one run reports them all.
  /// Default: on.
  public var continueAfterErrors: Bool?
  /// When false, drop the flags xcforge adds on its own (`-skipMacroValidation`,
  /// `-parallelizeTargets`, `COMPILATION_CACHE_ENABLE_CACHING=YES`) so the build matches a
  /// plain xcodebuild invocation. Default: true.
  public var defaultFlags: Bool?
  /// `-jobs N` for compiling actions, so a small Mac can cap parallel compiles.
  public var jobs: Int?
  /// Build in the separate diagnostic DerivedData slot and keep going after errors, so
  /// "show me every error" doesn't invalidate the main cache.
  public var allErrors: Bool?
  /// DerivedData used by `allErrors` builds. Default: a per-project folder next to Xcode's.
  public var diagnosticDerivedDataPath: String?

  public init(
    derivedDataPath: String? = nil,
    resultBundlePath: String? = nil,
    extraArgs: [String] = [],
    lockPath: String? = nil,
    lockWaitSeconds: TimeInterval? = nil,
    minFreeGB: Double? = nil,
    artifactDir: String? = nil,
    idleTimeoutSeconds: TimeInterval? = nil,
    continueAfterErrors: Bool? = nil,
    defaultFlags: Bool? = nil,
    jobs: Int? = nil,
    allErrors: Bool? = nil,
    diagnosticDerivedDataPath: String? = nil
  ) {
    self.derivedDataPath = derivedDataPath
    self.resultBundlePath = resultBundlePath
    self.extraArgs = extraArgs
    self.lockPath = lockPath
    self.lockWaitSeconds = lockWaitSeconds
    self.minFreeGB = minFreeGB
    self.artifactDir = artifactDir
    self.idleTimeoutSeconds = idleTimeoutSeconds
    self.continueAfterErrors = continueAfterErrors
    self.defaultFlags = defaultFlags
    self.jobs = jobs
    self.allErrors = allErrors
    self.diagnosticDerivedDataPath = diagnosticDerivedDataPath
  }

  /// Options set for the current call (CLI flags or MCP arguments).
  @TaskLocal public static var current = XcodebuildOptions()

  /// Default wait in the lock queue: one hour.
  public static let defaultLockWaitSeconds: TimeInterval = 3600

  /// Default silence before a build or test xcodebuild is treated as hung: ten minutes.
  /// A cold build that keeps printing is never killed by it.
  public static let defaultIdleTimeoutSeconds: TimeInterval = 600

  /// Merge the task-local value over environment variables over `.xcforge.yaml`.
  public static func effective(
    cwd: String = FileManager.default.currentDirectoryPath,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> XcodebuildOptions {
    let explicit = current
    let repo = RepoConfig.discover(from: cwd)

    func nonEmpty(_ s: String?) -> String? {
      guard let s, !s.isEmpty else { return nil }
      return s
    }

    var merged = XcodebuildOptions()
    merged.derivedDataPath =
      explicit.derivedDataPath ?? nonEmpty(environment["XCFORGE_DERIVED_DATA_PATH"])
      ?? repo?.derivedDataPath
    merged.resultBundlePath = explicit.resultBundlePath
    merged.lockPath =
      explicit.lockPath ?? nonEmpty(environment["XCFORGE_BUILD_LOCK"]) ?? repo?.buildLock
    merged.lockWaitSeconds =
      explicit.lockWaitSeconds ?? environment["XCFORGE_LOCK_WAIT"].flatMap { TimeInterval($0) }
    merged.minFreeGB =
      explicit.minFreeGB ?? environment["XCFORGE_MIN_FREE_GB"].flatMap { Double($0) }
      ?? repo?.minFreeGB
    merged.artifactDir =
      explicit.artifactDir ?? nonEmpty(environment["XCFORGE_ARTIFACT_DIR"]) ?? repo?.artifactDir
    merged.idleTimeoutSeconds =
      explicit.idleTimeoutSeconds ?? environment["XCFORGE_IDLE_TIMEOUT"].flatMap { TimeInterval($0) }
      ?? repo?.idleTimeout
    merged.continueAfterErrors = explicit.continueAfterErrors
    merged.defaultFlags =
      explicit.defaultFlags ?? environment["XCFORGE_DEFAULT_FLAGS"].flatMap(parseBool) ?? repo?.defaultFlags
    merged.extraArgs = explicit.extraArgs
    merged.jobs =
      explicit.jobs ?? environment["XCFORGE_JOBS"].flatMap { Int($0) }.flatMap { $0 > 0 ? $0 : nil } ?? repo?.jobs
    merged.allErrors = explicit.allErrors
    merged.diagnosticDerivedDataPath =
      explicit.diagnosticDerivedDataPath ?? nonEmpty(environment["XCFORGE_DIAGNOSTIC_DERIVED_DATA_PATH"])
      ?? repo?.diagnosticDerivedDataPath
    return merged
  }

  /// Point an `allErrors` build at the diagnostic DerivedData slot, unless this call named a
  /// DerivedData folder itself.
  func withDiagnosticSlot(project: String?) -> XcodebuildOptions {
    guard allErrors == true else { return self }
    var options = self
    options.continueAfterErrors = true
    if Self.current.derivedDataPath == nil {
      options.derivedDataPath = diagnosticDerivedDataPath ?? Self.defaultDiagnosticDerivedDataPath(project: project)
    }
    return options
  }

  /// A snapshot build keeps out of a configured DerivedData folder (`<folder>-snapshot`), so it
  /// never invalidates the main tree's cache. Xcode's default folder already differs by path.
  func forSnapshot(project: String?) -> XcodebuildOptions {
    guard let project, SourceSnapshot.contains(project), Self.current.derivedDataPath == nil,
      let derivedDataPath, !SourceSnapshot.contains(derivedDataPath)
    else { return self }
    var options = self
    options.derivedDataPath = derivedDataPath + "-snapshot"
    return options
  }

  /// `~/Library/Developer/Xcode/DerivedData/xcforge-diagnostic-<Name>-<hash>`: one slot per
  /// project, beside Xcode's own folders, so it stays warm between runs.
  static func defaultDiagnosticDerivedDataPath(project: String?, home: String = NSHomeDirectory()) -> String {
    let path = project ?? FileManager.default.currentDirectoryPath
    let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
    var hash: UInt64 = 5381
    for byte in path.utf8 { hash = (hash &* 33) &+ UInt64(byte) }
    let suffix = String(String(hash, radix: 16).suffix(8))
    return "\(home)/Library/Developer/Xcode/DerivedData/xcforge-diagnostic-\(name)-\(suffix)"
  }

  static func parseBool(_ raw: String) -> Bool? {
    switch raw.lowercased() {
    case "1", "true", "yes", "on": return true
    case "0", "false", "no", "off": return false
    default: return nil
    }
  }

  /// Directory for generated artifacts. Defaults to `/tmp`.
  public static func artifactDirectory() -> String {
    let dir = effective().artifactDir ?? "/tmp"
    if dir != "/tmp" {
      try? FileManager.default.createDirectory(
        atPath: dir, withIntermediateDirectories: true, attributes: nil)
    }
    return dir
  }

  /// A collision-free artifact path: `<dir>/xcf-<prefix>-<seconds>-<pid>-<random>.<ext>`.
  /// Two runs started in the same second (or by two processes) never share a path.
  public static func uniqueArtifactPath(prefix: String, extension ext: String) -> String {
    let ts = Int(Date().timeIntervalSince1970)
    let pid = ProcessInfo.processInfo.processIdentifier
    let rand = UUID().uuidString.prefix(6).lowercased()
    return "\(artifactDirectory())/xcf-\(prefix)-\(ts)-\(pid)-\(rand).\(ext)"
  }

  /// Result bundle path for one phase. When the caller fixed `resultBundlePath`, the
  /// final phases (`build`, `test`, `fail`) use it exactly and earlier phases get a
  /// sibling path, so both bundles survive.
  public static func resultBundlePath(prefix: String) -> String {
    if let fixed = current.resultBundlePath, !fixed.isEmpty {
      let finalPrefixes: Set<String> = ["build", "test", "fail"]
      if finalPrefixes.contains(prefix) { return fixed }
      let base = fixed.hasSuffix(".xcresult") ? String(fixed.dropLast(".xcresult".count)) : fixed
      return "\(base)-\(prefix).xcresult"
    }
    return uniqueArtifactPath(prefix: prefix, extension: "xcresult")
  }

  // MARK: - MCP plumbing

  /// Tools whose xcodebuild calls honour these options. Their schemas advertise the keys.
  public static let mcpToolNames: Set<String> = [
    "build_sim", "build_run_sim", "build_compile", "build_typecheck", "clean",
    "test_sim", "test_failures", "test_coverage", "build_and_diagnose", "build_and_test",
    "list_tests", "bless",
  ]

  /// JSON-schema properties added to each tool in `mcpToolNames`.
  public static let mcpSchemaProperties: [String: Value] = [
    "derivedDataPath": .object([
      "type": .string("string"),
      "description": .string("Passed to xcodebuild as -derivedDataPath. Default: Xcode's shared DerivedData."),
    ]),
    "resultBundlePath": .object([
      "type": .string("string"),
      "description": .string(
        "Exact .xcresult path for the final build or test phase. Replaced if it already exists."),
    ]),
    "xcodebuildArgs": .object([
      "type": .string("array"),
      "items": .object(["type": .string("string")]),
      "description": .string(
        "Extra xcodebuild arguments inserted before the action, e.g. [\"-jobs\", \"6\"] or [\"SWIFT_TREAT_WARNINGS_AS_ERRORS=NO\"]."
      ),
    ]),
    "buildLock": .object([
      "type": .string("string"),
      "description": .string(
        "Lock file to hold while xcodebuild runs. Same flock as macOS lockf(1); waiters queue first-come, first-served."
      ),
    ]),
    "lockWaitSeconds": .object([
      "type": .string("integer"),
      "description": .string("Give up after waiting this long for buildLock. Default: 3600."),
    ]),
    "minFreeGB": .object([
      "type": .string("number"),
      "description": .string(
        "Refuse to build when the DerivedData volume has less free space than this. Default: warn only."),
    ]),
    "idleTimeoutSeconds": .object([
      "type": .string("integer"),
      "description": .string(
        "Kill xcodebuild after this many seconds with no output. Default: 600. 0 disables it."),
    ]),
    "continueAfterErrors": .object([
      "type": .string("boolean"),
      "description": .string(
        "Keep building after the first error so one run reports every error. Default: true."),
    ]),
    "jobs": .object([
      "type": .string("integer"),
      "description": .string("Passed to xcodebuild as -jobs for compiling actions. Default: one per core."),
    ]),
    "allErrors": .object([
      "type": .string("boolean"),
      "description": .string(
        "Build in a separate diagnostic DerivedData slot and report every error, without invalidating the main cache."
      ),
    ]),
    "defaultFlags": .object([
      "type": .string("boolean"),
      "description": .string(
        "Set false to drop the flags xcforge adds (-skipMacroValidation, -parallelizeTargets, COMPILATION_CACHE_ENABLE_CACHING=YES). Default: true."
      ),
    ]),
  ]

  /// Parse the option keys out of an MCP argument dictionary.
  public static func fromMCPArguments(_ args: [String: Value]?) -> XcodebuildOptions {
    guard let args else { return XcodebuildOptions() }
    func number(_ v: Value?) -> Double? {
      guard let v else { return nil }
      if let d = v.doubleValue { return d }
      if let i = v.intValue { return Double(i) }
      if let s = v.stringValue { return Double(s) }
      return nil
    }
    let extra = args["xcodebuildArgs"]?.arrayValue?.compactMap { $0.stringValue } ?? []
    return XcodebuildOptions(
      derivedDataPath: args["derivedDataPath"]?.stringValue,
      resultBundlePath: args["resultBundlePath"]?.stringValue,
      extraArgs: extra,
      lockPath: args["buildLock"]?.stringValue,
      lockWaitSeconds: number(args["lockWaitSeconds"]),
      minFreeGB: number(args["minFreeGB"]),
      artifactDir: nil,
      idleTimeoutSeconds: number(args["idleTimeoutSeconds"]),
      continueAfterErrors: args["continueAfterErrors"]?.boolValue,
      defaultFlags: args["defaultFlags"]?.boolValue,
      jobs: number(args["jobs"]).map { Int($0) },
      allErrors: args["allErrors"]?.boolValue
    )
  }

  /// Return `tool` with the option properties merged into its input schema.
  static func augment(_ tool: Tool) -> Tool {
    guard mcpToolNames.contains(tool.name),
      case .object(var schema) = tool.inputSchema
    else { return tool }
    var properties = schema["properties"]?.objectValue ?? [:]
    for (key, value) in mcpSchemaProperties where properties[key] == nil {
      properties[key] = value
    }
    schema["properties"] = .object(properties)
    return Tool(
      name: tool.name,
      title: tool.title,
      description: tool.description,
      inputSchema: .object(schema),
      annotations: tool.annotations,
      outputSchema: tool.outputSchema,
      icons: tool.icons,
      _meta: tool._meta
    )
  }
}

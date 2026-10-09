import Foundation

/// Remembers the result bundle of the most recent build and test run per project, so
/// `build diagnose`, `test failures` and `test coverage` read this project's last run
/// instead of the newest bundle any session left in /tmp.
///
/// One small JSON file per project under `~/.xcforge/last-results/` (or
/// `XCFORGE_LAST_RESULTS_DIR`). Writes are best-effort and never fail a build.
public enum LastResultStore {
  public enum Kind: String, Codable, Sendable {
    case build
    case test
  }

  public struct Record: Codable, Sendable, Equatable {
    public var build: String?
    public var test: String?
    public var updatedAt: Date
    /// When build-for-testing last succeeded, and for which scheme, configuration and platform.
    public var testBuiltAt: Date?
    public var testBuildKey: String?
    /// The test targets that build covered; nil when it built every target in the scheme or plan.
    public var testBuildTargets: [String]?
  }

  static func directory() -> String {
    if let override = ProcessInfo.processInfo.environment["XCFORGE_LAST_RESULTS_DIR"],
      !override.isEmpty
    {
      return (override as NSString).expandingTildeInPath
    }
    return NSHomeDirectory() + "/.xcforge/last-results"
  }

  /// The project as an absolute path with symlinks resolved, so `MyApp.xcodeproj` passed from
  /// two worktrees gets two records, and one project reached two ways gets one.
  static func canonicalProject(_ project: String, cwd: String = FileManager.default.currentDirectoryPath) -> String {
    let expanded = (project as NSString).expandingTildeInPath
    let absolute = expanded.hasPrefix("/") ? expanded : (cwd as NSString).appendingPathComponent(expanded)
    return ((absolute as NSString).standardizingPath as NSString).resolvingSymlinksInPath
  }

  static func fileName(for project: String) -> String {
    let canonical = canonicalProject(project)
    let mapped = canonical.map { ch -> Character in
      ch.isLetter || ch.isNumber || ch == "." || ch == "-" ? ch : "_"
    }
    var safe = String(mapped)
    // File names stop at 255 bytes; keep the end of a long path and a hash of all of it.
    if safe.utf8.count > 200 {
      var hash: UInt64 = 5381
      for byte in canonical.utf8 { hash = (hash &* 33) &+ UInt64(byte) }
      safe = String(safe.suffix(160)) + "-" + String(hash, radix: 16)
    }
    return safe + ".json"
  }

  static func filePath(for project: String) -> String {
    (directory() as NSString).appendingPathComponent(fileName(for: project))
  }

  /// Record `bundlePath` as the latest result of `kind` for `project`.
  public static func record(project: String, kind: Kind, bundlePath: String, now: Date = Date()) {
    update(project: project, now: now) { record in
      switch kind {
      case .build: record.build = bundlePath
      case .test: record.test = bundlePath
      }
      record.updatedAt = now
    }
  }

  /// Read, change and write a project's record under an exclusive lock, so two processes
  /// finishing at once don't drop one another's update.
  private static func update(project: String, now: Date, _ change: (inout Record) -> Void) {
    let path = filePath(for: project)
    try? FileManager.default.createDirectory(
      atPath: directory(), withIntermediateDirectories: true, attributes: nil)
    let fd = open(path + ".lock", O_CREAT | O_RDWR, 0o644)
    if fd >= 0 { flock(fd, LOCK_EX) }
    defer {
      if fd >= 0 {
        flock(fd, LOCK_UN)
        close(fd)
      }
    }
    var record = load(path) ?? Record(build: nil, test: nil, updatedAt: now)
    change(&record)
    save(record, to: path)
  }

  /// What a test build depends on besides the sources and the test targets.
  static func testBuildKey(
    scheme: String, configuration: String, coverage: Bool, physicalDevice: Bool, testPlan: String? = nil
  ) -> String {
    [
      scheme, configuration, coverage ? "coverage" : "", physicalDevice ? "device" : "simulator",
      testPlan ?? "",
    ]
    .joined(separator: "|")
  }

  /// Note that build-for-testing just succeeded for `project` with `key`, covering `targets`
  /// (nil: every test target).
  static func recordTestBuild(project: String, key: String, targets: [String]? = nil, now: Date = Date()) {
    update(project: project, now: now) { record in
      record.testBuiltAt = now
      record.testBuildKey = key
      record.testBuildTargets = targets?.sorted()
    }
  }

  /// True when the last successful build-for-testing for `project` used `key`, built every
  /// target in `targets` (nil: needs every target), and nothing under `sourceRoot` changed
  /// after it, so its products can be tested as they are.
  static func testBuildIsCurrent(
    project: String, key: String, targets: [String]? = nil, sourceRoot: String
  ) -> Bool {
    guard let record = load(filePath(for: project)), record.testBuildKey == key,
      let builtAt = record.testBuiltAt
    else { return false }
    if let built = record.testBuildTargets {
      guard let targets, Set(targets).isSubset(of: Set(built)) else { return false }
    }
    return !SourceChanges.anyModified(under: sourceRoot, after: builtAt)
  }

  private static func save(_ record: Record, to path: String) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    guard let data = try? encoder.encode(record) else { return }
    try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
  }

  /// The latest recorded bundle of `kind` for `project`, if it still exists on disk.
  public static func latest(project: String, kind: Kind) -> String? {
    guard let record = load(filePath(for: project)) else { return nil }
    let path: String?
    switch kind {
    case .build: path = record.build
    case .test: path = record.test
    }
    guard let path, FileManager.default.fileExists(atPath: path) else { return nil }
    return path
  }

  private static func load(_ path: String) -> Record? {
    guard let data = FileManager.default.contents(atPath: path) else { return nil }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try? decoder.decode(Record.self, from: data)
  }

  /// Record the result bundle named in an xcodebuild argument list, if any.
  ///
  /// A failed build-for-testing counts as the latest test run, so `test failures` reports
  /// its errors instead of an earlier run's failures.
  static func recordFromArguments(_ args: [String], succeeded: Bool = true) {
    guard let bundleIndex = args.firstIndex(of: "-resultBundlePath"), bundleIndex + 1 < args.count
    else { return }
    let bundle = args[bundleIndex + 1]
    let projectIndex = args.firstIndex(of: "-workspace") ?? args.firstIndex(of: "-project")
    guard let projectIndex, projectIndex + 1 < args.count else { return }
    let project = args[projectIndex + 1]
    let testActions: Set<String> = ["test", "test-without-building"]
    let failedTestBuild = !succeeded && args.contains("build-for-testing")
    let kind: Kind = (failedTestBuild || args.contains { testActions.contains($0) }) ? .test : .build
    record(project: project, kind: kind, bundlePath: bundle)
  }
}

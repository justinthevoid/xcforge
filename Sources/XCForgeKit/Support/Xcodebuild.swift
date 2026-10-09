import Foundation

/// Single entry point for every `xcodebuild` invocation xcforge makes.
///
/// Applies `XcodebuildOptions` (DerivedData path, extra arguments), checks free disk and
/// swap, and holds the shared build lock for the duration of the call when one is set.
public enum Xcodebuild {
  public static let executable = "/usr/bin/xcodebuild"

  /// Actions and modes that accept `-derivedDataPath` and extra build arguments.
  static let actionTokens: Set<String> = [
    "build", "build-for-testing", "test", "test-without-building", "clean", "analyze",
    "archive", "docbuild", "-showBuildSettings", "-enumerate-tests",
  ]

  /// Run xcodebuild with the effective options applied.
  public static func run(
    _ arguments: [String],
    workingDirectory: String? = nil,
    environment: [String: String]? = nil,
    timeout: TimeInterval,
    idleTimeout: TimeInterval? = nil,
    env: Environment
  ) async throws -> ShellResult {
    // Settings come from the .xcforge.yaml next to the project being built, so a build of
    // another worktree doesn't pick up this checkout's DerivedData or lock.
    let configDir = projectDirectory(arguments, workingDirectory: workingDirectory)
    let options = XcodebuildOptions.effective(cwd: configDir ?? env.currentDirectoryPath())
    let args = apply(options, to: arguments)

    // Two tool calls in one server (parallel MCP calls) never run xcodebuild against the same
    // DerivedData at once; the second waits its turn instead of hitting "database is locked".
    var slot: XcodebuildQueue.Ticket?
    if needsLock(args) {
      let key = queueKey(args, workingDirectory: workingDirectory)
      slot = await XcodebuildQueue.shared.enter(key: key)
    }
    defer {
      if let slot {
        Task { await XcodebuildQueue.shared.leave(slot) }
      }
    }

    if needsLock(args) {
      try Preflight.check(options: options)
    }

    var lock: BuildLock.Handle?
    if let lockPath = options.lockPath, needsLock(args) {
      lock = try await BuildLock.acquire(
        path: lockPath, label: "xcodebuild " + summary(args),
        maxWait: options.lockWaitSeconds ?? XcodebuildOptions.defaultLockWaitSeconds)
    }
    defer { lock?.release() }

    // Builds and test runs are killed after a stretch of silence rather than a fixed total,
    // so a slow cold build is never cut off while a hung runner still is.
    let idle =
      idleTimeout ?? options.idleTimeoutSeconds
      ?? (needsLock(args) ? XcodebuildOptions.defaultIdleTimeoutSeconds : nil)
    let result = try await env.shell.run(
      executable, arguments: args, workingDirectory: workingDirectory,
      environment: environment, timeout: timeout,
      idleTimeout: (idle ?? 0) > 0 ? idle : nil, outputLimit: Shell.defaultOutputLimit)
    if result.exitCode != -2 {
      LastResultStore.recordFromArguments(args, succeeded: result.succeeded)
    }
    return result
  }

  /// Folder of the `-project` or `-workspace` argument, made absolute, or nil when neither is given.
  static func projectDirectory(_ args: [String], workingDirectory: String?) -> String? {
    guard let path = projectPath(args, workingDirectory: workingDirectory) else { return nil }
    return (path as NSString).deletingLastPathComponent
  }

  /// Absolute `-project`/`-workspace` path, or nil.
  static func projectPath(_ args: [String], workingDirectory: String?) -> String? {
    for flag in ["-workspace", "-project"] {
      if let i = args.firstIndex(of: flag), i + 1 < args.count {
        let raw = (args[i + 1] as NSString).expandingTildeInPath
        let base = workingDirectory ?? FileManager.default.currentDirectoryPath
        let absolute = raw.hasPrefix("/") ? raw : (base as NSString).appendingPathComponent(raw)
        return (absolute as NSString).standardizingPath
      }
    }
    return nil
  }

  /// What two xcodebuild calls must not share at the same time: the DerivedData folder when
  /// one is given, else the project (whose default DerivedData folder is derived from it).
  static func queueKey(_ args: [String], workingDirectory: String?) -> String {
    if let i = args.firstIndex(of: "-derivedDataPath"), i + 1 < args.count {
      return "dd:" + ((args[i + 1] as NSString).standardizingPath)
    }
    if let project = projectPath(args, workingDirectory: workingDirectory) {
      return "project:" + project
    }
    if let i = args.firstIndex(of: "-xctestrun"), i + 1 < args.count {
      return "xctestrun:" + args[i + 1]
    }
    return "cwd:" + (workingDirectory ?? FileManager.default.currentDirectoryPath)
  }

  /// True for invocations that build or run tests (as opposed to `-list` or `-version`).
  static func isBuildInvocation(_ args: [String]) -> Bool {
    args.contains { actionTokens.contains($0) }
  }

  /// Actions that compile or run tests and therefore take the shared build lock.
  /// `-showBuildSettings` alone does not, so it can run beside a build.
  static let lockingActions: Set<String> = [
    "build", "build-for-testing", "test", "test-without-building", "clean", "analyze",
    "archive", "docbuild",
  ]

  static func needsLock(_ args: [String]) -> Bool {
    args.contains { lockingActions.contains($0) }
  }

  /// Insert `-derivedDataPath` and extra arguments before the first action token.
  /// Arguments the caller already passed are never duplicated.
  static func apply(_ options: XcodebuildOptions, to original: [String]) -> [String] {
    guard isBuildInvocation(original) else { return original }
    let arguments =
      options.defaultFlags == false ? original.filter { !xcforgeDefaultFlags.contains($0) } : original
    var insert: [String] = []
    if let dd = options.derivedDataPath, !dd.isEmpty, !arguments.contains("-derivedDataPath"),
      !arguments.contains("-xctestrun")
    {
      insert += ["-derivedDataPath", dd]
    }
    if options.continueAfterErrors ?? true,
      arguments.contains(where: { compileActions.contains($0) }),
      !arguments.contains(where: { $0.hasPrefix(continueAfterErrorsDefault) })
    {
      insert.append(continueAfterErrorsDefault + "=YES")
    }
    insert += options.extraArgs
    guard !insert.isEmpty else { return arguments }
    let index = arguments.firstIndex { actionTokens.contains($0) } ?? arguments.endIndex
    var result = arguments
    result.insert(contentsOf: insert, at: index)
    return result
  }

  /// Flags xcforge adds to builds on its own. `defaultFlags: false` removes them.
  static let xcforgeDefaultFlags: Set<String> = [
    "-skipMacroValidation", "-parallelizeTargets", "COMPILATION_CACHE_ENABLE_CACHING=YES",
  ]

  /// Xcode user default that keeps the build going after the first error, so every
  /// error in the run is reported instead of only the first target's.
  static let continueAfterErrorsDefault = "-IDEBuildingContinueBuildingAfterErrors"

  /// Actions that compile sources.
  static let compileActions: Set<String> = ["build", "build-for-testing", "test", "analyze"]

  /// How xcforge killed a process, or nil when it exited on its own.
  public enum TimeoutKind: String, Sendable {
    /// No output for the idle limit: the process was hung.
    case idle
    /// The total time limit ran out while the process was still printing.
    case total
  }

  public static func timeoutKind(_ result: ShellResult) -> TimeoutKind? {
    guard result.exitCode == -1 else { return nil }
    return result.stderr.contains("(idle timeout)") ? .idle : .total
  }

  /// One line explaining a timeout and how to raise the limit, or nil.
  public static func timeoutExplanation(_ result: ShellResult) -> String? {
    switch timeoutKind(result) {
    case .idle:
      return result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        + ". Likely hung; raise idleTimeoutSeconds (--idle-timeout) if it was legitimately quiet."
    case .total:
      return result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        + ". It was still producing output; raise timeoutSeconds or pass long."
    case nil:
      return nil
    }
  }

  /// stdout and stderr together. xcodebuild prints compiler diagnostics to stdout.
  public static func combinedOutput(_ result: ShellResult) -> String {
    if result.stdout.isEmpty { return result.stderr }
    if result.stderr.isEmpty { return result.stdout }
    return result.stdout + "\n" + result.stderr
  }

  /// Short description used for lock status: scheme and action.
  static func summary(_ args: [String]) -> String {
    var parts: [String] = []
    if let i = args.firstIndex(of: "-scheme"), i + 1 < args.count {
      parts.append("-scheme \(args[i + 1])")
    }
    parts += args.filter { actionTokens.contains($0) }
    return parts.joined(separator: " ")
  }
}

// MARK: - In-process queue

/// First-come, first-served turns per DerivedData folder within one xcforge process.
///
/// The cross-process build lock is opt-in; this one is always on, because an MCP client can
/// send two build or test calls at once and both would otherwise run on the same DerivedData.
actor XcodebuildQueue {
  static let shared = XcodebuildQueue()

  struct Ticket: Sendable, Hashable {
    let key: String
    let id: UInt64
  }

  private var nextID: UInt64 = 0
  private var holders: [String: UInt64] = [:]
  private var waiters: [String: [(id: UInt64, resume: CheckedContinuation<Void, Never>)]] = [:]

  /// Wait for this key's turn. Returns at once when nobody holds it.
  func enter(key: String) async -> Ticket {
    nextID += 1
    let id = nextID
    if holders[key] == nil {
      holders[key] = id
      return Ticket(key: key, id: id)
    }
    await withCheckedContinuation { continuation in
      waiters[key, default: []].append((id, continuation))
    }
    return Ticket(key: key, id: id)
  }

  /// Hand the key to the next waiter, or free it.
  func leave(_ ticket: Ticket) {
    guard holders[ticket.key] == ticket.id else { return }
    if var queue = waiters[ticket.key], !queue.isEmpty {
      let next = queue.removeFirst()
      waiters[ticket.key] = queue.isEmpty ? nil : queue
      holders[ticket.key] = next.id
      next.resume.resume()
    } else {
      holders[ticket.key] = nil
    }
  }

  /// Number of calls waiting for a key (for tests and status).
  func waiting(for key: String) -> Int { waiters[key]?.count ?? 0 }
}

// MARK: - Preflight

/// Disk and memory checks before a build. Warns by default; refuses only when the
/// caller set `minFreeGB`.
public enum Preflight {
  public struct PreflightError: Error, CustomStringConvertible {
    public let description: String
  }

  /// Below this much free disk xcforge warns even without `minFreeGB`.
  static let warnFreeGB: Double = 5
  /// Above this fraction of swap in use xcforge warns.
  static let warnSwapFraction: Double = 0.85

  static func check(options: XcodebuildOptions) throws {
    let probePath =
      options.derivedDataPath.map { existingAncestor(of: $0) }
      ?? NSHomeDirectory() + "/Library/Developer"
    if let freeGB = freeDiskGB(at: probePath) {
      let rounded = String(format: "%.1f", freeGB)
      if let minimum = options.minFreeGB, freeGB < minimum {
        throw PreflightError(
          description:
            "Only \(rounded) GB free on the volume holding \(probePath); minFreeGB is \(minimum). "
            + "Free disk space (e.g. delete old DerivedData) or lower minFreeGB.")
      }
      if freeGB < warnFreeGB {
        Log.warn("Low disk: \(rounded) GB free on the volume holding \(probePath)")
      }
    }
    if let swap = swapUsage(), swap.total > 0, swap.used / swap.total > warnSwapFraction {
      let used = String(format: "%.1f", swap.used / 1_073_741_824)
      let total = String(format: "%.1f", swap.total / 1_073_741_824)
      Log.warn("Heavy swap: \(used) of \(total) GB in use; builds will be slow")
    }
  }

  /// Walk up to the nearest existing directory so a not-yet-created DerivedData path works.
  static func existingAncestor(of path: String) -> String {
    var current = (path as NSString).expandingTildeInPath
    while !current.isEmpty && current != "/" && !FileManager.default.fileExists(atPath: current) {
      current = (current as NSString).deletingLastPathComponent
    }
    return current.isEmpty ? "/" : current
  }

  static func freeDiskGB(at path: String) -> Double? {
    let url = URL(fileURLWithPath: path)
    if let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
      let bytes = values.volumeAvailableCapacityForImportantUsage
    {
      return Double(bytes) / 1_073_741_824
    }
    if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: path),
      let bytes = attrs[.systemFreeSize] as? NSNumber
    {
      return bytes.doubleValue / 1_073_741_824
    }
    return nil
  }

  /// Swap usage in bytes from `vm.swapusage`, or nil when unavailable.
  static func swapUsage() -> (used: Double, total: Double)? {
    #if canImport(Darwin)
      var usage = xsw_usage()
      var size = MemoryLayout<xsw_usage>.size
      guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return nil }
      return (Double(usage.xsu_used), Double(usage.xsu_total))
    #else
      return nil
    #endif
  }
}

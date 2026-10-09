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
    env: Environment
  ) async throws -> ShellResult {
    let options = XcodebuildOptions.effective(cwd: env.currentDirectoryPath())
    let args = apply(options, to: arguments)

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

    let result = try await env.shell.run(
      executable, arguments: args, workingDirectory: workingDirectory,
      environment: environment, timeout: timeout)
    if result.exitCode != -2 {
      LastResultStore.recordFromArguments(args)
    }
    return result
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
  static func apply(_ options: XcodebuildOptions, to arguments: [String]) -> [String] {
    guard isBuildInvocation(arguments) else { return arguments }
    var insert: [String] = []
    if let dd = options.derivedDataPath, !dd.isEmpty, !arguments.contains("-derivedDataPath"),
      !arguments.contains("-xctestrun")
    {
      insert += ["-derivedDataPath", dd]
    }
    insert += options.extraArgs
    guard !insert.isEmpty else { return arguments }
    let index = arguments.firstIndex { actionTokens.contains($0) } ?? arguments.endIndex
    var result = arguments
    result.insert(contentsOf: insert, at: index)
    return result
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

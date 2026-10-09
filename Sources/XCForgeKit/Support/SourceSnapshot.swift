import Foundation

/// Building from a snapshot of the working tree, so edits other agents make mid-build can't
/// break the build or invalidate its cache.
///
/// The snapshot is a git worktree kept at one path per repository and moved to the current
/// tree before each build (`git stash create` for tracked changes, untracked files copied).
/// Files that didn't change keep their timestamps, and Xcode's DerivedData folder follows the
/// stable path, so snapshot builds stay incremental.
public enum SourceSnapshot {
  public struct Handle: Sendable {
    /// The project or workspace inside the snapshot.
    public let project: String
    /// The snapshot worktree.
    public let worktree: String
    /// The repository the snapshot was taken from.
    public let repoRoot: String
    /// The commit the snapshot holds (the working tree's state as a stash commit, or HEAD).
    public let commit: String
    let lock: BuildLock.Handle

    public func release() { lock.release() }
  }

  public struct SnapshotError: Error, CustomStringConvertible {
    public let description: String
  }

  public static func root(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
    if let override = environment["XCFORGE_SNAPSHOT_DIR"], !override.isEmpty { return override }
    return NSHomeDirectory() + "/.xcforge/snapshots"
  }

  /// One worktree per repository: `<root>/<repo name>-<hash of its path>`.
  static func worktreePath(repoRoot: String, root: String) -> String {
    var hash: UInt64 = 5381
    for byte in repoRoot.utf8 { hash = (hash &* 33) &+ UInt64(byte) }
    let name = (repoRoot as NSString).lastPathComponent
    return (root as NSString).appendingPathComponent("\(name)-\(String(String(hash, radix: 16).suffix(8)))")
  }

  /// `project` with `repoRoot` swapped for `worktree`; nil when it isn't inside the repo.
  static func mapPath(_ project: String, repoRoot: String, worktree: String) -> String? {
    let prefix = repoRoot.hasSuffix("/") ? repoRoot : repoRoot + "/"
    guard project.hasPrefix(prefix) else { return nil }
    return (worktree as NSString).appendingPathComponent(String(project.dropFirst(prefix.count)))
  }

  /// True when `path` is inside a snapshot worktree.
  static func contains(_ path: String) -> Bool {
    let base = root()
    return path.hasPrefix(base.hasSuffix("/") ? base : base + "/")
  }

  /// Move the repository's snapshot worktree to the current working tree and hold its lock
  /// until `release()`. Two builds from the same repo's snapshot take turns.
  public static func prepare(project: String, env: Environment) async throws -> Handle {
    let canonicalProject = (project as NSString).resolvingSymlinksInPath
    let projectDir = (canonicalProject as NSString).deletingLastPathComponent

    func git(_ args: [String], in dir: String, timeout: TimeInterval = 120) async throws -> String {
      let result = try await env.shell.git(args, workingDirectory: dir, timeout: timeout)
      guard result.succeeded else {
        throw SnapshotError(description: "git \(args.joined(separator: " ")) failed: \(result.stderr)")
      }
      return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    let topLevel = try await git(["rev-parse", "--show-toplevel"], in: projectDir)
    let repoRoot = (topLevel as NSString).resolvingSymlinksInPath
    let worktree = worktreePath(repoRoot: repoRoot, root: root())
    guard let mapped = mapPath(canonicalProject, repoRoot: repoRoot, worktree: worktree) else {
      throw SnapshotError(description: "\(project) is not inside the git repository at \(repoRoot)")
    }

    let lock = try await BuildLock.acquire(path: worktree + ".lock", label: "snapshot build", maxWait: 3600)
    do {
      // A stash commit records tracked changes without touching the working tree or stash list.
      var commit = try await git(["stash", "create"], in: repoRoot)
      if commit.isEmpty { commit = try await git(["rev-parse", "HEAD"], in: repoRoot) }

      let fm = FileManager.default
      if fm.fileExists(atPath: (worktree as NSString).appendingPathComponent(".git")) {
        _ = try await git(["checkout", "--force", "--detach", commit], in: worktree, timeout: 300)
        // Drop files untracked in the snapshot; ignored build output stays.
        _ = try await git(["clean", "-fd"], in: worktree)
      } else {
        try? fm.removeItem(atPath: worktree)
        try fm.createDirectory(atPath: root(), withIntermediateDirectories: true)
        _ = try await git(["worktree", "prune"], in: repoRoot)
        _ = try await git(["worktree", "add", "--detach", worktree, commit], in: repoRoot, timeout: 600)
      }

      // New files the agent hasn't added yet are part of what it is building.
      let untracked = try await git(["ls-files", "--others", "--exclude-standard"], in: repoRoot)
      for relative in untracked.split(separator: "\n").map(String.init) where !relative.isEmpty {
        copyIfChanged(
          from: (repoRoot as NSString).appendingPathComponent(relative),
          to: (worktree as NSString).appendingPathComponent(relative))
      }
      return Handle(project: mapped, worktree: worktree, repoRoot: repoRoot, commit: commit, lock: lock)
    } catch {
      lock.release()
      throw error
    }
  }

  /// `value` with every path under `worktree` pointed back at `repoRoot`, so errors name the
  /// files the agent edits, not the snapshot's copies.
  public static func remap<T: Codable>(_ value: T, from worktree: String, to repoRoot: String) -> T {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .withoutEscapingSlashes
    guard let data = try? encoder.encode(value), let text = String(data: data, encoding: .utf8) else { return value }
    let replaced = text.replacingOccurrences(of: worktree + "/", with: repoRoot + "/")
    return (try? JSONDecoder().decode(T.self, from: Data(replaced.utf8))) ?? value
  }

  /// Copy a file unless the destination already has the same bytes, so unchanged files keep
  /// their timestamps and aren't recompiled.
  static func copyIfChanged(from source: String, to destination: String) {
    let fm = FileManager.default
    guard let data = fm.contents(atPath: source) else { return }
    if fm.contents(atPath: destination) == data { return }
    try? fm.createDirectory(
      atPath: (destination as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    try? data.write(to: URL(fileURLWithPath: destination), options: .atomic)
  }
}

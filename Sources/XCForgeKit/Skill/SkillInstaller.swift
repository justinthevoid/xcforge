import Foundation

/// One file of the xcforge agent skill, relative to the skill directory.
public struct SkillFile: Sendable, Equatable {
  public let path: String
  public let contents: String

  public init(path: String, contents: String) {
    self.path = path
    self.contents = contents
  }
}

/// The xcforge skill shipped inside the binary (see `EmbeddedSkill.swift`).
public enum SkillBundle {
  /// Directory name the skill installs under (`<skills dir>/xcforge`).
  public static let name = "xcforge"

  public static var files: [SkillFile] { embeddedFiles }

  public static func file(_ path: String) -> SkillFile? {
    files.first { $0.path == path }
  }
}

/// Where a skill install goes.
public enum SkillScope: String, Sendable, Codable, CaseIterable {
  /// `.claude/skills` at the repo root, shared with everyone who clones it.
  case project
  /// `~/.claude/skills` (or `$CLAUDE_CONFIG_DIR/skills`), for every project on this machine.
  case global
}

/// State of the skill in one skills directory.
public enum SkillInstallState: String, Sendable, Codable {
  /// No `xcforge` directory there.
  case notInstalled = "not_installed"
  /// Matches the skill in this binary.
  case current
  /// Installed by `xcforge skill install`, but from another xcforge version.
  case stale
  /// An `xcforge` directory not written by `xcforge skill install` (hand copy, other installer).
  case unmanaged
}

public struct SkillStatus: Sendable, Codable, Equatable {
  public let scope: String
  public let path: String
  public let state: SkillInstallState
  /// Bundled files that are missing or differ on disk.
  public let changedFiles: [String]
}

public struct SkillInstallResult: Sendable, Codable, Equatable {
  /// `installed`, `updated`, `unchanged`, `would_install`, `would_update` or `refused`.
  public let status: String
  public let path: String
  public let written: [String]
  public let removed: [String]
  public let message: String

  public var succeeded: Bool { status != "refused" }

  public init(status: String, path: String, written: [String] = [], removed: [String] = [], message: String) {
    self.status = status
    self.path = path
    self.written = written
    self.removed = removed
    self.message = message
  }
}

public enum SkillInstallerError: Error, CustomStringConvertible {
  case noHome
  case notManaged(String)

  public var description: String {
    switch self {
    case .noHome:
      return "Could not find the home directory for a global install. Pass --dir instead."
    case .notManaged(let path):
      return "\(path) was not installed by xcforge. Re-run with --force to remove it."
    }
  }
}

/// Writes, checks and removes the xcforge skill in an agent's skills directory.
///
/// An install records the files it wrote in a manifest next to them, so a later install
/// can drop files the new version no longer ships, and a directory someone else put
/// there is never overwritten without `force`.
public enum SkillInstaller {
  public static let manifestName = ".xcforge-skill.json"

  struct Manifest: Codable {
    var installedBy = "xcforge"
    var files: [String]
  }

  // MARK: - Locations

  /// The skills directory (the parent of `xcforge/`) for a scope.
  ///
  /// - `project`: `.claude/skills` at the git repo root containing `cwd`, else `cwd`.
  /// - `global`: `$CLAUDE_CONFIG_DIR/skills` when set, else `~/.claude/skills`.
  public static func skillsDirectory(
    scope: SkillScope,
    cwd: String = FileManager.default.currentDirectoryPath,
    environment: [String: String] = ProcessInfo.processInfo.environment,
    home: String? = NSHomeDirectory()
  ) throws -> String {
    switch scope {
    case .project:
      let root = RepoRoot.discover(from: cwd) ?? cwd
      return (root as NSString).appendingPathComponent(".claude/skills")
    case .global:
      if let configDir = environment["CLAUDE_CONFIG_DIR"], !configDir.isEmpty {
        let expanded = expandTilde(configDir, home: home)
        return (expanded as NSString).appendingPathComponent("skills")
      }
      guard let home, !home.isEmpty else { throw SkillInstallerError.noHome }
      return (home as NSString).appendingPathComponent(".claude/skills")
    }
  }

  static func expandTilde(_ path: String, home: String?) -> String {
    guard let home, path == "~" || path.hasPrefix("~/") else { return path }
    return home + path.dropFirst()
  }

  // MARK: - Status

  public static func status(_ skillsDirectory: String, scope: String, files: [SkillFile]? = nil) -> SkillStatus {
    let files = files ?? SkillBundle.files
    let dir = (skillsDirectory as NSString).appendingPathComponent(SkillBundle.name)
    let fm = FileManager.default
    var isDir: ObjCBool = false
    guard fm.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue else {
      return SkillStatus(scope: scope, path: dir, state: .notInstalled, changedFiles: [])
    }
    let changed = changedFiles(in: dir, files: files)
    let manifest = readManifest(in: dir)
    let state: SkillInstallState
    if manifest == nil {
      state = .unmanaged
    } else if changed.isEmpty && Set(manifest?.files ?? []) == Set(files.map(\.path)) {
      state = .current
    } else {
      state = .stale
    }
    return SkillStatus(scope: scope, path: dir, state: state, changedFiles: changed)
  }

  static func changedFiles(in dir: String, files: [SkillFile]) -> [String] {
    files.compactMap { file in
      let path = (dir as NSString).appendingPathComponent(file.path)
      let onDisk = try? String(contentsOfFile: path, encoding: .utf8)
      return onDisk == file.contents ? nil : file.path
    }
  }

  static func readManifest(in dir: String) -> Manifest? {
    let path = (dir as NSString).appendingPathComponent(manifestName)
    guard let data = FileManager.default.contents(atPath: path) else { return nil }
    return try? JSONDecoder().decode(Manifest.self, from: data)
  }

  // MARK: - Install

  /// Install or refresh the skill in `<skillsDirectory>/xcforge`.
  ///
  /// - `force`: replace an `xcforge` directory that this command did not write.
  /// - `dryRun`: report what would change without touching disk.
  public static func install(
    skillsDirectory: String, files: [SkillFile] = SkillBundle.files, force: Bool = false, dryRun: Bool = false
  ) throws -> SkillInstallResult {
    let fm = FileManager.default
    let dir = (skillsDirectory as NSString).appendingPathComponent(SkillBundle.name)
    let current = status(skillsDirectory, scope: "", files: files)

    if current.state == .current {
      return SkillInstallResult(status: "unchanged", path: dir, message: "Skill at \(dir) is up to date.")
    }
    if current.state == .unmanaged && !force {
      let message = "\(dir) exists but was not installed by xcforge. Re-run with --force to replace it."
      return SkillInstallResult(status: "refused", path: dir, message: message)
    }

    let bundled = Set(files.map(\.path))
    // Only files a previous install recorded are ours to remove.
    let previous = readManifest(in: dir)?.files ?? []
    let stale = previous.filter { !bundled.contains($0) && isSafeRelativePath($0) }.sorted()
    let fresh = current.state == .notInstalled
    var toWrite = current.changedFiles
    if fresh || current.state == .unmanaged {
      toWrite = files.map(\.path)
    }
    let verb = fresh ? "install" : "update"
    let detail = fresh ? "" : " (\(toWrite.count) file(s) changed)"

    if dryRun {
      let message = "Would \(verb) the xcforge skill at \(dir)\(detail)."
      return SkillInstallResult(status: "would_\(verb)", path: dir, written: toWrite, removed: stale, message: message)
    }

    if current.state == .unmanaged {
      try fm.removeItem(atPath: dir)
    }
    for path in stale {
      try? fm.removeItem(atPath: (dir as NSString).appendingPathComponent(path))
    }
    for file in files where toWrite.contains(file.path) {
      let target = (dir as NSString).appendingPathComponent(file.path)
      let parent = (target as NSString).deletingLastPathComponent
      try fm.createDirectory(atPath: parent, withIntermediateDirectories: true)
      try file.contents.write(toFile: target, atomically: true, encoding: .utf8)
    }
    try writeManifest(Manifest(files: files.map(\.path).sorted()), in: dir)

    let done = fresh ? "installed" : "updated"
    let message = "\(fresh ? "Installed" : "Updated") the xcforge skill at \(dir)\(detail)."
    return SkillInstallResult(status: done, path: dir, written: toWrite, removed: stale, message: message)
  }

  static func writeManifest(_ manifest: Manifest, in dir: String) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(manifest)
    let path = (dir as NSString).appendingPathComponent(manifestName)
    try data.write(to: URL(fileURLWithPath: path))
  }

  /// Rejects absolute paths and `..` so a hand-edited manifest can't point outside the skill.
  static func isSafeRelativePath(_ path: String) -> Bool {
    !path.isEmpty && !path.hasPrefix("/") && !path.split(separator: "/").contains("..")
  }

  // MARK: - Uninstall

  /// Remove `<skillsDirectory>/xcforge`. Without `force`, only a directory this command wrote.
  /// Returns the removed path, or nil when nothing was installed.
  public static func uninstall(skillsDirectory: String, force: Bool = false) throws -> String? {
    let dir = (skillsDirectory as NSString).appendingPathComponent(SkillBundle.name)
    let fm = FileManager.default
    guard fm.fileExists(atPath: dir) else { return nil }
    guard force || readManifest(in: dir) != nil else {
      throw SkillInstallerError.notManaged(dir)
    }
    try fm.removeItem(atPath: dir)
    return dir
  }
}

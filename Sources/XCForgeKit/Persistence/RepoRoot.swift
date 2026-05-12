import Foundation

/// Repo root discovery — walks up from a starting directory to the first
/// directory containing a `.git` entry (directory or worktree file). Extracted
/// so the various `.xcforge/*` stores share one boundary rule.
public enum RepoRoot {
  /// Walks up from `startDir` toward `/`, returning the first ancestor that
  /// contains a `.git` entry. Returns `nil` if no `.git` is found before the
  /// filesystem root, or if `startDir` is empty.
  public static func discover(from startDir: String) -> String? {
    guard !startDir.isEmpty else { return nil }
    let fm = FileManager.default
    var dir = startDir
    while dir != "/" {
      let gitPath = (dir as NSString).appendingPathComponent(".git")
      if fm.fileExists(atPath: gitPath) {
        return dir
      }
      dir = (dir as NSString).deletingLastPathComponent
    }
    return nil
  }
}

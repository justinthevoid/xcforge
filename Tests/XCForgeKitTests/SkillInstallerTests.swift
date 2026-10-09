import Foundation
import Testing

@testable import XCForgeKit

@Suite("Skill install: embedded skill and installer", .serialized)
struct SkillInstallerTests {

  private func makeTempDir() -> String {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("xcforge-skill-\(UUID().uuidString)", isDirectory: true)
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.path
  }

  private func read(_ path: String) -> String? {
    try? String(contentsOfFile: path, encoding: .utf8)
  }

  private let sample = [
    SkillFile(path: "SKILL.md", contents: "---\nname: xcforge\n---\nhello\n"),
    SkillFile(path: "references/a.md", contents: "a\n"),
  ]

  // MARK: - Embedded copy

  @Test("embedded skill matches Skills/xcforge (run scripts/embed-skill.py if not)")
  func embeddedMatchesRepo() throws {
    let repoSkill = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("Skills/xcforge").path
    let enumerator = try #require(FileManager.default.enumerator(atPath: repoSkill))
    var onDisk: [String: String] = [:]
    for case let rel as String in enumerator {
      let full = (repoSkill as NSString).appendingPathComponent(rel)
      var isDir: ObjCBool = false
      FileManager.default.fileExists(atPath: full, isDirectory: &isDir)
      if isDir.boolValue || (rel as NSString).lastPathComponent.hasPrefix(".") { continue }
      onDisk[rel] = read(full)
    }
    let embedded = Dictionary(uniqueKeysWithValues: SkillBundle.files.map { ($0.path, $0.contents) })
    #expect(Set(embedded.keys) == Set(onDisk.keys))
    for (path, contents) in onDisk {
      #expect(embedded[path] == contents, "\(path) differs; run python3 scripts/embed-skill.py")
    }
  }

  @Test("embedded skill has SKILL.md with frontmatter naming xcforge")
  func embeddedHasSkillMD() throws {
    let skill = try #require(SkillBundle.file("SKILL.md"))
    #expect(skill.contents.hasPrefix("---\nname: xcforge\n"))
  }

  // MARK: - Locations

  @Test("project scope uses .claude/skills at the git root")
  func projectScopeUsesRepoRoot() throws {
    let root = makeTempDir()
    defer { try? FileManager.default.removeItem(atPath: root) }
    try FileManager.default.createDirectory(atPath: root + "/.git", withIntermediateDirectories: true)
    try FileManager.default.createDirectory(atPath: root + "/App/Sub", withIntermediateDirectories: true)
    let dir = try SkillInstaller.skillsDirectory(scope: .project, cwd: root + "/App/Sub")
    #expect(dir == root + "/.claude/skills")
  }

  @Test("global scope uses ~/.claude/skills, or CLAUDE_CONFIG_DIR when set")
  func globalScope() throws {
    let plain = try SkillInstaller.skillsDirectory(scope: .global, environment: [:], home: "/Users/me")
    #expect(plain == "/Users/me/.claude/skills")
    let env = ["CLAUDE_CONFIG_DIR": "~/cfg"]
    let custom = try SkillInstaller.skillsDirectory(scope: .global, environment: env, home: "/Users/me")
    #expect(custom == "/Users/me/cfg/skills")
  }

  // MARK: - Install / status

  @Test("fresh install writes every file and a manifest; a second run changes nothing")
  func freshInstallThenUnchanged() throws {
    let skills = makeTempDir()
    defer { try? FileManager.default.removeItem(atPath: skills) }

    #expect(SkillInstaller.status(skills, scope: "t", files: sample).state == .notInstalled)
    let first = try SkillInstaller.install(skillsDirectory: skills, files: sample)
    #expect(first.status == "installed")
    #expect(read(skills + "/xcforge/references/a.md") == "a\n")
    #expect(FileManager.default.fileExists(atPath: skills + "/xcforge/" + SkillInstaller.manifestName))
    #expect(SkillInstaller.status(skills, scope: "t", files: sample).state == .current)

    let second = try SkillInstaller.install(skillsDirectory: skills, files: sample)
    #expect(second.status == "unchanged")
    #expect(second.written.isEmpty)
  }

  @Test("a newer skill is stale; install rewrites changed files and drops ones no longer shipped")
  func updateRefreshesAndPrunes() throws {
    let skills = makeTempDir()
    defer { try? FileManager.default.removeItem(atPath: skills) }
    _ = try SkillInstaller.install(skillsDirectory: skills, files: sample)

    let newer = [
      SkillFile(path: "SKILL.md", contents: "---\nname: xcforge\n---\nhello again\n"),
      SkillFile(path: "references/b.md", contents: "b\n"),
    ]
    let status = SkillInstaller.status(skills, scope: "t", files: newer)
    #expect(status.state == .stale)
    #expect(Set(status.changedFiles) == ["SKILL.md", "references/b.md"])

    let result = try SkillInstaller.install(skillsDirectory: skills, files: newer)
    #expect(result.status == "updated")
    #expect(result.removed == ["references/a.md"])
    #expect(!FileManager.default.fileExists(atPath: skills + "/xcforge/references/a.md"))
    #expect(read(skills + "/xcforge/SKILL.md") == newer[0].contents)
    #expect(SkillInstaller.status(skills, scope: "t", files: newer).state == .current)
  }

  @Test("dry run reports changes without writing")
  func dryRunWritesNothing() throws {
    let skills = makeTempDir()
    defer { try? FileManager.default.removeItem(atPath: skills) }
    let result = try SkillInstaller.install(skillsDirectory: skills, files: sample, dryRun: true)
    #expect(result.status == "would_install")
    #expect(result.written.count == 2)
    #expect(!FileManager.default.fileExists(atPath: skills + "/xcforge"))
  }

  @Test("a directory xcforge did not write is left alone unless forced")
  func unmanagedNeedsForce() throws {
    let skills = makeTempDir()
    defer { try? FileManager.default.removeItem(atPath: skills) }
    try FileManager.default.createDirectory(atPath: skills + "/xcforge", withIntermediateDirectories: true)
    try "mine\n".write(toFile: skills + "/xcforge/SKILL.md", atomically: true, encoding: .utf8)
    try "old\n".write(toFile: skills + "/xcforge/extra.md", atomically: true, encoding: .utf8)

    #expect(SkillInstaller.status(skills, scope: "t", files: sample).state == .unmanaged)
    let refused = try SkillInstaller.install(skillsDirectory: skills, files: sample)
    #expect(refused.status == "refused")
    #expect(!refused.succeeded)
    #expect(read(skills + "/xcforge/SKILL.md") == "mine\n")
    #expect(throws: SkillInstallerError.self) { try SkillInstaller.uninstall(skillsDirectory: skills) }

    let forced = try SkillInstaller.install(skillsDirectory: skills, files: sample, force: true)
    #expect(forced.status == "updated")
    #expect(read(skills + "/xcforge/SKILL.md") == sample[0].contents)
    #expect(!FileManager.default.fileExists(atPath: skills + "/xcforge/extra.md"))
  }

  @Test("uninstall removes an installed skill and reports nothing when absent")
  func uninstall() throws {
    let skills = makeTempDir()
    defer { try? FileManager.default.removeItem(atPath: skills) }
    #expect(try SkillInstaller.uninstall(skillsDirectory: skills) == nil)
    _ = try SkillInstaller.install(skillsDirectory: skills, files: sample)
    #expect(try SkillInstaller.uninstall(skillsDirectory: skills) == skills + "/xcforge")
    #expect(!FileManager.default.fileExists(atPath: skills + "/xcforge"))
  }

  @Test("manifest paths outside the skill directory are never removed")
  func unsafeManifestPaths() {
    #expect(SkillInstaller.isSafeRelativePath("references/a.md"))
    #expect(!SkillInstaller.isSafeRelativePath("../../etc/passwd"))
    #expect(!SkillInstaller.isSafeRelativePath("/etc/passwd"))
    #expect(!SkillInstaller.isSafeRelativePath(""))
  }
}

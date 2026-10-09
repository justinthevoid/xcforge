import ArgumentParser
import Foundation
import XCForgeKit

/// `xcforge skill` — put the xcforge agent skill where coding agents look for skills.
struct Skill: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "skill",
    abstract: "Install, check or print the xcforge agent skill (the tool reference agents load).",
    subcommands: [SkillInstall.self, SkillStatusCommand.self, SkillUninstall.self, SkillShow.self],
    defaultSubcommand: SkillStatusCommand.self
  )
}

/// Where to put the skill: the project's `.claude/skills` (default), the user's, or any skills directory.
struct SkillLocationOptions: ParsableArguments {
  @Flag(help: "Use the user's Claude Code skills directory (~/.claude/skills) instead of the project's.")
  var global = false

  @Option(help: "Any other skills directory, e.g. another agent's. The skill goes in <dir>/xcforge.")
  var dir: String?

  func skillsDirectory() throws -> (scope: String, path: String) {
    if let dir {
      let expanded = (dir as NSString).expandingTildeInPath
      let absolute = URL(fileURLWithPath: expanded).standardizedFileURL.path
      return ("custom", absolute)
    }
    let scope: SkillScope = global ? .global : .project
    return (scope.rawValue, try SkillInstaller.skillsDirectory(scope: scope))
  }

  func validate() throws {
    if global && dir != nil {
      throw ValidationError("Pass either --global or --dir, not both.")
    }
  }
}

struct SkillInstall: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "install",
    abstract: "Write the xcforge skill into the project's or your Claude Code skills directory.",
    discussion: """
      Without flags the skill goes in .claude/skills/xcforge at the git repo root, so everyone \
      who clones the repo gets it. --global writes ~/.claude/skills/xcforge (or \
      $CLAUDE_CONFIG_DIR/skills/xcforge) for every project on this Mac. Re-run after upgrading \
      xcforge to refresh it; files that did not change are left alone.
      """
  )

  @OptionGroup var location: SkillLocationOptions

  @Flag(help: "Replace an existing xcforge skill directory that this command did not write.")
  var force = false

  @Flag(name: .customLong("dry-run"), help: "Show what would change without writing anything.")
  var dryRun = false

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    let (_, skillsDir) = try location.skillsDirectory()
    let result: SkillInstallResult
    do {
      result = try SkillInstaller.install(skillsDirectory: skillsDir, force: force, dryRun: dryRun)
    } catch {
      try rethrowOrJSONError(error, json: shouldOutputJSON(flag: json))
      return
    }
    if shouldOutputJSON(flag: json) {
      print(try WorkflowJSONRenderer.renderJSON(result))
    } else {
      print(result.message)
      for path in result.removed { print("  removed \(path)") }
      if result.status == "installed" && !location.global && location.dir == nil {
        print("Commit .claude/skills/xcforge so agents in other checkouts get it too.")
      }
    }
    if !result.succeeded { throw ExitCode.failure }
  }
}

struct SkillStatusCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "status",
    abstract: "Show where the xcforge skill is installed and whether it matches this xcforge version."
  )

  @OptionGroup var location: SkillLocationOptions

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    var targets: [(scope: String, path: String)] = []
    if location.global || location.dir != nil {
      targets.append(try location.skillsDirectory())
    } else {
      // No flag: report both standard locations.
      for scope in SkillScope.allCases {
        if let path = try? SkillInstaller.skillsDirectory(scope: scope) {
          targets.append((scope.rawValue, path))
        }
      }
    }
    let statuses = targets.map { SkillInstaller.status($0.path, scope: $0.scope) }
    if shouldOutputJSON(flag: json) {
      print(try WorkflowJSONRenderer.renderJSON(statuses))
      return
    }
    for status in statuses {
      print("\(status.scope): \(status.state.rawValue)  \(status.path)")
      if status.state == .stale || status.state == .unmanaged, !status.changedFiles.isEmpty {
        print("  differs from this xcforge: \(status.changedFiles.joined(separator: ", "))")
      }
    }
    if statuses.contains(where: { $0.state == .stale }) {
      print("Run `xcforge skill install` (add --global for the user copy) to refresh.")
    }
  }
}

struct SkillUninstall: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "uninstall",
    abstract: "Remove the xcforge skill from the project's or your skills directory."
  )

  @OptionGroup var location: SkillLocationOptions

  @Flag(help: "Remove the directory even if this command did not install it.")
  var force = false

  mutating func run() async throws {
    let (_, skillsDir) = try location.skillsDirectory()
    do {
      if let removed = try SkillInstaller.uninstall(skillsDirectory: skillsDir, force: force) {
        print("Removed \(removed)")
      } else {
        print("No xcforge skill in \(skillsDir).")
      }
    } catch let error as SkillInstallerError {
      fputs("\(error.description)\n", stderr)
      throw ExitCode.failure
    }
  }
}

struct SkillShow: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "show",
    abstract: "Print a skill file to stdout (SKILL.md by default), for agents without an installed skill."
  )

  @Argument(help: "File inside the skill, e.g. references/test-tools.md.")
  var file = "SKILL.md"

  @Flag(help: "List the skill's files instead.")
  var list = false

  mutating func run() async throws {
    if list {
      SkillBundle.files.forEach { print($0.path) }
      return
    }
    guard let skillFile = SkillBundle.file(file) else {
      let available = SkillBundle.files.map(\.path).joined(separator: "\n  ")
      fputs("No skill file \(file). Available:\n  \(available)\n", stderr)
      throw ExitCode.failure
    }
    print(skillFile.contents, terminator: "")
  }
}

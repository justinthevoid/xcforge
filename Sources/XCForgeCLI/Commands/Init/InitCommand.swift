import ArgumentParser
import Foundation
import XCForgeKit

/// `xcforge init` — scaffold a documented `.xcforge.yaml` at the repo root.
///
/// Repo config is the committed team source of truth for this repo and
/// outranks the machine-global `~/.xcforge/defaults.json`. This command
/// pre-fills detected project/scheme/simulator with explanatory comments.
struct Init: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "init",
    abstract: "Scaffold a documented .xcforge.yaml at the repo root."
  )

  @Flag(help: "Overwrite an existing .xcforge.yaml instead of refusing.")
  var force = false

  mutating func run() async throws {
    let cwd = FileManager.default.currentDirectoryPath
    // Write at the git repo root; fall back to CWD when there is no repo.
    let root = RepoRoot.discover(from: cwd) ?? cwd
    let target = (root as NSString).appendingPathComponent(".xcforge.yaml")

    if FileManager.default.fileExists(atPath: target) && !force {
      fputs(
        "\(target) already exists. Re-run with --force to overwrite.\n", stderr)
      throw ExitCode.failure
    }

    let detected = await InitDetect.detect(startDir: root)
    let body = RepoConfig.scaffold(
      project: detected.project,
      scheme: detected.scheme,
      simulator: detected.simulator
    )

    do {
      try body.write(toFile: target, atomically: true, encoding: .utf8)
    } catch {
      fputs("Failed to write \(target): \(error.localizedDescription)\n", stderr)
      throw ExitCode.failure
    }

    print("Wrote \(target)")
    print(
      "  project:   \(detected.project ?? "(not detected — edit the file)")")
    print("  scheme:    \(detected.scheme ?? "(not detected — edit the file)")")
    print(
      "  simulator: \(detected.simulator ?? "(not detected — edit the file)")")
  }
}

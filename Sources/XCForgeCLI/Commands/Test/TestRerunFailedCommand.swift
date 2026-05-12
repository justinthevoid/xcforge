import ArgumentParser
import Foundation
import XCForgeKit

struct TestRerunFailed: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "rerun-failed",
    abstract:
      "Rerun only the tests that failed in the most recent run (reads .xcforge/last-failures.json)."
  )

  @Option(help: "Path to .xcodeproj or .xcworkspace. Auto-detected if omitted.")
  var project: String?

  @Option(help: "Xcode scheme name. Auto-detected if omitted.")
  var scheme: String?

  @Option(help: "Simulator name or UDID. Auto-detected if omitted.")
  var simulator: String?

  @Option(help: "Build configuration (Debug/Release). Default: Debug")
  var configuration: String?

  @Option(help: "Test plan name.")
  var testplan: String?

  @Flag(help: "Use 1800s timeout instead of the default 180s.")
  var long = false

  @Flag(help: "Capture a diagnostic snapshot even when the test run succeeds.")
  var diagnose = false

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  @Option(
    name: [.customLong("for")],
    help: "Output audience: 'human' (default) or 'agent'. 'agent' implies --json with a slim shape."
  )
  var forMode: OutputAudience = .human

  @Flag(help: "Apply known-failures gate to the rerun result.")
  var gate = false

  mutating func run() async throws {
    let cwd = FileManager.default.currentDirectoryPath
    let repoRoot = RepoRoot.discover(from: cwd) ?? cwd
    guard let payload = LastFailuresStore.read(at: repoRoot) else {
      fputs("no prior failures recorded — run `test run` first\n", stderr)
      throw ExitCode(2)
    }
    if payload.failures.isEmpty {
      print("no failures to rerun")
      return
    }

    let useJSON = shouldOutputJSON(flag: json) || forMode == .agent
    let configuration = self.configuration ?? "Debug"

    // Pass failure IDs as a pre-split list so IDs containing commas (e.g.
    // parameterized Swift Testing arguments) survive the trip to xcodebuild
    // intact — no comma-join + re-split round-trip.
    let execution = try await TestTools.executeTest(
      project: project,
      scheme: scheme ?? payload.scheme,
      simulator: simulator ?? payload.simulator,
      configuration: configuration,
      testplan: testplan,
      filter: nil,
      filterIDs: payload.failures,
      coverage: false,
      long: long,
      diagnose: diagnose,
      simRecovery: .off,
      gate: gate,
      forMode: forMode
    )

    if useJSON {
      print(try WorkflowJSONRenderer.renderTestJSON(execution, forAgent: forMode == .agent))
    } else {
      print(TestRenderer.renderTest(execution))
    }

    if !execution.succeeded {
      throw ExitCode.failure
    }
  }
}

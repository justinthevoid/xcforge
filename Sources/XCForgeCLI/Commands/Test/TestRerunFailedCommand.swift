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

  @Flag(help: "Raise the total time limit from 1800s to 7200s.")
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

  @OptionGroup var testRun: TestRunOptionGroup

  @OptionGroup var xcodebuild: XcodebuildOptionGroup

  mutating func run() async throws {
    let command = self
    try await xcodebuild.scoped { try await command.execute() }
  }

  func execute() async throws {
    let env = Environment.live
    let session = env.session
    // Failures are recorded in the repo of the project that was tested.
    let cwd = FileManager.default.currentDirectoryPath
    var repoRoot = RepoRoot.discover(from: cwd) ?? cwd
    if let project, let resolved = try? await session.resolveProject(project) {
      repoRoot = RepoRoot.discover(from: (resolved as NSString).deletingLastPathComponent) ?? repoRoot
    }
    guard let payload = LastFailuresStore.read(at: repoRoot) else {
      fputs("no prior failures recorded — run `test run` first\n", stderr)
      throw ExitCode(2)
    }
    if let reason = payload.infraFailure {
      fputs(
        "the last run failed before any test reported a result (\(reason)); there are no failures to rerun."
          + " Fix that and run the tests again.\n", stderr)
      throw ExitCode(2)
    }
    if payload.failures.isEmpty {
      print("no failures to rerun")
      return
    }

    let useJSON = shouldOutputJSON(flag: json) || forMode == .agent
    let recorded = payload.run
    let resolvedProject = project ?? recorded?.project
    let configuration = await session.resolveConfiguration(self.configuration ?? recorded?.configuration)
    let resolvedTestplan = await session.resolveTestPlan(testplan ?? recorded?.testPlan)
    let envEntries = testRun.env.isEmpty ? (recorded?.env ?? []) : testRun.env

    // Without --build/--no-build, skip the build when nothing changed since the last one.
    let skipBuild: Bool
    if let build = testRun.build {
      skipBuild = !build
    } else {
      skipBuild = await TestTools.lastTestBuildIsCurrent(
        project: resolvedProject, scheme: scheme ?? payload.scheme, simulator: simulator ?? payload.simulator,
        configuration: configuration, testplan: resolvedTestplan, testIDs: payload.failures, env: env)
    }

    // Pass failure IDs as a pre-split list so IDs containing commas (e.g.
    // parameterized Swift Testing arguments) survive the trip to xcodebuild
    // intact — no comma-join + re-split round-trip.
    let execution = try await TestTools.executeTest(
      project: resolvedProject,
      scheme: scheme ?? payload.scheme,
      simulator: simulator ?? payload.simulator,
      configuration: configuration,
      testplan: resolvedTestplan,
      filter: nil,
      filterIDs: payload.failures,
      coverage: false,
      long: long,
      diagnose: diagnose,
      simRecovery: .off,
      timeoutSeconds: testRun.timeout,
      envEntries: envEntries,
      gate: gate,
      forMode: forMode,
      skipBuild: skipBuild,
      testOptions: testRun.testOptions,
      includeConsole: testRun.includeConsole,
      env: env
    )

    if useJSON {
      print(try WorkflowJSONRenderer.renderTestJSON(execution, forAgent: forMode == .agent))
    } else {
      if skipBuild && testRun.build == nil {
        print("Build skipped: no source changed since the last build (pass --build to force one).")
      }
      print(TestRenderer.renderTest(execution))
    }

    if !execution.succeeded {
      throw ExitCode.failure
    }
  }
}

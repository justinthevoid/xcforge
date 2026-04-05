import ArgumentParser
import Foundation
import XCForgeKit

struct XCForgeCLI: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "xcforge",
    abstract: "CLI-first workflow entrypoints for xcforge.",
    subcommands: [
      Build.self, Test.self, BuildTest.self, Sim.self, Device.self, Diagnose.self, Defaults.self,
      Console.self, Git.self, Logs.self, Screenshot.self, UI.self, Accessibility.self, Plan.self,
      SPM.self, Debug.self,
    ]
  )
}

struct Defaults: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "defaults",
    abstract: "Show, set, or clear persisted workflow defaults.",
    subcommands: [DefaultsShow.self, DefaultsSet.self, DefaultsClear.self],
    defaultSubcommand: DefaultsShow.self
  )
}

struct DefaultsShow: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "show",
    abstract: "Display current persisted workflow defaults."
  )

  mutating func run() async throws {
    let env = Environment.live
    print(await env.session.showDefaults())
  }
}

struct DefaultsSet: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "set",
    abstract: "Set one or more persisted workflow defaults."
  )

  @Option(help: "Default project path (.xcodeproj or .xcworkspace).")
  var project: String?

  @Option(help: "Default scheme name.")
  var scheme: String?

  @Option(help: "Default simulator name or UDID.")
  var simulator: String?

  mutating func run() async throws {
    guard project != nil || scheme != nil || simulator != nil else {
      print("No defaults specified. Use --project, --scheme, or --simulator.")
      throw ExitCode.validationFailure
    }

    let env = Environment.live
    await env.session.setDefaults(
      project: project, scheme: scheme, simulator: simulator
    )
    print(await env.session.showDefaults())
  }
}

struct DefaultsClear: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "clear",
    abstract: "Clear all persisted workflow defaults."
  )

  mutating func run() async throws {
    let env = Environment.live
    await env.session.clearDefaults()
    print("Defaults cleared. Auto-detection will be used for all parameters.")
  }
}

/// Returns true when output should be JSON: either `--json` was passed or stdout is not a terminal.
func shouldOutputJSON(flag: Bool) -> Bool {
  flag || !isatty(STDOUT_FILENO).asBool
}

extension Int32 {
  fileprivate var asBool: Bool { self != 0 }
}

/// Execute a throwing closure, formatting any error as a JSON envelope when json is true.
func runAsyncJSON(json: Bool, body: () throws -> Void) throws {
  do {
    try body()
  } catch {
    try rethrowOrJSONError(error, json: json)
  }
}

/// Rethrow an error, formatting as JSON if the flag is set.
func rethrowOrJSONError(_ error: Error, json: Bool) throws {
  if let exitCode = error as? ExitCode { throw exitCode }
  guard json else { throw error }
  let envelope = CLIErrorEnvelope(error: "\(error)", code: errorCode(for: error))
  if let data = try? JSONEncoder().encode(envelope),
    let jsonString = String(data: data, encoding: .utf8)
  {
    fputs(jsonString + "\n", stderr)
  }
  throw ExitCode.failure
}

struct CLIErrorEnvelope: Encodable {
  let error: String
  let code: String
}

private func errorCode(for error: Error) -> String {
  let typeName = String(describing: type(of: error))
  if typeName.contains("ResolverError") || typeName.contains("CoverageError")
    || typeName.contains("TestDiscoveryError") || typeName.contains("BuildSettingsError")
    || typeName.contains("ToolValidationError")
  {
    return "resolution_failed"
  }
  if typeName.contains("ValidationError") { return "validation_error" }
  if error is EncodingError { return "encoding_failed" }
  if error is DecodingError { return "decoding_failed" }
  return "execution_failed"
}

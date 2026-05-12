import ArgumentParser
import Foundation
import MCP
import XCForgeKit

struct Bless: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "bless",
    abstract: "Save visual baseline, run tests, compare, and suggest a commit message.",
    subcommands: [BlessRun.self],
    defaultSubcommand: BlessRun.self
  )
}

struct BlessRun: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "run",
    abstract: "Save baseline, run tests, and compare visual output."
  )

  @Option(help: "Name to use for the visual baseline.")
  var baseline: String

  @Option(help: "Test filter, e.g. 'MyTarget/MyTests'.")
  var tests: String

  @Option(help: "Path to .xcodeproj or .xcworkspace. Auto-detected if omitted.")
  var project: String?

  @Option(help: "Xcode scheme name. Auto-detected if omitted.")
  var scheme: String?

  @Option(help: "Simulator name or UDID. Auto-detected if omitted.")
  var simulator: String?

  mutating func run() async throws {
    let env = Environment.live
    var args: [String: Value] = [
      "baseline": .string(baseline),
      "tests": .string(tests),
    ]
    if let project { args["project"] = .string(project) }
    if let scheme { args["scheme"] = .string(scheme) }
    if let simulator { args["simulator"] = .string(simulator) }

    let result = await BlessTools.blessImpl(args, env: env)
    let text = result.content.compactMap { item -> String? in
      if case .text(let t, _, _) = item { return t }
      return nil
    }.joined(separator: "\n")
    print(text)
    if result.isError == true {
      throw ExitCode.failure
    }
  }
}

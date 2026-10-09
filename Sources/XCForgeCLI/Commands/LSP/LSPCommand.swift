import ArgumentParser
import Foundation
import XCForgeKit

struct LSP: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "lsp",
    abstract: "Editor (SourceKit-LSP) integration.",
    subcommands: [LSPSetup.self],
    defaultSubcommand: LSPSetup.self
  )
}

struct LSPSetup: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "setup",
    abstract:
      "Write buildServer.json (via xcode-build-server) pointed at this project's DerivedData, so SourceKit-LSP finds modules."
  )

  @Option(help: "Path to .xcodeproj or .xcworkspace. Auto-detected if omitted.")
  var project: String?

  @Option(help: "Scheme to index. Auto-detected if omitted.")
  var scheme: String?

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    let result = await BuildTools.executeLSPSetup(project: project, scheme: scheme, env: .live)
    if shouldOutputJSON(flag: json) {
      print(try WorkflowJSONRenderer.renderJSON(result))
    } else {
      print(result.message)
      if let root = result.buildRoot { print("build_root: \(root)") }
    }
    if !result.succeeded { throw ExitCode.failure }
  }
}

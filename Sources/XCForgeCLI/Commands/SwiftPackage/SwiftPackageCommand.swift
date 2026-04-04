import ArgumentParser
import Foundation
import XCForgeKit

struct SPM: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "spm",
    abstract: "Swift Package Manager operations (build, test, run, list, clean).",
    subcommands: [SPMBuild.self, SPMTest.self, SPMRun.self, SPMList.self, SPMClean.self],
    defaultSubcommand: SPMBuild.self
  )
}

struct SPMBuild: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "build",
    abstract: "Build a Swift package."
  )

  @Option(help: "Working directory (defaults to current).")
  var path: String?

  @Option(help: "Build configuration (debug/release).")
  var configuration: String?

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    let env = Environment.live
    let result = await SwiftPackageTools.executeBuild(
      path: path, configuration: configuration, env: env)

    if json {
      print(try WorkflowJSONRenderer.renderJSON(result))
    } else {
      print(result.message)
    }

    if !result.succeeded {
      throw ExitCode.failure
    }
  }
}

struct SPMTest: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "test",
    abstract: "Run tests for a Swift package."
  )

  @Option(help: "Working directory (defaults to current).")
  var path: String?

  @Option(help: "Test filter.")
  var filter: String?

  @Flag(help: "Run tests in parallel.")
  var parallel = false

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    let env = Environment.live
    let result = await SwiftPackageTools.executeTest(
      path: path, filter: filter, parallel: parallel, env: env)

    if json {
      print(try WorkflowJSONRenderer.renderJSON(result))
    } else {
      print(result.message)
    }

    if !result.succeeded {
      throw ExitCode.failure
    }
  }
}

struct SPMRun: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "run",
    abstract: "Run a Swift package executable."
  )

  @Option(help: "Working directory (defaults to current).")
  var path: String?

  @Argument(help: "Target executable to run.")
  var executable: String?

  @Argument(parsing: .captureForPassthrough)
  var arguments: [String] = []

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    let env = Environment.live
    let result = await SwiftPackageTools.executeRun(
      path: path, executable: executable, arguments: arguments, env: env)

    if json {
      print(try WorkflowJSONRenderer.renderJSON(result))
    } else {
      print(result.message)
    }

    if !result.succeeded {
      throw ExitCode.failure
    }
  }
}

struct SPMList: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "list",
    abstract: "List targets and dependencies of a Swift package."
  )

  @Option(help: "Working directory (defaults to current).")
  var path: String?

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    let env = Environment.live
    let result = await SwiftPackageTools.executeList(path: path, env: env)

    if json {
      print(try WorkflowJSONRenderer.renderJSON(result))
    } else {
      print(result.message)
    }

    if !result.succeeded {
      throw ExitCode.failure
    }
  }
}

struct SPMClean: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "clean",
    abstract: "Clean the build artifacts of a Swift package."
  )

  @Option(help: "Working directory (defaults to current).")
  var path: String?

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    let env = Environment.live
    let result = await SwiftPackageTools.executeClean(path: path, env: env)

    if json {
      print(try WorkflowJSONRenderer.renderJSON(result))
    } else {
      print(result.message)
    }

    if !result.succeeded {
      throw ExitCode.failure
    }
  }
}

import ArgumentParser
import Foundation
import XCForgeKit

struct Build: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "build",
    abstract: "Build, clean, and inspect Xcode projects.",
    subcommands: [BuildRun.self, BuildClean.self, BuildDiscover.self, BuildSchemes.self],
    defaultSubcommand: BuildRun.self
  )
}

// MARK: - build run (default)

struct BuildRun: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "run",
    abstract: "Build, install, and launch an iOS app on a simulator."
  )

  @Option(help: "Path to .xcodeproj or .xcworkspace. Auto-detected if omitted.")
  var project: String?

  @Option(help: "Xcode scheme name. Auto-detected if omitted.")
  var scheme: String?

  @Option(help: "Simulator name or UDID. Auto-detected from booted simulator if omitted.")
  var simulator: String?

  @Option(help: "Build configuration (Debug/Release). Default: Debug")
  var configuration: String?

  @Flag(help: "Extract structured diagnostics (errors, warnings with file locations).")
  var diagnose = false

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    let configuration = self.configuration ?? "Debug"
    let useJSON = shouldOutputJSON(flag: json)

    let env = Environment.live
    if diagnose {
      let resolvedProject = try await env.session.resolveProject(project)
      let resolvedScheme = try await env.session.resolveScheme(scheme, project: resolvedProject)
      let resolvedSimulator = try await env.session.resolveSimulator(simulator)

      let execution = try await TestTools.executeBuildDiagnosis(
        project: resolvedProject,
        scheme: resolvedScheme,
        simulator: resolvedSimulator,
        configuration: configuration
      )

      if useJSON {
        print(try WorkflowJSONRenderer.renderJSON(execution))
      } else {
        print(BuildRenderer.renderDiagnose(execution))
      }

      if !execution.succeeded {
        throw ExitCode.failure
      }
    } else {
      let execution = try await BuildTools.executeBuild(
        project: project,
        scheme: scheme,
        simulator: simulator,
        configuration: configuration
      )

      guard execution.succeeded else {
        if useJSON {
          print(try WorkflowJSONRenderer.renderJSON(execution))
        } else {
          print(BuildRenderer.renderBuild(execution))
        }
        throw ExitCode.failure
      }

      // Build succeeded — continue with boot → install → launch pipeline.
      let resolvedSimulator = execution.simulator

      let bootResult = await SimTools.executeBootSim(simulator: resolvedSimulator, env: env)
      let bootStatus = bootResult.succeeded ? "ok" : "failed: \(bootResult.message)"

      var installStatus = "skipped"
      var launchStatus = "skipped"

      if bootResult.succeeded, let appPath = execution.appPath {
        let installResult = await SimTools.executeInstallApp(
          simulator: resolvedSimulator, appPath: appPath, env: env)
        installStatus = installResult.succeeded ? "ok" : "failed: \(installResult.message)"

        if installResult.succeeded, let bundleId = execution.bundleId {
          let launchResult = await SimTools.executeLaunchApp(
            simulator: resolvedSimulator, bundleId: bundleId, env: env)
          launchStatus = launchResult.succeeded ? "ok" : "failed: \(launchResult.message)"
        } else if !installResult.succeeded {
          launchStatus = "skipped (install failed)"
        }
      } else if !bootResult.succeeded {
        installStatus = "skipped (boot failed)"
        launchStatus = "skipped (boot failed)"
      } else {
        installStatus = "skipped (no app path)"
      }

      if useJSON {
        print(try WorkflowJSONRenderer.renderJSON(execution))
      } else {
        print(
          BuildRenderer.renderBuildRun(
            execution, bootStatus: bootStatus, installStatus: installStatus,
            launchStatus: launchStatus))
      }

      let failed =
        bootStatus.hasPrefix("failed") || installStatus.hasPrefix("failed")
        || launchStatus.hasPrefix("failed")
      if failed {
        throw ExitCode.failure
      }
    }
  }
}

// MARK: - build clean

struct BuildClean: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "clean",
    abstract: "Clean build artifacts for a project and scheme."
  )

  @Option(help: "Path to .xcodeproj or .xcworkspace. Auto-detected if omitted.")
  var project: String?

  @Option(help: "Xcode scheme name. Auto-detected if omitted.")
  var scheme: String?

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    let useJSON = shouldOutputJSON(flag: json)

    let execution = try await BuildTools.executeClean(
      project: project,
      scheme: scheme
    )

    if useJSON {
      print(try WorkflowJSONRenderer.renderJSON(execution))
    } else {
      print(BuildRenderer.renderClean(execution))
    }

    if !execution.succeeded {
      throw ExitCode.failure
    }
  }
}

// MARK: - build discover

struct BuildDiscover: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "discover",
    abstract: "Find .xcodeproj and .xcworkspace files in a directory."
  )

  @Option(help: "Directory to search. Defaults to current directory.")
  var path: String?

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    let path = self.path ?? FileManager.default.currentDirectoryPath
    let useJSON = shouldOutputJSON(flag: json)

    let execution = try await BuildTools.executeDiscover(path: path)

    if useJSON {
      print(try WorkflowJSONRenderer.renderJSON(execution))
    } else {
      print(BuildRenderer.renderDiscover(execution))
    }
  }
}

// MARK: - build schemes

struct BuildSchemes: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "schemes",
    abstract: "List available schemes for a project."
  )

  @Option(help: "Path to .xcodeproj or .xcworkspace. Auto-detected if omitted.")
  var project: String?

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    let useJSON = shouldOutputJSON(flag: json)

    let execution = try await BuildTools.executeListSchemes(project: project)

    if useJSON {
      print(try WorkflowJSONRenderer.renderJSON(execution))
    } else {
      print(BuildRenderer.renderSchemes(execution))
    }

    if !execution.succeeded {
      throw ExitCode.failure
    }
  }
}

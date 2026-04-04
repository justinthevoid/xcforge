import ArgumentParser
import Foundation
import XCForgeKit

struct Build: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "build",
        abstract: "Build, clean, and inspect Xcode projects.",
        subcommands: [BuildRun.self, BuildClean.self, BuildDiscover.self, BuildSchemes.self],
        defaultSubcommand: BuildRun.self
    )
}

// MARK: - build run (default)

struct BuildRun: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Build an iOS app for simulator."
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

    mutating func run() throws {
        let project = self.project
        let scheme = self.scheme
        let simulator = self.simulator
        let configuration = self.configuration ?? "Debug"
        let diagnose = self.diagnose
        let useJSON = shouldOutputJSON(flag: self.json)

        try runAsync {
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

                if useJSON {
                    print(try WorkflowJSONRenderer.renderJSON(execution))
                } else {
                    print(BuildRenderer.renderBuild(execution))
                }

                if !execution.succeeded {
                    throw ExitCode.failure
                }
            }
        }
    }
}

// MARK: - build clean

struct BuildClean: ParsableCommand {
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

    mutating func run() throws {
        let project = self.project
        let scheme = self.scheme
        let useJSON = shouldOutputJSON(flag: self.json)

        try runAsync {
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
}

// MARK: - build discover

struct BuildDiscover: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "discover",
        abstract: "Find .xcodeproj and .xcworkspace files in a directory."
    )

    @Option(help: "Directory to search. Defaults to current directory.")
    var path: String?

    @Flag(help: "Emit the result as machine-readable JSON.")
    var json = false

    mutating func run() throws {
        let path = self.path ?? FileManager.default.currentDirectoryPath
        let useJSON = shouldOutputJSON(flag: self.json)

        try runAsync {
            let execution = try await BuildTools.executeDiscover(path: path)

            if useJSON {
                print(try WorkflowJSONRenderer.renderJSON(execution))
            } else {
                print(BuildRenderer.renderDiscover(execution))
            }
        }
    }
}

// MARK: - build schemes

struct BuildSchemes: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "schemes",
        abstract: "List available schemes for a project."
    )

    @Option(help: "Path to .xcodeproj or .xcworkspace. Auto-detected if omitted.")
    var project: String?

    @Flag(help: "Emit the result as machine-readable JSON.")
    var json = false

    mutating func run() throws {
        let project = self.project
        let useJSON = shouldOutputJSON(flag: self.json)

        try runAsync {
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
}

import ArgumentParser
import Foundation
import XCForgeKit

struct Test: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "test",
        abstract: "Run tests on simulator, inspect failures, and report coverage.",
        subcommands: [TestRun.self, TestFailures.self, TestCoverage.self, TestList.self],
        defaultSubcommand: TestRun.self
    )
}

struct TestRun: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Run xcodebuild test on simulator."
    )

    @Option(help: "Path to .xcodeproj or .xcworkspace. Auto-detected if omitted.")
    var project: String?

    @Option(help: "Xcode scheme name. Auto-detected if omitted.")
    var scheme: String?

    @Option(help: "Simulator name or UDID. Auto-detected from booted simulator if omitted.")
    var simulator: String?

    @Option(help: "Build configuration (Debug/Release). Default: Debug")
    var configuration: String?

    @Option(help: "Test plan name.")
    var testplan: String?

    @Option(help: "Test filter, e.g. 'MyTests/testFoo' or 'MyTests'.")
    var filter: String?

    @Flag(help: "Enable code coverage collection.")
    var coverage = false

    @Flag(help: "Emit the result as machine-readable JSON.")
    var json = false

    mutating func run() throws {
        let project = self.project
        let scheme = self.scheme
        let simulator = self.simulator
        let configuration = self.configuration ?? "Debug"
        let testplan = self.testplan
        let filter = self.filter
        let coverage = self.coverage
        let json = self.json

        try runAsync {
            let execution = try await TestTools.executeTest(
                project: project,
                scheme: scheme,
                simulator: simulator,
                configuration: configuration,
                testplan: testplan,
                filter: filter,
                coverage: coverage
            )

            if json {
                print(try WorkflowJSONRenderer.renderJSON(execution))
            } else {
                print(TestRenderer.renderTest(execution))
            }

            if !execution.succeeded {
                throw ExitCode.failure
            }
        }
    }
}

struct TestFailures: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "failures",
        abstract: "Extract failed tests with error messages, console output, and screenshots."
    )

    @Option(help: "Path to existing .xcresult bundle. If provided, skips running tests.")
    var xcresultPath: String?

    @Option(help: "Path to .xcodeproj or .xcworkspace. Auto-detected if omitted.")
    var project: String?

    @Option(help: "Xcode scheme name. Auto-detected if omitted.")
    var scheme: String?

    @Option(help: "Simulator name or UDID. Auto-detected if omitted.")
    var simulator: String?

    @Flag(help: "Include console output (print/NSLog) for each failed test.")
    var includeConsole = false

    @Flag(help: "Emit the result as machine-readable JSON.")
    var json = false

    mutating func run() throws {
        let xcresultPath = self.xcresultPath
        let project = self.project
        let scheme = self.scheme
        let simulator = self.simulator
        let includeConsole = self.includeConsole
        let json = self.json

        try runAsync {
            let result = try await TestTools.extractFailures(
                xcresultPath: xcresultPath,
                project: project,
                scheme: scheme,
                simulator: simulator,
                includeConsole: includeConsole
            )

            if json {
                print(try WorkflowJSONRenderer.renderJSON(result))
            } else {
                print(TestRenderer.renderFailures(result))
            }

            if !result.failures.isEmpty {
                throw ExitCode.failure
            }
        }
    }
}

struct TestCoverage: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "coverage",
        abstract: "Show code coverage report. Without --file: per-file overview. With --file: per-function detail."
    )

    @Option(help: "Drill into a specific file for per-function coverage (e.g. 'LoginViewModel.swift').")
    var file: String?

    @Option(help: "Path to existing .xcresult bundle (must have coverage enabled).")
    var xcresultPath: String?

    @Option(help: "Path to .xcodeproj or .xcworkspace. Auto-detected if omitted.")
    var project: String?

    @Option(help: "Xcode scheme name. Auto-detected if omitted.")
    var scheme: String?

    @Option(help: "Simulator name or UDID. Auto-detected if omitted.")
    var simulator: String?

    @Option(help: "Only show files below this coverage %. Default: 100 (show all).")
    var minCoverage: Double?

    @Flag(help: "Emit the result as machine-readable JSON.")
    var json = false

    mutating func run() throws {
        let file = self.file
        let xcresultPath = self.xcresultPath
        let project = self.project
        let scheme = self.scheme
        let simulator = self.simulator
        let minCoverage = self.minCoverage ?? 100.0
        let json = self.json

        try runAsync {
            if let file {
                // Per-function drill-down
                let resolvedXcresult: String
                if let provided = xcresultPath {
                    resolvedXcresult = provided
                } else {
                    let coverageResult = try await TestTools.extractCoverage(
                        project: project, scheme: scheme, simulator: simulator
                    )
                    resolvedXcresult = coverageResult.xcresultPath
                }

                let detail = try await TestTools.extractFileCoverage(
                    file: file,
                    xcresultPath: resolvedXcresult
                )

                if json {
                    print(try WorkflowJSONRenderer.renderJSON(detail))
                } else {
                    print(TestRenderer.renderFileCoverage(detail))
                }
            } else {
                // Overview
                let result = try await TestTools.extractCoverage(
                    xcresultPath: xcresultPath,
                    project: project,
                    scheme: scheme,
                    simulator: simulator,
                    minCoverage: minCoverage
                )

                if json {
                    print(try WorkflowJSONRenderer.renderJSON(result))
                } else {
                    print(TestRenderer.renderCoverage(result))
                }
            }
        }
    }
}

struct TestList: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List available test identifiers (Target/Class/method) for a scheme."
    )

    @Option(help: "Path to .xcodeproj or .xcworkspace. Auto-detected if omitted.")
    var project: String?

    @Option(help: "Xcode scheme name. Auto-detected if omitted.")
    var scheme: String?

    @Option(help: "Simulator name or UDID. Auto-detected from booted simulator if omitted.")
    var simulator: String?

    @Flag(help: "Emit the result as machine-readable JSON.")
    var json = false

    mutating func run() throws {
        let project = self.project
        let scheme = self.scheme
        let simulator = self.simulator
        let json = self.json

        try runAsync {
            let result = try await TestTools.executeListTests(
                project: project,
                scheme: scheme,
                simulator: simulator
            )

            if json {
                print(try WorkflowJSONRenderer.renderJSON(result))
            } else {
                print(TestRenderer.renderListTests(result))
            }
        }
    }
}

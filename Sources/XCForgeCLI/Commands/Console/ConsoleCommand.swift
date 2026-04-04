import ArgumentParser
import Foundation
import XCForgeKit

struct Console: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "console",
        abstract: "Launch, read, and stop app console output capture.",
        subcommands: [ConsoleLaunch.self, ConsoleRead.self, ConsoleStop.self],
        defaultSubcommand: ConsoleRead.self
    )
}

struct ConsoleResult: Codable {
    let succeeded: Bool
    let message: String
    let stdout: [String]?
    let stderr: [String]?
    let isRunning: Bool?
    let bundleId: String?
}

struct ConsoleLaunch: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "launch",
        abstract: "Launch an app with console output capture."
    )

    @Option(help: "Simulator name or UDID. Auto-detected from booted simulator if omitted.")
    var simulator: String?

    @Option(name: .long, help: "App bundle identifier. Auto-detected from last build if omitted.")
    var bundleId: String?

    @Option(help: "Space-separated launch arguments for the app.")
    var args: String?

    @Flag(help: "Emit the result as machine-readable JSON.")
    var json = false

    mutating func run() throws {
        let simulator = self.simulator
        let bundleId = self.bundleId
        let args = self.args
        let json = self.json

        try runAsync {
            let env = Environment.live
            guard let resolvedBundleId = await env.session.resolveBundleId(bundleId) else {
                let result = ConsoleResult(
                    succeeded: false,
                    message: "Missing bundle_id — provide --bundle-id or run build first",
                    stdout: nil, stderr: nil, isRunning: nil, bundleId: nil
                )
                if json {
                    print(try ConsoleRenderer.renderJSON(result))
                } else {
                    print(ConsoleRenderer.renderError(result.message))
                }
                throw ExitCode.failure
            }

            let launchArgs = args?.split(separator: " ").map(String.init) ?? []

            let sim: String
            do {
                sim = try await env.session.resolveSimulator(simulator)
            } catch {
                let result = ConsoleResult(
                    succeeded: false,
                    message: "\(error)",
                    stdout: nil, stderr: nil, isRunning: nil, bundleId: nil
                )
                if json {
                    print(try ConsoleRenderer.renderJSON(result))
                } else {
                    print(ConsoleRenderer.renderError(result.message))
                }
                throw ExitCode.failure
            }

            do {
                let udid = try await SimTools.resolveSimulator(sim)
                let msg = try await AppConsole.shared.launch(
                    simulator: udid, bundleId: resolvedBundleId, args: launchArgs
                )
                let result = ConsoleResult(
                    succeeded: true,
                    message: msg,
                    stdout: nil, stderr: nil,
                    isRunning: true,
                    bundleId: resolvedBundleId
                )
                if json {
                    print(try ConsoleRenderer.renderJSON(result))
                } else {
                    print(ConsoleRenderer.renderLaunch(result))
                }
            } catch {
                let result = ConsoleResult(
                    succeeded: false,
                    message: "Launch failed: \(error)",
                    stdout: nil, stderr: nil, isRunning: false, bundleId: resolvedBundleId
                )
                if json {
                    print(try ConsoleRenderer.renderJSON(result))
                } else {
                    print(ConsoleRenderer.renderError(result.message))
                }
                throw ExitCode.failure
            }
        }
    }
}

struct ConsoleRead: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "read",
        abstract: "Read captured console output from a running app."
    )

    @Option(help: "Only return last N lines per stream.")
    var last: Int?

    @Flag(help: "Clear buffer after reading.")
    var clear = false

    @Option(help: "Which stream to read: stdout, stderr, or both. Default: both.")
    var stream: String = "both"

    @Flag(help: "Emit the result as machine-readable JSON.")
    var json = false

    mutating func run() throws {
        let last = self.last
        let clear = self.clear
        let stream = self.stream
        let json = self.json

        try runAsync {
            let output = await AppConsole.shared.read(last: last, clear: clear)

            let filteredStdout: [String]?
            let filteredStderr: [String]?

            switch stream {
            case "stdout":
                filteredStdout = output.stdout
                filteredStderr = nil
            case "stderr":
                filteredStdout = nil
                filteredStderr = output.stderr
            default:
                filteredStdout = output.stdout
                filteredStderr = output.stderr
            }

            let result = ConsoleResult(
                succeeded: true,
                message: clear ? "Buffer cleared after reading" : "Console output read",
                stdout: filteredStdout,
                stderr: filteredStderr,
                isRunning: output.isRunning,
                bundleId: output.bundleId
            )

            if json {
                print(try ConsoleRenderer.renderJSON(result))
            } else {
                print(ConsoleRenderer.renderRead(result, stream: stream, cleared: clear))
            }
        }
    }
}

struct ConsoleStop: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stop",
        abstract: "Stop the app console capture and terminate the app."
    )

    @Flag(help: "Emit the result as machine-readable JSON.")
    var json = false

    mutating func run() throws {
        let json = self.json

        try runAsync {
            await AppConsole.shared.stop()

            let result = ConsoleResult(
                succeeded: true,
                message: "App console stopped",
                stdout: nil, stderr: nil,
                isRunning: false, bundleId: nil
            )

            if json {
                print(try ConsoleRenderer.renderJSON(result))
            } else {
                print(ConsoleRenderer.renderStop(result))
            }
        }
    }
}

import Foundation
import MCP

/// Captures stdout/stderr from a running iOS app via `simctl launch --console`.
/// This captures print() statements, NSLog, and all console output.
public actor AppConsole {
    public static let shared = AppConsole()

    private var process: Process?
    private var stdoutBuffer: [String] = []
    private var stderrBuffer: [String] = []
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var bundleId: String?
    private let maxLines = 10000

    public func launch(simulator: String, bundleId: String, args: [String] = [], env: [String: String] = [:]) throws -> String {
        // Stop existing capture
        stop()

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")

        var simctlArgs = ["simctl", "launch", "--console", "--terminate-running-process", simulator, bundleId]
        simctlArgs += args

        proc.arguments = simctlArgs

        // Pass environment variables via SIMCTL_CHILD_ prefix
        if !env.isEmpty {
            var procEnv = ProcessInfo.processInfo.environment
            for (k, v) in env {
                procEnv["SIMCTL_CHILD_\(k)"] = v
            }
            proc.environment = procEnv
        }

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        self.stdoutPipe = outPipe
        self.stderrPipe = errPipe

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { [weak self] in await self?.appendStdout(text) }
        }

        errPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { [weak self] in await self?.appendStderr(text) }
        }

        try proc.run()
        self.process = proc
        self.bundleId = bundleId

        return "Console capture started for \(bundleId)"
    }

    private func appendStdout(_ text: String) {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        stdoutBuffer.append(contentsOf: lines)
        if stdoutBuffer.count > maxLines {
            stdoutBuffer.removeFirst(stdoutBuffer.count - maxLines)
        }
    }

    private func appendStderr(_ text: String) {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        stderrBuffer.append(contentsOf: lines)
        if stderrBuffer.count > maxLines {
            stderrBuffer.removeFirst(stderrBuffer.count - maxLines)
        }
    }

    public func stop() {
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminate()
        process = nil
        stdoutPipe = nil
        stderrPipe = nil
        stdoutBuffer.removeAll()
        stderrBuffer.removeAll()
        bundleId = nil
    }

    public struct ConsoleOutput: Sendable {
        public let stdout: [String]
        public let stderr: [String]
        public let isRunning: Bool
        public let bundleId: String?
    }

    public func read(last: Int?, clear: Bool) -> ConsoleOutput {
        let out: [String]
        let err: [String]

        if let n = last {
            out = Array(stdoutBuffer.suffix(n))
            err = Array(stderrBuffer.suffix(n))
        } else {
            out = stdoutBuffer
            err = stderrBuffer
        }

        if clear {
            stdoutBuffer.removeAll()
            stderrBuffer.removeAll()
        }

        return ConsoleOutput(
            stdout: out,
            stderr: err,
            isRunning: process?.isRunning ?? false,
            bundleId: bundleId
        )
    }

    var isRunning: Bool {
        process?.isRunning ?? false
    }
}

enum ConsoleTools {
    struct RuntimeSignalCapture: Sendable, Equatable {
        let relaunchedApp: Bool
        let stdout: [String]
        let stderr: [String]
        let isRunning: Bool
        let combinedText: String
    }

    public static let tools: [Tool] = [
        Tool(
            name: "launch_app_console",
            description: "Launch an app with console output capture. Captures all print() and NSLog output. Bundle ID is auto-detected from last build if omitted.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "simulator": .object(["type": .string("string"), "description": .string("Simulator name or UDID. Auto-detected from booted simulator if omitted.")]),
                    "bundle_id": .object(["type": .string("string"), "description": .string("App bundle identifier. Auto-detected from last build_sim if omitted.")]),
                    "args": .object(["type": .string("string"), "description": .string("Space-separated launch arguments for the app")]),
                ]),
            ])
        ),
        Tool(
            name: "read_app_console",
            description: "Read captured console output (stdout + stderr) from a running app launched with launch_app_console.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "last": .object(["type": .string("number"), "description": .string("Only return last N lines per stream")]),
                    "clear": .object(["type": .string("boolean"), "description": .string("Clear buffer after reading. Default: false")]),
                    "stream": .object(["type": .string("string"), "description": .string("Which stream: stdout, stderr, or both. Default: both")]),
                ]),
            ])
        ),
        Tool(
            name: "stop_app_console",
            description: "Stop the app console capture and terminate the app.",
            inputSchema: .object(["type": .string("object"), "properties": .object([:])])
        ),
    ]

    // MARK: - Input Types

    struct LaunchConsoleInput: Decodable {
        let simulator: String?
        let bundle_id: String?
        let args: String?
    }

    struct ReadConsoleInput: Decodable {
        let last: Int?
        let clear: Bool?
        let stream: String?
    }

    static func launchAppConsole(_ args: [String: Value]?, env: Environment) async -> CallTool.Result {
        switch ToolInput.decode(LaunchConsoleInput.self, from: args) {
        case .failure(let err): return err
        case .success(let input):
            guard let bundleId = await env.session.resolveBundleId(input.bundle_id) else {
                return .fail("Missing bundle_id — provide it or run build_sim first")
            }
            let launchArgs = input.args?.split(separator: " ").map(String.init) ?? []

            let sim: String
            do {
                sim = try await env.session.resolveSimulator(input.simulator)
            } catch {
                return .fail("\(error)")
            }

            do {
                let udid = try await SimTools.resolveSimulator(sim)
                let msg = try await AppConsole.shared.launch(simulator: udid, bundleId: bundleId, args: launchArgs)
                return .ok(msg)
            } catch {
                return .fail("Launch failed: \(error)")
            }
        }
    }

    static func readAppConsole(_ args: [String: Value]?) async -> CallTool.Result {
        switch ToolInput.decode(ReadConsoleInput.self, from: args) {
        case .failure(let err): return err
        case .success(let input):
            return await readAppConsoleImpl(input)
        }
    }

    private static func readAppConsoleImpl(_ input: ReadConsoleInput) async -> CallTool.Result {
        let last = input.last
        let clear = input.clear ?? false
        let stream = input.stream ?? "both"

        let output = await AppConsole.shared.read(last: last, clear: clear)

        var sections: [String] = []

        if stream == "stdout" || stream == "both" {
            if output.stdout.isEmpty {
                sections.append("=== STDOUT (empty) ===")
            } else {
                let text = output.stdout.joined(separator: "\n")
                let truncated = text.count > 30000 ? String(text.prefix(30000)) + "\n... [truncated]" : text
                sections.append("=== STDOUT (\(output.stdout.count) lines) ===\n\(truncated)")
            }
        }

        if stream == "stderr" || stream == "both" {
            if output.stderr.isEmpty {
                sections.append("=== STDERR (empty) ===")
            } else {
                let text = output.stderr.joined(separator: "\n")
                let truncated = text.count > 30000 ? String(text.prefix(30000)) + "\n... [truncated]" : text
                sections.append("=== STDERR (\(output.stderr.count) lines) ===\n\(truncated)")
            }
        }

        let status = output.isRunning ? "running" : "stopped"
        let header = "App: \(output.bundleId ?? "?") [\(status)]\(clear ? " (buffer cleared)" : "")"

        return .ok(header + "\n\n" + sections.joined(separator: "\n\n"))
    }

    static func stopAppConsole(_ args: [String: Value]?) async -> CallTool.Result {
        await AppConsole.shared.stop()
        return .ok("App console stopped")
    }

    static func captureRuntimeSignals(
        simulatorUDID: String,
        bundleId: String,
        settleTimeNanoseconds: UInt64 = 1_500_000_000,
        env: Environment
    ) async throws -> RuntimeSignalCapture {
        await AppConsole.shared.stop()

        let relaunchedApp = try await SimTools.terminateAppIfRunning(simulatorUDID: simulatorUDID, bundleId: bundleId, env: env)
        if relaunchedApp {
            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        do {
            _ = try await AppConsole.shared.launch(simulator: simulatorUDID, bundleId: bundleId)
            try? await Task.sleep(nanoseconds: settleTimeNanoseconds)
        } catch {
            await AppConsole.shared.stop()
            throw error
        }

        let output = await AppConsole.shared.read(last: nil, clear: true)
        let appRunning = (try? await SimTools.terminateAppIfRunning(simulatorUDID: simulatorUDID, bundleId: bundleId, env: env)) ?? false
        await AppConsole.shared.stop()

        let combinedText = (output.stdout.map { "[stdout] \($0)" }
            + output.stderr.map { "[stderr] \($0)" })
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return RuntimeSignalCapture(
            relaunchedApp: relaunchedApp,
            stdout: output.stdout,
            stderr: output.stderr,
            isRunning: appRunning,
            combinedText: combinedText
        )
    }

    static func resetRuntimeCaptureContext(
        simulatorUDID: String,
        bundleId: String,
        wdaClient: WDAClient
    ) async -> SimTools.RuntimeContinuityReset {
        await AppConsole.shared.stop()
        return await SimTools.resetRuntimeContinuity(
            simulatorUDID: simulatorUDID,
            bundleId: bundleId,
            wdaClient: wdaClient,
            env: .live
        )
    }
}

extension ConsoleTools: ToolProvider {
    public static func dispatch(_ name: String, _ args: [String: Value]?, env: Environment) async -> CallTool.Result? {
        switch name {
        case "launch_app_console": return await launchAppConsole(args, env: env)
        case "read_app_console":   return await readAppConsole(args)
        case "stop_app_console":   return await stopAppConsole(args)
        default: return nil
        }
    }
}

import Foundation

public struct ShellResult: Sendable {
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32

    public var succeeded: Bool { exitCode == 0 }
}

// MARK: - ShellExecutor protocol

/// Abstraction over shell command execution. Enables dependency injection
/// for tool handlers, allowing tests to substitute a mock executor.
public protocol ShellExecutor: Sendable {
    func run(
        _ executable: String,
        arguments: [String],
        workingDirectory: String?,
        environment: [String: String]?,
        timeout: TimeInterval
    ) async throws -> ShellResult

    func xcrun(timeout: TimeInterval, arguments: [String]) async throws -> ShellResult

    func git(_ arguments: [String], workingDirectory: String, timeout: TimeInterval) async throws -> ShellResult
}

extension ShellExecutor {
    /// Convenience variadic wrapper matching Shell's original API.
    public func xcrun(timeout: TimeInterval = 300, _ args: String...) async throws -> ShellResult {
        try await xcrun(timeout: timeout, arguments: args)
    }

    /// Default parameter convenience for run.
    public func run(
        _ executable: String,
        arguments: [String],
        workingDirectory: String? = nil,
        environment: [String: String]? = nil,
        timeout: TimeInterval = 300
    ) async throws -> ShellResult {
        try await run(executable, arguments: arguments, workingDirectory: workingDirectory, environment: environment, timeout: timeout)
    }

    /// Default parameter convenience for git.
    public func git(_ arguments: [String], workingDirectory: String, timeout: TimeInterval = 30) async throws -> ShellResult {
        try await git(arguments, workingDirectory: workingDirectory, timeout: timeout)
    }
}

// MARK: - Environment

/// Carries injectable dependencies through the tool dispatch path.
public struct Environment: Sendable {
    public let shell: any ShellExecutor
    public let session: SessionState
    public let axpBridge: AXPBridge
    public let wdaClient: WDAClient

    public init(shell: any ShellExecutor, session: SessionState = SessionState(), axpBridge: AXPBridge = AXPBridge(), wdaClient: WDAClient = WDAClient()) {
        self.shell = shell
        self.session = session
        self.axpBridge = axpBridge
        self.wdaClient = wdaClient
    }

    /// Production environment using real process execution.
    public static let live = Environment(shell: LiveShell())
}

// MARK: - LiveShell (production implementation)

/// Production ShellExecutor that delegates to Shell's static methods.
public struct LiveShell: ShellExecutor {
    public init() {}

    public func run(
        _ executable: String,
        arguments: [String],
        workingDirectory: String?,
        environment: [String: String]?,
        timeout: TimeInterval
    ) async throws -> ShellResult {
        try await Shell.run(executable, arguments: arguments, workingDirectory: workingDirectory, environment: environment, timeout: timeout)
    }

    public func xcrun(timeout: TimeInterval, arguments: [String]) async throws -> ShellResult {
        try await Shell.xcrun(timeout: timeout, arguments: arguments)
    }

    public func git(_ arguments: [String], workingDirectory: String, timeout: TimeInterval) async throws -> ShellResult {
        try await Shell.git(arguments, workingDirectory: workingDirectory, timeout: timeout)
    }
}

// MARK: - Shell (static API preserved for non-tool callers)

public enum Shell {
    /// Run a command with arguments, returning stdout/stderr/exitCode.
    static func run(
        _ executable: String,
        arguments: [String],
        workingDirectory: String? = nil,
        environment: [String: String]? = nil,
        timeout: TimeInterval = 300
    ) async throws -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        if let dir = workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: dir)
        }

        if let env = environment {
            var merged = ProcessInfo.processInfo.environment
            for (k, v) in env { merged[k] = v }
            process.environment = merged
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Set termination handler BEFORE run() to avoid race condition.
        // Uses withCheckedContinuation instead of process.waitUntilExit() to avoid
        // blocking the Swift Cooperative Thread Pool. waitUntilExit() is synchronous
        // and permanently consumes a pool thread — with enough concurrent shell calls
        // or ESC-interrupted tasks, the pool is exhausted and ALL async work deadlocks.
        let terminationContinuation = AsyncStream<Int32>.makeStream()
        process.terminationHandler = { proc in
            terminationContinuation.continuation.yield(proc.terminationStatus)
            terminationContinuation.continuation.finish()
        }

        try process.run()

        // Timeout watchdog
        let pid = process.processIdentifier
        let timeoutNanos = UInt64(timeout * 1_000_000_000)
        let timeoutTask = Task.detached {
            try? await Task.sleep(nanoseconds: timeoutNanos)
            kill(pid, SIGTERM)
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            kill(pid, SIGKILL)
        }

        // Read output concurrently
        async let stdoutData = stdoutPipe.fileHandleForReading.readToEndAsync()
        async let stderrData = stderrPipe.fileHandleForReading.readToEndAsync()

        let (out, err) = try await (stdoutData, stderrData)

        // Await process exit without blocking the cooperative thread pool.
        // Note: for-await on AsyncStream breaks early if the Task is cancelled
        // (Swift 6 runtime). Guard against accessing terminationReason on a
        // still-running process — that throws an uncatchable ObjC exception.
        for await _ in terminationContinuation.stream {}
        timeoutTask.cancel()

        // If task was cancelled, the process may still be running
        if process.isRunning {
            kill(process.processIdentifier, SIGTERM)
            return ShellResult(stdout: "", stderr: "Task cancelled", exitCode: -2)
        }

        // Detect killed process (timeout or crash → uncaughtSignal)
        if process.terminationReason == .uncaughtSignal {
            let partialOut = String(data: out, encoding: .utf8) ?? ""
            return ShellResult(
                stdout: partialOut,
                stderr: "Process timed out after \(Int(timeout))s and was killed (signal \(process.terminationStatus))",
                exitCode: -1
            )
        }

        let stdout = String(data: out, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let stderr = String(data: err, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return ShellResult(stdout: stdout, stderr: stderr, exitCode: process.terminationStatus)
    }

    /// Convenience for xcrun commands. Accepts an optional timeout (default: 300s).
    static func xcrun(timeout: TimeInterval = 300, _ arguments: String...) async throws -> ShellResult {
        try await run("/usr/bin/xcrun", arguments: Array(arguments), timeout: timeout)
    }

    /// Array overload for xcrun (used by LiveShell delegation).
    static func xcrun(timeout: TimeInterval = 300, arguments: [String]) async throws -> ShellResult {
        try await run("/usr/bin/xcrun", arguments: arguments, timeout: timeout)
    }

    /// Convenience for git commands (default timeout: 30s)
    public static func git(_ arguments: [String], workingDirectory: String, timeout: TimeInterval = 30) async throws -> ShellResult {
        try await run("/usr/bin/git", arguments: arguments, workingDirectory: workingDirectory, timeout: timeout)
    }
}

// MARK: - FileHandle async read

extension FileHandle {
    func readToEndAsync() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                let data = self.readDataToEndOfFile()
                continuation.resume(returning: data)
            }
        }
    }
}

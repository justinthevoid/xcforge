import Foundation

// MARK: - DebuggerSessionError

public enum DebuggerSessionError: Error, CustomStringConvertible {
  case sessionExpired
  case timeout(String)
  case processLaunchFailed(String)

  public var description: String {
    switch self {
    case .sessionExpired:
      return "Session expired due to inactivity"
    case .timeout(let cmd):
      return "Timed out waiting for LLDB prompt after: \(cmd)"
    case .processLaunchFailed(let msg):
      return "LLDB process failed to launch: \(msg)"
    }
  }
}

// MARK: - DebuggerSession

/// Wraps a persistent `xcrun lldb` subprocess. All I/O is actor-isolated.
/// Sessions expire after 30 minutes of inactivity; the watchdog terminates
/// the process and removes the session from the registry.
public actor DebuggerSession {

  // MARK: - Properties

  public let sessionID: String
  private let process: Process
  private let stdinHandle: FileHandle
  private let stdoutHandle: FileHandle
  private var watchdogTask: Task<Void, Never>?
  private let inactivityTimeout: TimeInterval

  static let inactivitySeconds: TimeInterval = 30 * 60  // 30 minutes

  // MARK: - Initialization

  init(
    sessionID: String,
    process: Process,
    stdinHandle: FileHandle,
    stdoutHandle: FileHandle,
    inactivityTimeout: TimeInterval
  ) {
    self.sessionID = sessionID
    self.process = process
    self.stdinHandle = stdinHandle
    self.stdoutHandle = stdoutHandle
    self.inactivityTimeout = inactivityTimeout
  }

  /// Launch an LLDB process and return a connected session.
  public static func launch(
    sessionID: String,
    inactivityTimeout: TimeInterval = 30 * 60
  ) async throws -> DebuggerSession {
    let process = Process()
    let stdinPipe = Pipe()
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()

    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = ["lldb"]
    process.standardInput = stdinPipe
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    // terminationHandler must be set BEFORE process.run() to avoid races
    // with fast-exiting processes.
    let terminationStream = AsyncStream<Int32>.makeStream()
    process.terminationHandler = { proc in
      terminationStream.continuation.yield(proc.terminationStatus)
      terminationStream.continuation.finish()
    }

    do {
      try process.run()
    } catch {
      throw DebuggerSessionError.processLaunchFailed(error.localizedDescription)
    }

    // Drain stderr in background — prevents OS pipe buffer (~64 KB) from filling
    // and deadlocking LLDB when it writes verbose attach output to stderr.
    Task.detached {
      while process.isRunning {
        _ = stderrPipe.fileHandleForReading.availableData
        try? await Task.sleep(nanoseconds: 100_000_000)
      }
    }

    let session = DebuggerSession(
      sessionID: sessionID,
      process: process,
      stdinHandle: stdinPipe.fileHandleForWriting,
      stdoutHandle: stdoutPipe.fileHandleForReading,
      inactivityTimeout: inactivityTimeout
    )

    // Wait for the initial LLDB prompt before returning.
    _ = try await session.readUntilPrompt(timeout: 15)
    await session.resetWatchdog()
    return session
  }

  // MARK: - Public Methods

  /// Send a command to LLDB and return all output until the next prompt.
  /// Default timeout is 30 s; callers requiring a tighter bound (e.g. `continue`)
  /// should pass an explicit value.
  public func sendCommand(_ command: String, timeout: TimeInterval = 30) async throws -> String {
    guard process.isRunning else {
      throw DebuggerSessionError.sessionExpired
    }
    resetWatchdog()
    let line = command + "\n"
    guard let data = line.data(using: .utf8) else {
      return ""
    }
    stdinHandle.write(data)
    return try await readUntilPrompt(timeout: timeout)
  }

  /// Terminate the LLDB subprocess immediately.
  public func terminate() {
    watchdogTask?.cancel()
    watchdogTask = nil
    if process.isRunning {
      process.terminate()
    }
  }

  // MARK: - Private Methods

  /// Read stdout line-by-line until a line that starts with `(lldb) `.
  /// Accumulates all content before the prompt and returns it.
  private func readUntilPrompt(timeout: TimeInterval) async throws -> String {
    let deadline = DispatchTime.now() + timeout
    let stdoutHandle = self.stdoutHandle

    return try await withCheckedThrowingContinuation { continuation in
      DispatchQueue.global(qos: .utility).async {
        var result = ""

        while true {
          // Check timeout
          if DispatchTime.now() > deadline {
            break
          }

          let chunk = stdoutHandle.availableData
          if chunk.isEmpty {
            // Early-exit if the process has already terminated to avoid busy-waiting
            // the full timeout on a dead pipe returning empty data indefinitely.
            if !self.process.isRunning { break }
            Thread.sleep(forTimeInterval: 0.01)
            continue
          }

          guard let text = String(data: chunk, encoding: .utf8) else { continue }

          result += text

          // Check if accumulated output contains the LLDB prompt.
          // LLDB may emit the prompt mid-buffer after a command completes.
          if result.range(of: "\n(lldb) ") != nil || result.range(of: "(lldb) ") != nil {
            // Strip the trailing prompt and everything after it
            var output = result
            if let promptRange = result.range(of: "\n(lldb) ") {
              output = String(result[result.startIndex..<promptRange.lowerBound])
            } else if let promptRange = result.range(of: "(lldb) ") {
              output = String(result[result.startIndex..<promptRange.lowerBound])
            }
            continuation.resume(returning: output.trimmingCharacters(in: .newlines))
            return
          }
        }

        continuation.resume(throwing: DebuggerSessionError.timeout("readUntilPrompt"))
      }
    }
  }

  private func resetWatchdog() {
    watchdogTask?.cancel()
    let inactivityNanos = UInt64(inactivityTimeout * 1_000_000_000)
    watchdogTask = Task { [weak self] in
      do {
        try await Task.sleep(nanoseconds: inactivityNanos)
        guard let self else { return }
        await self.terminate()
        await DebuggerSessionRegistry.shared.remove(id: self.sessionID)
      } catch {}
    }
  }
}

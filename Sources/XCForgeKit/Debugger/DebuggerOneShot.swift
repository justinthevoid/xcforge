import Foundation

// MARK: - DebuggerOneShotError

public enum DebuggerOneShotError: Error, CustomStringConvertible {
  case pidResolutionFailed(String)
  case appNotRunning(String)

  public var description: String {
    switch self {
    case .pidResolutionFailed(let reason):
      return "PID resolution failed: \(reason)"
    case .appNotRunning(let bundleId):
      return "App '\(bundleId)' is not running on the booted simulator"
    }
  }
}

// MARK: - DebuggerOneShot

/// Provides one-shot attach → operate → detach helpers for CLI commands.
/// Each CLI invocation creates a fresh session, performs one operation, then
/// removes the session. Long-lived sessions are only used by the MCP server.
public enum DebuggerOneShot {

  // MARK: - PID Resolution

  /// Resolve a running process ID for the given bundle ID on the booted simulator.
  public static func resolveProcessID(for bundleId: String) async throws -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = ["simctl", "listapps", "booted", "--json"]

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    let terminationStream = AsyncStream<Int32>.makeStream()
    // Set terminationHandler BEFORE process.run() to avoid the race where a
    // fast-exiting process fires the handler before it is registered.
    process.terminationHandler = { proc in
      terminationStream.continuation.yield(proc.terminationStatus)
      terminationStream.continuation.finish()
    }

    try process.run()

    // Drain stderr to avoid pipe-buffer deadlock
    Task.detached {
      _ = stderrPipe.fileHandleForReading.readDataToEndOfFile()
    }

    let outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()

    var exitStatus: Int32 = 0
    for await status in terminationStream.stream {
      exitStatus = status
    }

    guard exitStatus == 0 else {
      throw DebuggerOneShotError.pidResolutionFailed("simctl exited \(exitStatus)")
    }

    guard
      let json = try? JSONSerialization.jsonObject(with: outputData) as? [String: Any],
      let appInfo = json[bundleId] as? [String: Any]
    else {
      throw DebuggerOneShotError.appNotRunning(bundleId)
    }

    guard let pid = appInfo["pid"] as? Int else {
      throw DebuggerOneShotError.appNotRunning(bundleId)
    }

    return Int32(pid)
  }

  // MARK: - One-Shot Operation

  /// Attach LLDB to a process, run `operation`, then detach — suitable for CLI use.
  public static func withSession<T: Sendable>(
    pid: Int32,
    registry: DebuggerSessionRegistry = DebuggerSessionRegistry.shared,
    operation: @Sendable (DebuggerSession) async throws -> T
  ) async throws -> T {
    let sessionID = UUID().uuidString
    let session = try await DebuggerSession.launch(sessionID: sessionID)

    let id = await registry.create(session: session)

    defer {
      Task { await registry.remove(id: id) }
    }

    // Attach to the PID
    let attachOutput = try await session.sendCommand("process attach --pid \(pid)")
    let lower = attachOutput.lowercased()
    guard !lower.contains("error:") && !lower.contains("failed to attach") else {
      throw DebuggerSessionError.processLaunchFailed("Attach failed: \(attachOutput)")
    }

    return try await operation(session)
  }

  /// Convenience overload that resolves a bundle ID to a PID first.
  public static func withSession<T: Sendable>(
    bundleId: String,
    registry: DebuggerSessionRegistry = DebuggerSessionRegistry.shared,
    operation: @Sendable (DebuggerSession) async throws -> T
  ) async throws -> T {
    let pid = try await resolveProcessID(for: bundleId)
    return try await withSession(pid: pid, registry: registry, operation: operation)
  }
}

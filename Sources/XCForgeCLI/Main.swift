import ArgumentParser
import Dispatch
import Foundation
import Logging
import MCP
import XCForgeKit

@main
struct Main {
  static func main() async throws {
    // Ctrl-C, a shell tool's timeout kill or a client hang-up must not leave xcodebuild
    // running with DerivedData locked. Stop our children before exiting.
    let signalSources = installTerminationHandlers()
    defer { signalSources.forEach { $0.cancel() } }

    if CommandLine.arguments.count > 1 {
      await XCForgeCLI.main()
    } else {
      let logger = Logger(label: "com.xcforge.mcp")

      let server = Server(
        name: "xcforge",
        version: "1.6.1",
        capabilities: .init(tools: .init(listChanged: true))
      )

      await server.withMethodHandler(ListTools.self) { _ in
        .init(tools: ToolRegistry.allTools)
      }

      await server.withMethodHandler(CallTool.self) { params in
        guard let token = params._meta?.progressToken else {
          return await ToolRegistry.dispatch(params.name, params.arguments)
        }
        return await ProgressHeartbeat.run(token: token, server: server) {
          await ToolRegistry.dispatch(params.name, params.arguments)
        }
      }

      let transport = StdioTransport(logger: logger)
      try await server.start(transport: transport)
      await server.waitUntilCompleted()
      // The client closed stdin: nothing will read the results of calls still running.
      ChildProcesses.terminateAll()
    }
  }

  /// Forward SIGINT, SIGTERM and SIGHUP to running children, then exit with the usual
  /// 128 + signal status.
  static func installTerminationHandlers() -> [DispatchSourceSignal] {
    [SIGINT, SIGTERM, SIGHUP].map { sig in
      signal(sig, SIG_IGN)
      let source = DispatchSource.makeSignalSource(signal: sig, queue: .global())
      source.setEventHandler {
        ChildProcesses.terminateAll(grace: 1)
        // Give SIGTERM'd children a moment to exit before we go.
        Thread.sleep(forTimeInterval: ChildProcesses.running.isEmpty ? 0 : 1.2)
        exit(128 + sig)
      }
      source.resume()
      return source
    }
  }
}

/// Sends MCP progress notifications while a tool call runs, so clients that time out
/// silent requests keep waiting for long builds and tests.
enum ProgressHeartbeat {
  /// Seconds between notifications.
  static let interval: UInt64 = 10

  static func run(
    token: ProgressToken, server: Server, _ body: @Sendable () async -> CallTool.Result
  ) async -> CallTool.Result {
    let activity = ToolActivity()
    let started = Date()
    let heartbeat = Task {
      var beats = 0.0
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: interval * 1_000_000_000)
        if Task.isCancelled { break }
        beats += 1
        let elapsed = Int(Date().timeIntervalSince(started))
        let message = activity.lastLine.map { "\(elapsed)s: \($0)" } ?? "\(elapsed)s elapsed"
        try? await server.notify(
          ProgressNotification.message(
            .init(progressToken: token, progress: beats, message: message)))
      }
    }
    defer { heartbeat.cancel() }
    return await ToolActivity.$current.withValue(activity) { await body() }
  }
}

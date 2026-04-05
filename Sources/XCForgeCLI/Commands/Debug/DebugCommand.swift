import ArgumentParser
import Foundation
import XCForgeKit

// MARK: - Debug (group)

struct Debug: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "debug",
    abstract: "Attach LLDB to a running simulator process and inspect, step, or evaluate expressions.",
    subcommands: [
      DebugAttach.self,
      DebugDetach.self,
      DebugBacktrace.self,
      DebugInspect.self,
      DebugBreakpoint.self,
      DebugContinue.self,
      DebugRun.self,
    ]
  )
}

// MARK: - TargetOptions

/// Mixin that provides --pid / --bundle-id target selection for one-shot commands.
struct TargetOptions: ParsableArguments {
  @Option(help: "Process ID to attach to.")
  var pid: Int32?

  @Option(help: "App bundle ID on the booted simulator (e.g. com.example.App).")
  var bundleId: String?

  /// Resolve either --pid or --bundle-id into a concrete PID, throwing if neither provided.
  func resolvePID() async throws -> Int32 {
    if let pid = pid { return pid }
    if let bundleId = bundleId {
      return try await DebuggerOneShot.resolveProcessID(for: bundleId)
    }
    throw ValidationError("Either --pid or --bundle-id is required")
  }
}

// MARK: - debug attach

struct DebugAttach: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "attach",
    abstract: "Attach LLDB to a running simulator process and return a session ID."
  )

  @OptionGroup var target: TargetOptions

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    let useJSON = shouldOutputJSON(flag: json)
    do {
      let pid = try await target.resolvePID()
      let sessionID = UUID().uuidString
      let session = try await DebuggerSession.launch(sessionID: sessionID)
      _ = await DebuggerSessionRegistry.shared.create(session: session)

      // Ensure the session is cleaned up if attach fails or throws
      var attachSucceeded = false
      defer {
        if !attachSucceeded {
          Task { await DebuggerSessionRegistry.shared.remove(id: sessionID) }
        }
      }

      let attachOutput = try await session.sendCommand("process attach --pid \(pid)")
      let lower = attachOutput.lowercased()
      if lower.contains("error:") || lower.contains("failed") {
        throw ValidationError("Attach failed: \(attachOutput)")
      }

      attachSucceeded = true
      let result = DebuggerProvider.AttachResult(sessionId: sessionID, pid: pid, status: "stopped")
      if useJSON {
        print(try WorkflowJSONRenderer.renderJSON(result))
      } else {
        print(DebugRenderer.renderAttach(result))
      }
    } catch {
      try rethrowOrJSONError(error, json: useJSON)
    }
  }
}

// MARK: - debug detach

struct DebugDetach: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "detach",
    abstract: "Detach from a debugger session created by MCP lldb_attach."
  )

  @Option(help: "Session ID returned by lldb_attach or debug attach.")
  var session: String

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    let useJSON = shouldOutputJSON(flag: json)
    await DebuggerSessionRegistry.shared.remove(id: session)
    let result = DebuggerProvider.DetachResult(detached: true)
    if useJSON {
      print(try WorkflowJSONRenderer.renderJSON(result))
    } else {
      print("Session \(session) detached")
    }
  }
}

// MARK: - debug backtrace

struct DebugBacktrace: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "backtrace",
    abstract: "Print stack frames for a running process (one-shot attach, backtrace, detach)."
  )

  @OptionGroup var target: TargetOptions

  @Option(help: "Thread index (default 0).")
  var thread: Int = 0

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    let useJSON = shouldOutputJSON(flag: json)
    // Capture by value before @Sendable closure to avoid inout self capture
    let threadIndex = self.thread
    do {
      let pid = try await target.resolvePID()
      let frames = try await DebuggerOneShot.withSession(pid: pid) { session in
        if threadIndex != 0 {
          _ = try await session.sendCommand("thread select \(threadIndex)")
        }
        let output = try await session.sendCommand("bt")
        return DebuggerProvider.parseBacktraceOutput(output)
      }
      if useJSON {
        print(try WorkflowJSONRenderer.renderJSON(frames))
      } else {
        print(DebugRenderer.renderBacktrace(frames))
      }
    } catch {
      try rethrowOrJSONError(error, json: useJSON)
    }
  }
}

// MARK: - debug inspect

struct DebugInspect: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "inspect",
    abstract: "Evaluate an expression in the current frame (one-shot)."
  )

  @OptionGroup var target: TargetOptions

  @Option(help: "Expression to evaluate (e.g. self.count).")
  var expression: String

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    let useJSON = shouldOutputJSON(flag: json)
    // Capture by value before @Sendable closure
    let expr = self.expression
    do {
      guard !expr.contains("\n"), !expr.contains("\r") else {
        throw ValidationError("Newlines not allowed in expression")
      }
      let pid = try await target.resolvePID()
      let result = try await DebuggerOneShot.withSession(pid: pid) { session in
        let output = try await session.sendCommand("expression \(expr)")
        return DebuggerProvider.parseExpressionOutput(output, expression: expr)
      }
      if useJSON {
        print(try WorkflowJSONRenderer.renderJSON(result))
      } else {
        print(DebugRenderer.renderVariable(result))
      }
    } catch {
      try rethrowOrJSONError(error, json: useJSON)
    }
  }
}

// MARK: - debug breakpoint (sub-group)

struct DebugBreakpoint: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "breakpoint",
    abstract: "Set or remove breakpoints (one-shot).",
    subcommands: [DebugBreakpointSet.self, DebugBreakpointRemove.self],
    defaultSubcommand: DebugBreakpointSet.self
  )
}

// MARK: - debug breakpoint set

struct DebugBreakpointSet: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "set",
    abstract: "Set a breakpoint by file+line or function name (one-shot)."
  )

  @OptionGroup var target: TargetOptions

  @Option(help: "Source file name (e.g. Foo.swift). Used with --line.")
  var file: String?

  @Option(help: "Line number. Used with --file.")
  var line: Int?

  @Option(help: "Function or method name (e.g. -[FooVC viewDidLoad]).")
  var function: String?

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    let useJSON = shouldOutputJSON(flag: json)
    // Capture by value before @Sendable closure
    let fileArg = self.file
    let lineArg = self.line
    let functionArg = self.function
    do {
      if let f = fileArg, f.contains("\n") || f.contains("\r") {
        throw ValidationError("Newlines not allowed in file")
      }
      if let fn = functionArg, fn.contains("\n") || fn.contains("\r") {
        throw ValidationError("Newlines not allowed in function")
      }

      let command: String
      if let file = fileArg, let line = lineArg {
        command = "breakpoint set --file \(file) --line \(line)"
      } else if let function = functionArg {
        command = "breakpoint set --name \(function)"
      } else {
        throw ValidationError("Either --file and --line, or --function is required")
      }

      let pid = try await target.resolvePID()
      let result = try await DebuggerOneShot.withSession(pid: pid) { session in
        let output = try await session.sendCommand(command)
        guard let breakpointId = DebuggerProvider.parseBreakpointOutput(output) else {
          throw ValidationError("No breakpoint created — check file path or function name")
        }
        let resolved = output.lowercased().contains("resolved")
          || !output.lowercased().contains("unresolved")
        return DebuggerProvider.BreakpointResult(breakpointId: breakpointId, resolved: resolved)
      }

      if useJSON {
        print(try WorkflowJSONRenderer.renderJSON(result))
      } else {
        print(DebugRenderer.renderBreakpoint(result))
      }
    } catch {
      try rethrowOrJSONError(error, json: useJSON)
    }
  }
}

// MARK: - debug breakpoint remove

struct DebugBreakpointRemove: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "remove",
    abstract: "Remove a breakpoint by ID (one-shot)."
  )

  @OptionGroup var target: TargetOptions

  @Option(help: "Breakpoint ID to remove.")
  var breakpointId: Int

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    let useJSON = shouldOutputJSON(flag: json)
    // Capture by value before @Sendable closure
    let bpId = self.breakpointId
    do {
      let pid = try await target.resolvePID()
      let result = try await DebuggerOneShot.withSession(pid: pid) { session in
        let output = try await session.sendCommand("breakpoint delete \(bpId)")
        let removed = output.contains("breakpoint deleted") || output.contains("breakpoints deleted")
        if !removed {
          throw ValidationError("Breakpoint ID \(bpId) not found")
        }
        return DebuggerProvider.RemoveBreakpointResult(removed: true)
      }
      if useJSON {
        print(try WorkflowJSONRenderer.renderJSON(result))
      } else {
        print(DebugRenderer.renderRemoveBreakpoint(result))
      }
    } catch {
      try rethrowOrJSONError(error, json: useJSON)
    }
  }
}

// MARK: - debug continue

struct DebugContinue: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "continue",
    abstract: "Continue, step over, step into, or step out (one-shot)."
  )

  @OptionGroup var target: TargetOptions

  @Option(help: "Execution mode: continue, step-over, step-into, step-out (default: continue).")
  var mode: String = "continue"

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    let useJSON = shouldOutputJSON(flag: json)
    // Normalize hyphenated CLI mode to underscore for DebuggerProvider
    let normalizedMode = mode.replacingOccurrences(of: "-", with: "_")
    let command: String
    switch normalizedMode {
    case "step_over": command = "next"
    case "step_into": command = "step"
    case "step_out": command = "finish"
    default: command = "continue"
    }
    do {
      let pid = try await target.resolvePID()
      let result = try await DebuggerOneShot.withSession(pid: pid) { session in
        // 10-second timeout per spec I/O matrix
        let output = try await session.sendCommand(command, timeout: 10)
        return DebuggerProvider.parseContinueOutput(output)
      }
      if useJSON {
        print(try WorkflowJSONRenderer.renderJSON(result))
      } else {
        print(DebugRenderer.renderContinue(result))
      }
    } catch {
      try rethrowOrJSONError(error, json: useJSON)
    }
  }
}

// MARK: - debug run

struct DebugRun: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "run",
    abstract: "Run an arbitrary LLDB command and return raw output (one-shot)."
  )

  @OptionGroup var target: TargetOptions

  @Option(help: "Raw LLDB command string (e.g. memory read 0x...).")
  var command: String

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    let useJSON = shouldOutputJSON(flag: json)
    // Capture by value before @Sendable closure
    let cmd = self.command
    do {
      guard !cmd.contains("\n"), !cmd.contains("\r") else {
        throw ValidationError("Newlines not allowed in command")
      }
      let pid = try await target.resolvePID()
      let result = try await DebuggerOneShot.withSession(pid: pid) { session in
        let output = try await session.sendCommand(cmd)
        return DebuggerProvider.CommandResult(output: output)
      }
      if useJSON {
        print(try WorkflowJSONRenderer.renderJSON(result))
      } else {
        print(DebugRenderer.renderCommand(result))
      }
    } catch {
      try rethrowOrJSONError(error, json: useJSON)
    }
  }
}

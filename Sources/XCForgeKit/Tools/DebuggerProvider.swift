import Foundation
import MCP

// MARK: - DebuggerProviderError

public enum DebuggerProviderError: Error, CustomStringConvertible {
  case sessionNotFound(String)
  case invalidInput(String)
  case notStopped(String)
  case breakpointNotFound(Int)
  case attachFailed(String)

  public var description: String {
    switch self {
    case .sessionNotFound(let id):
      return "Session not found or expired: \(id)"
    case .invalidInput(let msg):
      return "Invalid input: \(msg)"
    case .notStopped(let detail):
      return "Process is not stopped at a frame: \(detail)"
    case .breakpointNotFound(let id):
      return "Breakpoint ID \(id) not found"
    case .attachFailed(let msg):
      return "Attach failed: \(msg)"
    }
  }
}

// MARK: - Result Types

public enum DebuggerProvider {

  public struct AttachResult: Codable, Sendable {
    public let sessionId: String
    public let pid: Int32
    public let status: String
    public init(sessionId: String, pid: Int32, status: String) {
      self.sessionId = sessionId
      self.pid = pid
      self.status = status
    }
  }

  public struct DetachResult: Codable, Sendable {
    public let detached: Bool
    public init(detached: Bool) { self.detached = detached }
  }

  public struct BreakpointResult: Codable, Sendable {
    public let breakpointId: Int
    public let resolved: Bool
    public init(breakpointId: Int, resolved: Bool) {
      self.breakpointId = breakpointId
      self.resolved = resolved
    }
  }

  public struct RemoveBreakpointResult: Codable, Sendable {
    public let removed: Bool
    public init(removed: Bool) { self.removed = removed }
  }

  public struct InspectResult: Codable, Sendable {
    public let expression: String
    public let type: String
    public let value: String
    public let summary: String
    public init(expression: String, type: String, value: String, summary: String) {
      self.expression = expression
      self.type = type
      self.value = value
      self.summary = summary
    }
  }

  public struct FrameInfo: Codable, Sendable {
    public let frameIndex: Int
    public let address: String
    public let symbol: String
    public let file: String?
    public let line: Int?
    public init(frameIndex: Int, address: String, symbol: String, file: String?, line: Int?) {
      self.frameIndex = frameIndex
      self.address = address
      self.symbol = symbol
      self.file = file
      self.line = line
    }
  }

  public struct ContinueResult: Codable, Sendable {
    public let stopReason: String
    public let threadIndex: Int
    public let frameIndex: Int
    public init(stopReason: String, threadIndex: Int, frameIndex: Int) {
      self.stopReason = stopReason
      self.threadIndex = threadIndex
      self.frameIndex = frameIndex
    }
  }

  public struct CommandResult: Codable, Sendable {
    public let output: String
    public init(output: String) { self.output = output }
  }
}

// MARK: - Tool Definitions

extension DebuggerProvider {

  public static let tools: [Tool] = [
    Tool(
      name: "lldb_attach",
      description: "Attach LLDB to a running simulator process. Returns a sessionId for subsequent tool calls.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "bundleId": .object([
            "type": .string("string"),
            "description": .string("App bundle ID on the booted simulator. Mutually exclusive with pid."),
          ]),
          "pid": .object([
            "type": .string("integer"),
            "description": .string("Process ID to attach to. Mutually exclusive with bundleId."),
          ]),
        ]),
      ])
    ),
    Tool(
      name: "lldb_detach",
      description: "Detach LLDB and destroy the session. Silently succeeds if the session is already gone.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "sessionId": .object([
            "type": .string("string"),
            "description": .string("Session ID returned by lldb_attach."),
          ])
        ]),
        "required": .array([.string("sessionId")]),
      ])
    ),
    Tool(
      name: "lldb_set_breakpoint",
      description: "Set a breakpoint by file+line or function name.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "sessionId": .object([
            "type": .string("string"),
            "description": .string("Session ID returned by lldb_attach."),
          ]),
          "file": .object([
            "type": .string("string"),
            "description": .string("Source file name (e.g. Foo.swift). Used with line."),
          ]),
          "line": .object([
            "type": .string("integer"),
            "description": .string("Line number. Used with file."),
          ]),
          "function": .object([
            "type": .string("string"),
            "description": .string("Function or method name (e.g. -[FooVC viewDidLoad])."),
          ]),
        ]),
        "required": .array([.string("sessionId")]),
      ])
    ),
    Tool(
      name: "lldb_remove_breakpoint",
      description: "Remove a breakpoint by ID. Returns an error if the ID is unknown.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "sessionId": .object([
            "type": .string("string"),
            "description": .string("Session ID returned by lldb_attach."),
          ]),
          "breakpointId": .object([
            "type": .string("integer"),
            "description": .string("Breakpoint ID returned by lldb_set_breakpoint."),
          ]),
        ]),
        "required": .array([.string("sessionId"), .string("breakpointId")]),
      ])
    ),
    Tool(
      name: "lldb_inspect_variable",
      description: "Evaluate an expression in the current frame. Process must be stopped.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "sessionId": .object([
            "type": .string("string"),
            "description": .string("Session ID returned by lldb_attach."),
          ]),
          "expression": .object([
            "type": .string("string"),
            "description": .string("Expression to evaluate (e.g. self.count)."),
          ]),
        ]),
        "required": .array([.string("sessionId"), .string("expression")]),
      ])
    ),
    Tool(
      name: "lldb_backtrace",
      description: "Return stack frames for the current or specified thread. Process must be stopped.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "sessionId": .object([
            "type": .string("string"),
            "description": .string("Session ID returned by lldb_attach."),
          ]),
          "threadIndex": .object([
            "type": .string("integer"),
            "description": .string("Thread index (default 0)."),
          ]),
        ]),
        "required": .array([.string("sessionId")]),
      ])
    ),
    Tool(
      name: "lldb_continue",
      description: "Continue, step over, step into, or step out of the current frame.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "sessionId": .object([
            "type": .string("string"),
            "description": .string("Session ID returned by lldb_attach."),
          ]),
          "mode": .object([
            "type": .string("string"),
            "description": .string("Execution mode: continue, step_over, step_into, step_out (default: continue)."),
          ]),
        ]),
        "required": .array([.string("sessionId")]),
      ])
    ),
    Tool(
      name: "lldb_run_command",
      description: "Run an arbitrary LLDB command and return the raw output.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "sessionId": .object([
            "type": .string("string"),
            "description": .string("Session ID returned by lldb_attach."),
          ]),
          "command": .object([
            "type": .string("string"),
            "description": .string("Raw LLDB command string (e.g. memory read 0x...)."),
          ]),
        ]),
        "required": .array([.string("sessionId"), .string("command")]),
      ])
    ),
  ]

  // MARK: - Input Types

  struct AttachInput: Decodable {
    let bundleId: String?
    let pid: Int32?
  }

  struct SessionInput: Decodable {
    let sessionId: String
  }

  struct SetBreakpointInput: Decodable {
    let sessionId: String
    let file: String?
    let line: Int?
    let function: String?
  }

  struct RemoveBreakpointInput: Decodable {
    let sessionId: String
    let breakpointId: Int
  }

  struct InspectInput: Decodable {
    let sessionId: String
    let expression: String
  }

  struct BacktraceInput: Decodable {
    let sessionId: String
    let threadIndex: Int?
  }

  struct ContinueInput: Decodable {
    let sessionId: String
    let mode: String?
  }

  struct RunCommandInput: Decodable {
    let sessionId: String
    let command: String
  }
}

// MARK: - Dispatch

extension DebuggerProvider: ToolProvider {
  public static func dispatch(_ name: String, _ args: [String: Value]?, env: Environment) async -> CallTool.Result? {
    switch name {
    case "lldb_attach": return await performAttach(args)
    case "lldb_detach": return await performDetach(args)
    case "lldb_set_breakpoint": return await performSetBreakpoint(args)
    case "lldb_remove_breakpoint": return await performRemoveBreakpoint(args)
    case "lldb_inspect_variable": return await performInspectVariable(args)
    case "lldb_backtrace": return await performBacktrace(args)
    case "lldb_continue": return await performContinue(args)
    case "lldb_run_command": return await performRunCommand(args)
    default: return nil
    }
  }
}

// MARK: - Tool Implementations

extension DebuggerProvider {

  // MARK: lldb_attach

  static func performAttach(_ args: [String: Value]?) async -> CallTool.Result {
    switch ToolInput.decode(AttachInput.self, from: args) {
    case .failure(let err): return err
    case .success(let input):
      do {
        let pid: Int32
        if let bundleId = input.bundleId {
          pid = try await DebuggerOneShot.resolveProcessID(for: bundleId)
        } else if let rawPid = input.pid {
          pid = rawPid
        } else {
          return .fail("Either bundleId or pid is required")
        }

        let sessionID = UUID().uuidString
        let session = try await DebuggerSession.launch(sessionID: sessionID)
        _ = await DebuggerSessionRegistry.shared.create(session: session)

        let attachOutput = try await session.sendCommand("process attach --pid \(pid)")
        let lower = attachOutput.lowercased()

        if lower.contains("error:") || lower.contains("failed") {
          await DebuggerSessionRegistry.shared.remove(id: sessionID)
          return .fail("Attach failed: \(attachOutput)")
        }

        let result = AttachResult(sessionId: sessionID, pid: pid, status: "stopped")
        let data = try JSONEncoder().encode(result)
        return .ok(String(data: data, encoding: .utf8) ?? "{}")
      } catch {
        return .fail("Attach error: \(error)")
      }
    }
  }

  // MARK: lldb_detach

  static func performDetach(_ args: [String: Value]?) async -> CallTool.Result {
    switch ToolInput.decode(SessionInput.self, from: args) {
    case .failure(let err): return err
    case .success(let input):
      // Silently succeeds even if session is already gone (per spec).
      await DebuggerSessionRegistry.shared.remove(id: input.sessionId)
      let result = DetachResult(detached: true)
      guard let data = try? JSONEncoder().encode(result),
        let json = String(data: data, encoding: .utf8)
      else {
        return .ok("{\"detached\":true}")
      }
      return .ok(json)
    }
  }

  // MARK: lldb_set_breakpoint

  static func performSetBreakpoint(_ args: [String: Value]?) async -> CallTool.Result {
    switch ToolInput.decode(SetBreakpointInput.self, from: args) {
    case .failure(let err): return err
    case .success(let input):
      // Sanitize inputs for newline injection
      if let file = input.file, file.contains("\n") || file.contains("\r") {
        return .fail("Invalid input: Newlines not allowed in file")
      }
      if let function = input.function, function.contains("\n") || function.contains("\r") {
        return .fail("Invalid input: Newlines not allowed in function")
      }

      let session: DebuggerSession
      do {
        session = try await DebuggerSessionRegistry.shared.lookupSession(for: input.sessionId)
      } catch {
        return .fail("Session not found or expired")
      }

      let command: String
      if let file = input.file, let line = input.line {
        command = "breakpoint set --file \(file) --line \(line)"
      } else if let function = input.function {
        command = "breakpoint set --name \(function)"
      } else {
        return .fail("Invalid input: Either file+line or function is required")
      }

      do {
        let output = try await session.sendCommand(command)
        guard let breakpointId = parseBreakpointOutput(output) else {
          return .fail("No breakpoint created — check file path or function name")
        }
        let resolved = output.lowercased().contains("resolved") || !output.lowercased().contains("unresolved")
        let result = BreakpointResult(breakpointId: breakpointId, resolved: resolved)
        let data = try JSONEncoder().encode(result)
        return .ok(String(data: data, encoding: .utf8) ?? "{}")
      } catch {
        return .fail("Set breakpoint error: \(error)")
      }
    }
  }

  // MARK: lldb_remove_breakpoint

  static func performRemoveBreakpoint(_ args: [String: Value]?) async -> CallTool.Result {
    switch ToolInput.decode(RemoveBreakpointInput.self, from: args) {
    case .failure(let err): return err
    case .success(let input):
      let session: DebuggerSession
      do {
        session = try await DebuggerSessionRegistry.shared.lookupSession(for: input.sessionId)
      } catch {
        return .fail("Session not found or expired")
      }

      do {
        let output = try await session.sendCommand("breakpoint delete \(input.breakpointId)")
        let removed = output.contains("breakpoint deleted") || output.contains("breakpoints deleted")
        if !removed {
          return .fail("Breakpoint ID \(input.breakpointId) not found")
        }
        let result = RemoveBreakpointResult(removed: true)
        let data = try JSONEncoder().encode(result)
        return .ok(String(data: data, encoding: .utf8) ?? "{}")
      } catch {
        return .fail("Remove breakpoint error: \(error)")
      }
    }
  }

  // MARK: lldb_inspect_variable

  static func performInspectVariable(_ args: [String: Value]?) async -> CallTool.Result {
    switch ToolInput.decode(InspectInput.self, from: args) {
    case .failure(let err): return err
    case .success(let input):
      // Sanitize for newline injection
      guard !input.expression.contains("\n"), !input.expression.contains("\r") else {
        return .fail("Invalid input: Newlines not allowed in expression")
      }

      let session: DebuggerSession
      do {
        session = try await DebuggerSessionRegistry.shared.lookupSession(for: input.sessionId)
      } catch {
        return .fail("Session not found or expired")
      }

      do {
        let output = try await session.sendCommand("expression \(input.expression)")
        let lower = output.lowercased()

        if lower.contains("not stopped") || lower.contains("no process")
          || lower.hasPrefix("error:")
          || output.contains("\nerror:")
        {
          return .fail("not stopped at a frame: \(output)")
        }

        // Parse LLDB expression output: ($type) $tmp = $value
        let parsed = parseExpressionOutput(output, expression: input.expression)
        let data = try JSONEncoder().encode(parsed)
        return .ok(String(data: data, encoding: .utf8) ?? "{}")
      } catch {
        return .fail("Inspect error: \(error)")
      }
    }
  }

  // MARK: lldb_backtrace

  static func performBacktrace(_ args: [String: Value]?) async -> CallTool.Result {
    switch ToolInput.decode(BacktraceInput.self, from: args) {
    case .failure(let err): return err
    case .success(let input):
      let session: DebuggerSession
      do {
        session = try await DebuggerSessionRegistry.shared.lookupSession(for: input.sessionId)
      } catch {
        return .fail("Session not found or expired")
      }

      let threadIndex = input.threadIndex ?? 0

      do {
        // For non-zero threadIndex, make TWO sequential sendCommand calls.
        // Do NOT embed \n in a single call — it corrupts prompt detection.
        if threadIndex != 0 {
          _ = try await session.sendCommand("thread select \(threadIndex)")
        }
        let output = try await session.sendCommand("bt")
        let lower = output.lowercased()
        if lower.contains("error:") || lower.contains("no process") || lower.contains("not stopped") {
          return .fail("Process is not stopped at a frame: \(output)")
        }

        let frames = parseBacktraceOutput(output)
        let data = try JSONEncoder().encode(frames)
        return .ok(String(data: data, encoding: .utf8) ?? "[]")
      } catch {
        return .fail("Backtrace error: \(error)")
      }
    }
  }

  // MARK: lldb_continue

  static func performContinue(_ args: [String: Value]?) async -> CallTool.Result {
    switch ToolInput.decode(ContinueInput.self, from: args) {
    case .failure(let err): return err
    case .success(let input):
      let session: DebuggerSession
      do {
        session = try await DebuggerSessionRegistry.shared.lookupSession(for: input.sessionId)
      } catch {
        return .fail("Session not found or expired")
      }

      let mode = input.mode ?? "continue"
      let command: String
      switch mode {
      case "step_over": command = "next"
      case "step_into": command = "step"
      case "step_out": command = "finish"
      default: command = "continue"
      }

      do {
        // 10-second timeout per spec I/O matrix
        let output = try await session.sendCommand(command, timeout: 10)
        let result = parseContinueOutput(output)
        let data = try JSONEncoder().encode(result)
        return .ok(String(data: data, encoding: .utf8) ?? "{}")
      } catch {
        return .fail("Continue error: \(error)")
      }
    }
  }

  // MARK: lldb_run_command

  static func performRunCommand(_ args: [String: Value]?) async -> CallTool.Result {
    switch ToolInput.decode(RunCommandInput.self, from: args) {
    case .failure(let err): return err
    case .success(let input):
      // Sanitize for newline injection
      guard !input.command.contains("\n"), !input.command.contains("\r") else {
        return .fail("Invalid input: Newlines not allowed in command")
      }

      let session: DebuggerSession
      do {
        session = try await DebuggerSessionRegistry.shared.lookupSession(for: input.sessionId)
      } catch {
        return .fail("Session not found or expired")
      }

      do {
        let output = try await session.sendCommand(input.command)
        let result = CommandResult(output: output)
        let data = try JSONEncoder().encode(result)
        return .ok(String(data: data, encoding: .utf8) ?? "{}")
      } catch {
        return .fail("Run command error: \(error)")
      }
    }
  }
}

// MARK: - Output Parsers

extension DebuggerProvider {

  /// Parse LLDB breakpoint output and return the breakpoint ID.
  /// Returns nil when no "Breakpoint N:" line is found — callers return `.fail` on nil.
  /// Returning nil (not 0) prevents callers from issuing `breakpoint delete 0`
  /// which silently deletes all breakpoints.
  public static func parseBreakpointOutput(_ output: String) -> Int? {
    // LLDB outputs: "Breakpoint 1: ..." or "Breakpoint 1 (1 locations)"
    for line in output.split(separator: "\n") {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.hasPrefix("Breakpoint ") {
        let rest = String(trimmed.dropFirst("Breakpoint ".count))
        let numberPart = rest.prefix(while: { $0.isNumber })
        if let id = Int(numberPart), id > 0 {
          return id
        }
      }
    }
    return nil
  }

  /// Parse LLDB continue/step output into a `ContinueResult`.
  /// Uses specific "stop reason = X" patterns — NOT loose `contains("step")`
  /// which matches symbol names and produces incorrect stopReason values.
  public static func parseContinueOutput(_ output: String) -> ContinueResult {
    let lower = output.lowercased()

    var stopReason = "unknown"
    if lower.contains("stop reason = breakpoint") {
      stopReason = "breakpoint"
    } else if lower.contains("stop reason = step") {
      stopReason = "step"
    } else if lower.contains("stop reason = signal") {
      stopReason = "signal"
    } else if lower.contains("exited") || lower.contains("stop reason = exception") {
      stopReason = "exit"
    }

    // Parse thread index from output: "* thread #N, ..."
    var threadIndex = 0
    for line in output.split(separator: "\n") {
      let t = line.trimmingCharacters(in: .whitespaces)
      if t.hasPrefix("* thread #") || t.hasPrefix("thread #") {
        let digits = t.dropFirst(t.hasPrefix("* thread #") ? "* thread #".count : "thread #".count)
          .prefix(while: { $0.isNumber })
        if let n = Int(digits) {
          threadIndex = n - 1  // LLDB uses 1-based thread numbers
          break
        }
      }
    }

    // Parse frame index from output: "* frame #N:"
    var frameIndex = 0
    for line in output.split(separator: "\n") {
      let t = line.trimmingCharacters(in: .whitespaces)
      if t.hasPrefix("* frame #") || t.hasPrefix("frame #") {
        let digits = t.dropFirst(t.hasPrefix("* frame #") ? "* frame #".count : "frame #".count)
          .prefix(while: { $0.isNumber })
        if let n = Int(digits) {
          frameIndex = n
          break
        }
      }
    }

    return ContinueResult(stopReason: stopReason, threadIndex: threadIndex, frameIndex: frameIndex)
  }

  /// Parse LLDB `bt` output into an array of `FrameInfo`.
  public static func parseBacktraceOutput(_ output: String) -> [FrameInfo] {
    var frames: [FrameInfo] = []

    for line in output.split(separator: "\n") {
      let t = line.trimmingCharacters(in: .whitespaces)
      // LLDB format: "  frame #0: 0xdeadbeef module`symbol + offset at file.swift:line:col"
      let stripped = t.hasPrefix("* ") ? String(t.dropFirst(2)) : t
      guard stripped.hasPrefix("frame #") else { continue }

      let rest = stripped.dropFirst("frame #".count)
      let indexDigits = rest.prefix(while: { $0.isNumber })
      guard let frameIndex = Int(indexDigits) else { continue }

      let afterIndex = rest.dropFirst(indexDigits.count)
      // Skip ": "
      let addressPart = afterIndex.drop(while: { $0 == ":" || $0 == " " })

      // Extract hex address
      var address = ""
      var remaining = addressPart
      let addrPart = remaining.prefix(while: { $0 == "0" || $0 == "x" || $0.isHexDigit })
      address = String(addrPart)
      remaining = remaining.dropFirst(addrPart.count)

      // Everything after address is "module`symbol at file:line"
      let symbolPart = remaining.trimmingCharacters(in: .whitespaces)
      var symbol = symbolPart
      var file: String?
      var fileLine: Int?

      if let atRange = symbolPart.range(of: " at ") {
        symbol = String(symbolPart[symbolPart.startIndex..<atRange.lowerBound])
        let filePart = String(symbolPart[atRange.upperBound...])
        // "file.swift:42:5" — split off column
        let components = filePart.components(separatedBy: ":")
        if let first = components.first { file = first }
        if components.count > 1, let ln = Int(components[1]) { fileLine = ln }
      }

      frames.append(FrameInfo(
        frameIndex: frameIndex,
        address: address,
        symbol: symbol,
        file: file,
        line: fileLine
      ))
    }

    return frames
  }

  /// Parse LLDB `expression` output into an `InspectResult`.
  /// LLDB format: "($type) $tmp = $value\n  Summary: ..."
  public static func parseExpressionOutput(_ output: String, expression: String) -> InspectResult {
    var typeName = ""
    var value = ""
    var summary = ""

    for line in output.split(separator: "\n") {
      let t = line.trimmingCharacters(in: .whitespaces)
      // Pattern: "($Int) $R0 = 42"
      if t.hasPrefix("(") {
        if let closeParens = t.firstIndex(of: ")") {
          typeName = String(t[t.index(after: t.startIndex)..<closeParens])
          let after = String(t[t.index(after: closeParens)...]).trimmingCharacters(in: .whitespaces)
          // Skip "= " or "$tmpN = "
          if let eqRange = after.range(of: " = ") {
            value = String(after[eqRange.upperBound...])
          } else {
            value = after
          }
        }
      } else if t.hasPrefix("Summary:") {
        summary = String(t.dropFirst("Summary:".count)).trimmingCharacters(in: .whitespaces)
      }
    }

    return InspectResult(
      expression: expression,
      type: typeName,
      value: value,
      summary: summary
    )
  }
}

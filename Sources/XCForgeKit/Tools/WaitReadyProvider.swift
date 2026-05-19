import Foundation
import MCP

/// `wait_ready` — the single new MCP tool: a standalone launch-readiness gate
/// backed by the shared `ReadinessProbe`. Reused verbatim by the
/// `xcforge wait-ready` CLI command (Pose model: shared pure func).
public enum WaitReadyTools {
  public static let group = "wait-ready"

  public struct WaitReadyExecution: Codable, Sendable {
    public let ready: Bool
    public let mode: String
    public let elapsedMs: Int
    public let satisfied: [String]
    public let signals: [String]
    public let reason: String?
  }

  public static let tools: [Tool] = [
    Tool(
      name: "wait_ready",
      description: """
        Block until the screen is actually ready, gating on real signals \
        instead of a blind sleep. Signal grammar (comma = all must hold): \
        `launch-complete`, `a11y:<accessibilityId>`, `text:<substring>`. \
        Detects via AXP first (no WDA session needed), WDA fallback, else a \
        reported degraded wait. Returns ready/mode/elapsedMs/satisfied so an \
        agent can tell a real gate from a degraded sleep.
        """,
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "simulator": .object([
            "type": .string("string"),
            "description": .string(
              "Simulator name or UDID. Auto-detected from booted simulator if omitted."),
          ]),
          "for": .object([
            "type": .string("string"),
            "description": .string(
              "Readiness signal(s), comma-separated (all must hold). e.g. `a11y:home.title` or `launch-complete,text:Welcome`."
            ),
          ]),
          "timeout": .object([
            "type": .string("number"),
            "description": .string(
              "Ceiling in seconds. Capture happens the instant the signal holds, so a high ceiling costs nothing on the fast path. 0 skips the gate (pass-through): reports ready. Default 20."
            ),
          ]),
        ]),
      ])
    )
  ]

  // MARK: - Input

  struct WaitReadyInput: Decodable {
    let simulator: String?
    let `for`: String?
    let timeout: Double?
  }

  // MARK: - Shared Execution

  /// Pure, reused by both MCP dispatch and the CLI command.
  public static func executeWaitReady(
    signalSpec: String,
    timeout: Double,
    pollMs: Int = 150,
    simulator: String? = nil,
    env: Environment = .live
  ) async -> WaitReadyExecution {
    let parsed = ReadinessProbe.Signal.parseSpec(signalSpec)
    let result = await ReadinessProbe.waitReady(
      signals: parsed.signals,
      timeout: timeout,
      pollMs: pollMs,
      specWasUnparseable: parsed.allUnparseable,
      simulator: simulator,
      env: env
    )
    return WaitReadyExecution(
      ready: result.ready,
      mode: result.mode.rawValue,
      elapsedMs: result.elapsedMs,
      satisfied: result.satisfied,
      signals: parsed.signals.map(\.raw),
      reason: result.reason
    )
  }

  // MARK: - MCP Dispatch

  static func waitReady(_ args: [String: Value]?, env: Environment) async -> CallTool.Result {
    switch ToolInput.decode(WaitReadyInput.self, from: args) {
    case .failure(let err): return err
    case .success(let input):
      let exec = await executeWaitReady(
        signalSpec: input.for ?? "launch-complete",
        timeout: input.timeout ?? 20,
        simulator: input.simulator,
        env: env
      )
      var lines: [String] = []
      lines.append(exec.ready ? "Ready" : "NOT ready")
      lines.append("mode: \(exec.mode)")
      lines.append("elapsedMs: \(exec.elapsedMs)")
      lines.append("signals: \(exec.signals.joined(separator: ", "))")
      lines.append("satisfied: \(exec.satisfied.joined(separator: ", "))")
      if let reason = exec.reason { lines.append("reason: \(reason)") }
      let body = lines.joined(separator: "\n")
      return exec.ready ? .ok(body) : .fail(body)
    }
  }
}

extension WaitReadyTools: ToolProvider {
  public static func dispatch(_ name: String, _ args: [String: Value]?, env: Environment) async
    -> CallTool.Result?
  {
    switch name {
    case "wait_ready": return await waitReady(args, env: env)
    default: return nil
    }
  }
}

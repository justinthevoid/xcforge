import Foundation
import MCP

public enum PlanTools {
  public static let tools: [Tool] = [
    Tool(
      name: "run_plan",
      description: """
        Execute a multi-step UI automation plan server-side. \
        Dramatically reduces round-trips: 1 call replaces 15+ sequential find/click/verify calls. \
        Each step is a JSON object with a single action key (find, click, verify, etc.). \
        Steps run sequentially. Use "$var" to bind and reference elements across steps. \
        If a "judge" or "handleUnexpected" step is reached, the plan suspends — \
        call run_plan_decide with the returned session_id to resume. \
        Returns a structured report with per-step status and optional screenshots.
        """,
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "steps": .object([
            "type": .string("array"),
            "description": .string(
              """
              Array of step objects. Each has one action key: \
              navigate, navigateBack, find, findAll, click, doubleTap, longPress, \
              swipe, typeText, screenshot, wait, waitFor, verify, ifElementExists, \
              judge, handleUnexpected. Example: [{"find": "Login", "as": "$btn"}, {"click": "$btn"}]
              """),
            "items": .object(["type": .string("object")]),
          ]),
          "error_strategy": .object([
            "type": .string("string"),
            "description": .string(
              "What to do on step failure: 'abort_with_screenshot' (default), 'abort', 'continue'"),
          ]),
          "timeout": .object([
            "type": .string("number"),
            "description": .string("Max plan execution time in seconds. Default: 120"),
          ]),
        ]),
        "required": .array([.string("steps")]),
      ])
    ),
    Tool(
      name: "run_plan_decide",
      description: """
        Resume a suspended plan after a judge/handleUnexpected step. \
        Provide the session_id from the run_plan response and your decision. \
        Decisions: 'accept' (accept alert/continue), 'dismiss' (dismiss alert), \
        'skip' (skip this step), 'abort' (stop the plan), \
        or any freeform text as guidance for the next step. \
        Returns the merged report covering all steps (before and after suspend).
        """,
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "session_id": .object([
            "type": .string("string"),
            "description": .string("Session ID from the suspended run_plan response"),
          ]),
          "decision": .object([
            "type": .string("string"),
            "description": .string(
              "Your decision: 'accept', 'dismiss', 'skip', 'abort', or freeform guidance"),
          ]),
        ]),
        "required": .array([.string("session_id"), .string("decision")]),
      ])
    ),
  ]

  // MARK: - Input Types

  struct RunPlanInput: Decodable {
    let steps: [Value]
    let error_strategy: String?
    let timeout: Double?
  }

  struct RunPlanDecideInput: Decodable {
    let session_id: String
    let decision: String
  }

  // MARK: - Handlers

  public static func runPlan(_ args: [String: Value]?, env: Environment = .live) async
    -> CallTool.Result
  {
    switch ToolInput.decode(RunPlanInput.self, from: args) {
    case .failure(let err): return err
    case .success(let input): return await runPlanImpl(input, env: env)
    }
  }

  private static func runPlanImpl(_ input: RunPlanInput, env: Environment) async -> CallTool.Result
  {
    // Parse steps
    let steps: [PlanStep]
    do {
      steps = try PlanParser.parse(input.steps)
    } catch {
      return .fail("Plan parse error: \(error)")
    }

    // Empty plan → immediate success
    if steps.isEmpty {
      let report = PlanReport(steps: [])
      return encodeReport(report)
    }

    // Parse options
    let strategyStr = input.error_strategy ?? "abort_with_screenshot"
    let strategy = ErrorStrategy(rawValue: strategyStr) ?? .abortWithScreenshot
    let timeout = input.timeout ?? 120

    // Ensure WDA is running
    do {
      let sim = try await env.session.resolveSimulator(nil)
      try await env.wdaClient.ensureWDARunning(simulator: sim)
    } catch {
      return .fail("WDA setup failed: \(error)")
    }

    // Execute
    let executor = PlanExecutor(
      session: env.session, wdaClient: env.wdaClient, errorStrategy: strategy,
      timeoutSeconds: timeout)
    let result = await executor.execute(steps: steps)

    switch result {
    case .completed(let report):
      return encodeReport(report)

    case .suspended(let suspended, _):
      let sessionId = await PlanSessionStore.shared.store(suspended)
      let report = PlanReport(
        steps: suspended.completedResults,
        sessionId: sessionId,
        suspendQuestion: suspended.question
      )
      return encodeSuspendedReport(report, screenshot: suspended.screenshotBase64)
    }
  }

  public static func runPlanDecide(_ args: [String: Value]?, env: Environment = .live) async
    -> CallTool.Result
  {
    switch ToolInput.decode(RunPlanDecideInput.self, from: args) {
    case .failure(let err): return err
    case .success(let input): return await runPlanDecideImpl(input, env: env)
    }
  }

  private static func runPlanDecideImpl(_ input: RunPlanDecideInput, env: Environment) async
    -> CallTool.Result
  {
    let sessionId = input.session_id
    let decision = input.decision

    // Consume session
    guard let suspended = await PlanSessionStore.shared.consume(sessionId) else {
      return .fail(
        "Session '\(sessionId)' not found or expired (5-minute TTL). Re-run the plan to start fresh."
      )
    }

    // Handle abort decision
    if decision == "abort" {
      let report = PlanReport(steps: suspended.completedResults)
      return encodeReport(report)
    }

    // Handle skip decision — skip the suspended step and continue
    if decision == "skip" {
      let executor = PlanExecutor(
        session: env.session, wdaClient: env.wdaClient, errorStrategy: suspended.errorStrategy,
        timeoutSeconds: suspended.timeoutSeconds)
      executor.restore(
        priorResults: suspended.completedResults,
        savedBindings: suspended.variableBindings,
        startTime: suspended.startTime
      )
      let result = await executor.execute(steps: suspended.steps, startAt: suspended.pauseIndex + 1)
      switch result {
      case .completed(let report):
        return encodeReport(report)
      case .suspended(let newSuspended, _):
        let newSessionId = await PlanSessionStore.shared.store(newSuspended)
        let report = PlanReport(
          steps: newSuspended.completedResults,
          sessionId: newSessionId,
          suspendQuestion: newSuspended.question
        )
        return encodeSuspendedReport(report, screenshot: newSuspended.screenshotBase64)
      }
    }

    // Handle accept/dismiss — try to handle alert first
    if decision == "accept" || decision == "dismiss" {
      do {
        if decision == "accept" {
          _ = try await env.wdaClient.acceptAlert()
        } else {
          _ = try await env.wdaClient.dismissAlert()
        }
      } catch {
        // Alert handling failed — continue anyway (the decision was to proceed)
      }
    }

    // Resume execution from next step
    let executor = PlanExecutor(
      session: env.session, wdaClient: env.wdaClient, errorStrategy: suspended.errorStrategy,
      timeoutSeconds: suspended.timeoutSeconds)
    executor.restore(
      priorResults: suspended.completedResults,
      savedBindings: suspended.variableBindings,
      startTime: suspended.startTime
    )
    let result = await executor.execute(steps: suspended.steps, startAt: suspended.pauseIndex + 1)

    switch result {
    case .completed(let report):
      return encodeReport(report)
    case .suspended(let newSuspended, _):
      let newSessionId = await PlanSessionStore.shared.store(newSuspended)
      let report = PlanReport(
        steps: newSuspended.completedResults,
        sessionId: newSessionId,
        suspendQuestion: newSuspended.question
      )
      return encodeSuspendedReport(report, screenshot: newSuspended.screenshotBase64)
    }
  }

  // MARK: - Result Encoding

  private static func encodeReport(_ report: PlanReport) -> CallTool.Result {
    do {
      let json = try WorkflowJSONRenderer.renderJSON(report)
      return .init(
        content: [.text(text: json, annotations: nil, _meta: nil)], isError: report.failed > 0)
    } catch {
      return .fail("Failed to encode report: \(error)")
    }
  }

  private static func encodeSuspendedReport(_ report: PlanReport, screenshot: String?)
    -> CallTool.Result
  {
    do {
      let json = try WorkflowJSONRenderer.renderJSON(report)
      var content: [Tool.Content] = [.text(text: json, annotations: nil, _meta: nil)]
      if let ss = screenshot {
        content.append(.image(data: ss, mimeType: "image/jpeg", annotations: nil, _meta: nil))
      }
      return .init(content: content, isError: false)
    } catch {
      return .fail("Failed to encode report: \(error)")
    }
  }
}

extension PlanTools: ToolProvider {
  public static func dispatch(_ name: String, _ args: [String: Value]?, env: Environment) async
    -> CallTool.Result?
  {
    switch name {
    case "run_plan": return await runPlan(args, env: env)
    case "run_plan_decide": return await runPlanDecide(args, env: env)
    default: return nil
    }
  }
}

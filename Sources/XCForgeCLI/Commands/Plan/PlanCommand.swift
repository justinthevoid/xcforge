import ArgumentParser
import Foundation
import MCP
import XCForgeKit

struct Plan: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "plan",
    abstract: "Execute multi-step UI automation plans.",
    subcommands: [PlanRun.self, PlanDecide.self]
  )
}

// MARK: - plan run

struct PlanRun: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "run",
    abstract: "Execute a UI automation plan from a JSON file or stdin."
  )

  @Option(help: "Path to a JSON file containing the plan steps array.")
  var file: String?

  @Flag(help: "Read plan JSON from stdin.")
  var stdin = false

  @Option(help: "Error strategy: abort_with_screenshot (default), abort, continue.")
  var errorStrategy: String = "abort_with_screenshot"

  @Option(help: "Max execution time in seconds. Default: 120.")
  var timeout: Double = 120

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    let useJSON = shouldOutputJSON(flag: json)
    var errorStrategy = self.errorStrategy
    var timeout = self.timeout

    // Read plan JSON
    let planJSON: String
    if let path = file {
      guard let data = FileManager.default.contents(atPath: path),
        let str = String(data: data, encoding: .utf8)
      else {
        print("Error: Could not read file at '\(path)'")
        throw ExitCode.failure
      }
      planJSON = str
    } else if stdin {
      var input = ""
      while let line = readLine(strippingNewline: false) {
        input += line
      }
      planJSON = input
    } else {
      print("Error: Provide --file <path> or --stdin")
      throw ExitCode.validationFailure
    }

    // Parse JSON — accept bare array or {"steps": [...]} wrapper
    guard let data = planJSON.data(using: .utf8),
      let raw = try? JSONSerialization.jsonObject(with: data)
    else {
      print("Error: Plan must be a JSON array of step objects, or an object with a \"steps\" array")
      throw ExitCode.failure
    }

    let parsed: [[String: Any]]
    if let array = raw as? [[String: Any]] {
      parsed = array
    } else if let wrapper = raw as? [String: Any],
      let steps = wrapper["steps"] as? [[String: Any]]
    {
      parsed = steps
      // Extract wrapper-level options as defaults (CLI flags take precedence)
      if let es = wrapper["error_strategy"] as? String {
        errorStrategy = es
      }
      if let t = wrapper["timeout"] as? Double {
        timeout = t
      } else if let t = wrapper["timeout"] as? Int {
        timeout = Double(t)
      }
    } else {
      print("Error: Plan must be a JSON array of step objects, or an object with a \"steps\" array")
      throw ExitCode.failure
    }

    // Convert to MCP Value
    let stepsValue = jsonToValue(parsed)

    guard case .array(let steps) = stepsValue else {
      print("Error: Plan must be a JSON array")
      throw ExitCode.failure
    }

    // Parse
    let planSteps: [PlanStep]
    do {
      planSteps = try PlanParser.parse(steps)
    } catch {
      print("Parse error: \(error)")
      throw ExitCode.failure
    }

    if planSteps.isEmpty {
      let report = PlanReport(steps: [])
      if useJSON {
        print(try WorkflowJSONRenderer.renderJSON(report))
      } else {
        print(PlanRenderer.render(report))
      }
      return
    }

    let strategy = ErrorStrategy(rawValue: errorStrategy) ?? .abortWithScreenshot

    // Ensure WDA
    let env = Environment.live
    do {
      let sim = try await env.session.resolveSimulator(nil)
      try await env.wdaClient.ensureWDARunning(simulator: sim)
    } catch {
      print("WDA setup failed: \(error)")
      throw ExitCode.failure
    }

    let executor = PlanExecutor(
      session: env.session, wdaClient: env.wdaClient, errorStrategy: strategy,
      timeoutSeconds: timeout)
    let result = await executor.execute(steps: planSteps)

    switch result {
    case .completed(let report):
      if useJSON {
        print(try WorkflowJSONRenderer.renderJSON(report))
      } else {
        print(PlanRenderer.render(report))
      }
      if report.failed > 0 { throw ExitCode.failure }

    case .suspended(let suspended, _):
      let sessionId = await PlanSessionStore.shared.store(suspended)
      let report = PlanReport(
        steps: suspended.completedResults,
        sessionId: sessionId,
        suspendQuestion: suspended.question
      )
      if useJSON {
        print(try WorkflowJSONRenderer.renderJSON(report))
      } else {
        print(PlanRenderer.render(report))
      }
    }
  }
}

// MARK: - plan decide

struct PlanDecide: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "decide",
    abstract: "Resume a suspended plan with a decision."
  )

  @Option(help: "Session ID from the suspended plan run.")
  var sessionId: String

  @Option(help: "Decision: accept, dismiss, skip, abort, or freeform guidance.")
  var decision: String

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    let useJSON = shouldOutputJSON(flag: json)
    let env = Environment.live
    guard let suspended = await PlanSessionStore.shared.consume(sessionId) else {
      let msg = "Session '\(sessionId)' not found or expired (5-minute TTL). Re-run the plan."
      if useJSON {
        let envelope = CLIErrorEnvelope(error: msg, code: "session_not_found")
        if let data = try? JSONEncoder().encode(envelope),
          let jsonString = String(data: data, encoding: .utf8)
        {
          fputs(jsonString + "\n", stderr)
        }
      } else {
        print(msg)
      }
      throw ExitCode.failure
    }

    if decision == "abort" {
      let report = PlanReport(steps: suspended.completedResults)
      if useJSON {
        print(try WorkflowJSONRenderer.renderJSON(report))
      } else {
        print(PlanRenderer.render(report))
      }
      return
    }

    if decision == "accept" || decision == "dismiss" {
      do {
        if decision == "accept" {
          _ = try await env.wdaClient.acceptAlert()
        } else {
          _ = try await env.wdaClient.dismissAlert()
        }
      } catch { /* continue anyway */  }
    }

    let startAt = decision == "skip" ? suspended.pauseIndex + 1 : suspended.pauseIndex + 1
    let executor = PlanExecutor(
      session: env.session, wdaClient: env.wdaClient, errorStrategy: suspended.errorStrategy,
      timeoutSeconds: suspended.timeoutSeconds)
    executor.restore(
      priorResults: suspended.completedResults,
      savedBindings: suspended.variableBindings,
      startTime: suspended.startTime
    )
    let result = await executor.execute(steps: suspended.steps, startAt: startAt)

    switch result {
    case .completed(let report):
      if useJSON {
        print(try WorkflowJSONRenderer.renderJSON(report))
      } else {
        print(PlanRenderer.render(report))
      }
      if report.failed > 0 { throw ExitCode.failure }

    case .suspended(let newSuspended, _):
      let newSessionId = await PlanSessionStore.shared.store(newSuspended)
      let report = PlanReport(
        steps: newSuspended.completedResults,
        sessionId: newSessionId,
        suspendQuestion: newSuspended.question
      )
      if useJSON {
        print(try WorkflowJSONRenderer.renderJSON(report))
      } else {
        print(PlanRenderer.render(report))
      }
    }
  }
}

// MARK: - JSON to MCP Value conversion

private func jsonToValue(_ array: [[String: Any]]) -> Value {
  .array(array.map { jsonObjectToValue($0) })
}

private func jsonObjectToValue(_ dict: [String: Any]) -> Value {
  var result: [String: Value] = [:]
  for (key, val) in dict {
    result[key] = anyToValue(val)
  }
  return .object(result)
}

private func anyToValue(_ val: Any) -> Value {
  // Order matters: Bool before NSNumber since Bool bridges to NSNumber in ObjC
  switch val {
  case let b as Bool: return .bool(b)
  case let s as String: return .string(s)
  case let n as NSNumber:
    // NSNumber can hold Int or Double — check if it's integral
    if CFNumberIsFloatType(n) {
      return .double(n.doubleValue)
    } else {
      return .int(n.intValue)
    }
  case let arr as [Any]: return .array(arr.map { anyToValue($0) })
  case let dict as [String: Any]: return jsonObjectToValue(dict)
  case is NSNull: return .null
  default: return .null
  }
}

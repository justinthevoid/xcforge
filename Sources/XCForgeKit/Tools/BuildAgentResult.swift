import Foundation
import MCP

/// The slim JSON build tools return over MCP unless `for: "human"` asks for the text report:
/// what happened, the errors with full paths, and where to look next.
extension BuildTools {
  struct AgentBuildResult: Codable, Equatable {
    var ok: Bool
    var summary: String
    var errors: [String]?
    var warnings: Int?
    var failureReason: String?
    var xcresult: String?
    var bundleId: String?
    var appPath: String?
    var diagnostic: String?
  }

  /// Build tools that return `AgentBuildResult` by default and take `for`.
  static let agentJSONTools: Set<String> = ["build_compile", "build_sim", "build_typecheck"]

  static let forProperty: Value = .object([
    "type": .string("string"),
    "enum": .array([.string("agent"), .string("human")]),
    "description": .string("'agent' (default) returns slim JSON; 'human' returns the text report."),
  ])

  /// Add `for` to the build tools that return agent JSON.
  static func augmentFor(_ tool: Tool) -> Tool {
    guard agentJSONTools.contains(tool.name), case .object(var schema) = tool.inputSchema,
      case .object(var properties)? = schema["properties"], properties["for"] == nil
    else { return tool }
    properties["for"] = forProperty
    schema["properties"] = .object(properties)
    return tool.replacing(inputSchema: .object(schema))
  }

  /// True unless the call asked for the text report.
  static func wantsAgentJSON(_ args: [String: Value]?) -> Bool {
    args?["for"]?.stringValue?.lowercased() != "human"
  }

  static func agentResult(_ execution: BuildExecution, action: String) -> AgentBuildResult {
    var errors: [String] = []
    if let issues = execution.issues, issues.contains(where: { $0.severity == .error }) {
      errors = issues.filter { $0.severity == .error }.map(fullIssueText)
    } else if let structured = execution.structuredErrors, !structured.isEmpty {
      errors = structured
    } else {
      errors = execution.errors
    }
    let shown = Array(errors.prefix(SwiftPMOutput.listLimit * 2))
    let warnings = execution.warningCount ?? execution.issues?.filter { $0.severity == .warning }.count
    var summary = "\(action) \(execution.succeeded ? "succeeded" : "failed") in \(execution.elapsed)s"
    if !execution.succeeded, !errors.isEmpty {
      summary += ": \(errors.count) error\(errors.count == 1 ? "" : "s")"
      if errors.count > shown.count { summary += " (first \(shown.count) listed)" }
    }
    return AgentBuildResult(
      ok: execution.succeeded, summary: summary, errors: shown.isEmpty ? nil : shown,
      warnings: warnings.flatMap { $0 > 0 ? $0 : nil }, failureReason: execution.failureReason,
      xcresult: execution.xcresultPath, bundleId: execution.bundleId, appPath: execution.appPath,
      diagnostic: execution.hangDiagnosticPath)
  }

  /// `/full/path/File.swift:12:5: message`, so the agent can open the file without searching.
  static func fullIssueText(_ issue: TestTools.BuildIssueObservation) -> String {
    guard let location = issue.location else { return issue.message }
    var place = location.filePath
    if let line = location.line {
      place += ":\(line)"
      if let column = location.column { place += ":\(column)" }
    }
    return "\(place): \(issue.message)"
  }

  static func agentJSON(_ execution: BuildExecution, action: String) -> CallTool.Result {
    let result = agentResult(execution, action: action)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let json = (try? encoder.encode(result)).flatMap { String(data: $0, encoding: .utf8) } ?? result.summary
    return result.ok ? .ok(json) : .fail(json)
  }
}

import Foundation

public enum WorkflowJSONRenderer {
  public static func renderJSON<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(value)
    // Safe to force-unwrap: JSONEncoder always produces valid UTF-8.
    return String(data: data, encoding: .utf8)!
  }

  /// Test-result renderer that projects to the slim agent shape when
  /// `forAgent` is true. Falls back to the standard encoder otherwise.
  public static func renderTestJSON(
    _ value: TestTools.TestExecution, forAgent: Bool
  ) throws -> String {
    if forAgent {
      return try renderJSON(AgentResultProjection.project(value))
    }
    return try renderJSON(value)
  }

  public static func renderTestJSON(
    _ value: TestTools.BuildAndTestResult, forAgent: Bool
  ) throws -> String {
    if forAgent {
      return try renderJSON(AgentResultProjection.project(value))
    }
    return try renderJSON(value)
  }
}

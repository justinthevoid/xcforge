import Foundation

/// Output audience for test-shaped commands. `agent` implies JSON and routes
/// through `AgentResultProjection` to keep the wire shape under the 10-field
/// budget defined in spec-agent-trust-test-signal. Lives in XCForgeKit so the
/// MCP dispatch path can thread it without depending on ArgumentParser.
public enum OutputAudience: String, Sendable, CaseIterable {
  case human
  case agent
}

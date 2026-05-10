import Foundation
import MCP

// MARK: - Debug Logging (stderr, safe for MCP stdio transport)

enum Log {
  static func warn(_ message: String) {
    fputs("[xcforge] \(message)\n", stderr)
  }

  /// Verbose / informational. Suppressed unless XCFORGE_DEBUG is set, so routine
  /// stderr stays quiet for MCP clients while still being available when needed.
  static func debug(_ message: String) {
    if ProcessInfo.processInfo.environment["XCFORGE_DEBUG"] != nil {
      fputs("[xcforge debug] \(message)\n", stderr)
    }
  }
}

// MARK: - Convenience for CallTool.Result

extension CallTool.Result {
  /// Quick success result with text content
  static func ok(_ text: String) -> Self {
    .init(content: [.text(text: text, annotations: nil, _meta: nil)])
  }

  /// Quick error result with text content
  static func fail(_ text: String) -> Self {
    .init(content: [.text(text: text, annotations: nil, _meta: nil)], isError: true)
  }
}

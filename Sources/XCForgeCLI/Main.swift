import ArgumentParser
import Logging
import MCP
import XCForgeKit

@main
struct Main {
  static func main() async throws {
    if CommandLine.arguments.count > 1 {
      await XCForgeCLI.main()
    } else {
      let logger = Logger(label: "com.xcforge.mcp")

      let server = Server(
        name: "xcforge",
        version: "1.3.0",
        capabilities: .init(tools: .init(listChanged: true))
      )

      await server.withMethodHandler(ListTools.self) { _ in
        .init(tools: ToolRegistry.allTools)
      }

      await server.withMethodHandler(CallTool.self) { params in
        await ToolRegistry.dispatch(params.name, params.arguments)
      }

      let transport = StdioTransport(logger: logger)
      try await server.start(transport: transport)
      await server.waitUntilCompleted()
    }
  }
}

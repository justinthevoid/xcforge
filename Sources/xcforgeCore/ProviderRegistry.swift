import MCP

/// Central registry of all tools. Each module self-registers via ToolProvider conformance.
public enum ToolRegistry {
    static let providers: [any ToolProvider.Type] = [
        SessionState.self,
        BuildTools.self,
        SimTools.self,
        ScreenshotTools.self,
        UITools.self,
        LogTools.self,
        GitTools.self,
        ConsoleTools.self,
        TestTools.self,
        VisualTools.self,
        MultiDeviceTools.self,
        AccessibilityTools.self,
        DiagnoseTools.self,
        PlanTools.self,
        SwiftPackageTools.self,
        DeviceTools.self,
    ]

    public static var allTools: [Tool] {
        let tools = providers.flatMap { $0.tools }
        assert(Set(tools.map(\.name)).count == tools.count, "Duplicate tool name detected in ToolProvider registrations")
        return tools
    }

    public static func dispatch(_ name: String, _ args: [String: Value]?, env: Environment = .live) async -> CallTool.Result {
        for provider in providers {
            if let result = await provider.dispatch(name, args, env: env) {
                return result
            }
        }
        Log.warn("Unknown tool: \(name)")
        return .fail("Unknown tool: \(name)")
    }
}

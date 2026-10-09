import Foundation
import MCP
import Testing

@testable import XCForgeKit

@Suite("Tool surface: groups, casing, merged tools, results, records", .serialized)
struct ToolSurfaceTests {
  private func text(_ result: CallTool.Result?) -> String {
    guard let result else { return "" }
    return result.content.compactMap {
      if case .text(let text, _, _) = $0 { return text }
      return nil
    }.joined(separator: "\n")
  }

  private func properties(_ tool: Tool?) -> [String: Value] {
    if case .object(let schema)? = tool?.inputSchema, case .object(let props)? = schema["properties"] {
      return props
    }
    return [:]
  }

  private func tempDir() -> String {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("xcforge-surface-\(UUID().uuidString)", isDirectory: true).path
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    return dir
  }

  // MARK: - Tool groups

  @Test("the diagnose group starts off, and a spec adds, removes or picks groups")
  func groupSpecs() {
    let groups = ["build", "diagnose", "git", "session-state", "test", "ui"]
    #expect(ToolSurface.disabledGroups(spec: nil, allGroups: groups).disabled == ["diagnose"])
    #expect(ToolSurface.disabledGroups(spec: "+diagnose", allGroups: groups).disabled.isEmpty)
    #expect(ToolSurface.disabledGroups(spec: "-git", allGroups: groups).disabled == ["diagnose", "git"])
    #expect(ToolSurface.disabledGroups(spec: "all", allGroups: groups).disabled.isEmpty)
    let only = ToolSurface.disabledGroups(spec: "[build, test]", allGroups: groups)
    #expect(only.disabled == ["diagnose", "git", "ui"])
    #expect(ToolSurface.disabledGroups(spec: "-session-state", allGroups: groups).disabled == ["diagnose"])
    let unknown = ToolSurface.disabledGroups(spec: "+gti", allGroups: groups)
    #expect(unknown.warnings.count == 1)
    #expect(unknown.warnings.first?.contains("gti") == true)
  }

  @Test("toolGroups is read from .xcforge.yaml and the environment wins over it")
  func startupSpec() {
    let dir = tempDir()
    defer { try? FileManager.default.removeItem(atPath: dir) }
    try? "toolGroups: +diagnose\n".write(toFile: dir + "/.xcforge.yaml", atomically: true, encoding: .utf8)
    #expect(ToolSurface.startupSpec(environment: [:], cwd: dir) == "+diagnose")
    #expect(ToolSurface.startupSpec(environment: ["XCFORGE_TOOL_GROUPS": "-git"], cwd: dir) == "-git")
  }

  @Test("a tool in a disabled group says how to turn the group on")
  func disabledGroupCall() async {
    guard ToolRegistry.disabledGroups.contains("diagnose") else { return }
    let result = await ToolRegistry.dispatch("diagnose_status", nil)
    #expect(result.isError == true)
    #expect(text(result).contains("tool_groups"))
    #expect(text(result).contains("XCFORGE_TOOL_GROUPS=+diagnose"))
  }

  // MARK: - Listing

  @Test("the listed tools: merged tools in, deprecated names and the diagnose group out")
  func listing() {
    let names = Set(ToolRegistry.allTools.map(\.name))
    #expect(names.contains("tap"))
    #expect(names.contains("tool_groups"))
    for alias in ToolSurface.deprecatedAliases.keys {
      #expect(!names.contains(alias), "\(alias) should not be listed")
      #expect(ToolRegistry.declaredTool(alias) != nil, "\(alias) must still dispatch")
    }
    if ToolRegistry.disabledGroups.contains("diagnose") {
      #expect(!names.contains("diagnose_start"))
    }
    #expect(ToolRegistry.declaredTool("diagnose_start") != nil)
  }

  @Test("every listed argument is camelCase")
  func camelCaseArguments() {
    var snake: [String] = []
    for tool in ToolRegistry.allTools {
      for name in tool.argumentNames where name.contains("_") { snake.append("\(tool.name).\(name)") }
    }
    #expect(snake.isEmpty, "snake_case arguments: \(snake.joined(separator: ", "))")
    let testSim = ToolRegistry.allTools.first { $0.name == "test_sim" }
    #expect(properties(testSim)["includeConsole"] != nil)
    #expect(properties(testSim)["rerunFailed"] != nil)
  }

  @Test("either casing reaches the name the implementation reads")
  func normalizeArguments() {
    #expect(ToolSurface.camelCase("include_console") == "includeConsole")
    #expect(ToolSurface.camelCase("derivedDataPath") == "derivedDataPath")
    let declared = ["element_id", "derivedDataPath", "x"]
    let normalized = ToolSurface.normalize(
      ["elementId": .string("e1"), "derived_data_path": .string("/dd"), "x": .int(3), "bogus": .bool(true)],
      declared: declared)
    #expect(normalized?["element_id"] == .string("e1"))
    #expect(normalized?["derivedDataPath"] == .string("/dd"))
    #expect(normalized?["x"] == .int(3))
    #expect(normalized?["bogus"] == .bool(true))

    let tool = Tool(
      name: "t", description: nil,
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object(["include_console": .object([:]), "path": .object([:])]),
        "required": .array([.string("include_console")]),
      ]))
    let listed = ToolSurface.canonicalize(tool)
    #expect(Set(listed.argumentNames) == ["includeConsole", "path"])
    if case .object(let schema) = listed.inputSchema {
      #expect(schema["required"] == .array([.string("includeConsole")]))
    }
  }

  @Test("read-only tools are marked; tools that change things are not")
  func readOnlyHints() {
    let tools = ToolRegistry.allTools
    #expect(tools.first { $0.name == "git_status" }?.annotations.readOnlyHint == true)
    #expect(tools.first { $0.name == "get_source" }?.annotations.readOnlyHint == true)
    #expect(tools.first { $0.name == "build_sim" }?.annotations.readOnlyHint == nil)
    #expect(tools.first { $0.name == "tap" }?.annotations.readOnlyHint == nil)
  }

  // MARK: - tap

  @Test("tap needs exactly one target and point options need a point")
  func tapTargets() async {
    let none = await UITools.tap([:], env: .live)
    #expect(text(none).contains("exactly one target"))
    let two = await UITools.tap(["id": .string("a"), "elementId": .string("b")], env: .live)
    #expect(text(two).contains("exactly one target"))
    let countWithoutPoint = await UITools.tap(["id": .string("a"), "count": .int(2)], env: .live)
    #expect(text(countWithoutPoint).contains("need x and y"))
    let halfQuery = await UITools.tap(["value": .string("Save")], env: .live)
    #expect(text(halfQuery).contains("using and value go together"))
    let twoModes = await UITools.tap(
      ["x": .int(1), "y": .int(2), "count": .int(2), "hid": .bool(true)], env: .live)
    #expect(text(twoModes).contains("one of count: 2"))
    #expect(ToolSurface.deprecationNote(for: "tap_by_id")?.contains("tap with id") == true)
    #expect(ToolSurface.deprecationNote(for: "tap") == nil)
  }

  // MARK: - Build results

  @Test("build tools default to slim JSON with full error paths")
  func buildAgentJSON() throws {
    let issue = TestTools.BuildIssueObservation(
      severity: .error, message: "cannot find 'x' in scope",
      location: SourceLocation(filePath: "/src/App/View.swift", line: 12, column: 5), source: "xcresult")
    let execution = BuildTools.BuildExecution(
      succeeded: false, elapsed: "4.2", scheme: "App", simulator: "iPhone 17", configuration: "Debug",
      bundleId: nil, appPath: nil, errors: [], failureReason: nil, structuredErrors: nil,
      xcresultPath: "/tmp/r.xcresult", issues: [issue], errorCount: 1, warningCount: 0)
    let result = BuildTools.agentResult(execution, action: "Compile")
    #expect(result.ok == false)
    #expect(result.summary == "Compile failed in 4.2s: 1 error")
    #expect(result.errors == ["/src/App/View.swift:12:5: cannot find 'x' in scope"])
    #expect(result.warnings == nil)
    #expect(result.xcresult == "/tmp/r.xcresult")

    let call = BuildTools.agentJSON(execution, action: "Compile")
    #expect(call.isError == true)
    let json = try #require(text(call).data(using: .utf8))
    let decoded = try JSONDecoder().decode(BuildTools.AgentBuildResult.self, from: json)
    #expect(decoded == result)
    #expect(!text(call).contains("\n"))

    #expect(BuildTools.wantsAgentJSON(nil))
    #expect(!BuildTools.wantsAgentJSON(["for": .string("human")]))
    let compile = ToolRegistry.allTools.first { $0.name == "build_compile" }
    #expect(properties(compile)["for"] != nil)
  }

  // MARK: - rerunFailed

  @Test("rerunFailed can't be combined with a filter")
  func rerunFailedWithFilter() async {
    var input = TestTools.TestSimInput()
    input.filter = "AppTests/LoginTests"
    input.rerunFailed = true
    switch await TestTools.applyRerunFailed(&input, env: .live) {
    case .refusal(let result): #expect(text(result).contains("drop filter or rerunFailed"))
    case .ids: Issue.record("expected a refusal")
    }
  }

  // MARK: - plan decide across processes

  @Test("a suspended plan saved by plan run is resumed once, without the wait counting")
  func planSessionFile() throws {
    let dir = tempDir()
    defer { try? FileManager.default.removeItem(atPath: dir) }
    let steps: [Value] = [.object(["navigateBack": .bool(true)]), .object(["navigateBack": .bool(true)])]
    let plan = SuspendedPlan(
      steps: try PlanParser.parse(steps), pauseIndex: 0, question: "Proceed?", completedResults: [],
      variableBindings: ["$btn": .init(elementId: "e1", label: "Save")], errorStrategy: .abort,
      timeoutSeconds: 120, startTime: 1000, screenshotBase64: nil)
    let id = try PlanSessionFile.save(plan, steps: steps, directory: dir)

    let resumed = try PlanSessionFile.consume(id, directory: dir, now: Date().addingTimeInterval(30))
    #expect(resumed.plan.steps.count == 2)
    #expect(resumed.plan.question == "Proceed?")
    #expect(resumed.plan.variableBindings["$btn"]?.elementId == "e1")
    #expect(resumed.plan.errorStrategy == .abort)
    #expect(resumed.plan.startTime >= 1029)
    #expect(resumed.steps.count == 2)

    #expect(throws: PlanSessionFile.LoadError.self) { try PlanSessionFile.consume(id, directory: dir) }
    #expect(throws: PlanSessionFile.LoadError.self) { try PlanSessionFile.consume("../etc", directory: dir) }

    let old = try PlanSessionFile.save(plan, steps: steps, directory: dir)
    #expect(throws: PlanSessionFile.LoadError.self) {
      try PlanSessionFile.consume(old, directory: dir, now: Date().addingTimeInterval(7200))
    }
  }

  // MARK: - Per-project records

  @Test("last results are keyed on the absolute project path")
  func canonicalRecords() {
    let cwd = "/work/repo-a"
    #expect(LastResultStore.canonicalProject("App.xcodeproj", cwd: cwd) == "/work/repo-a/App.xcodeproj")
    #expect(LastResultStore.canonicalProject("/work/repo-a/./x/../App.xcodeproj") == "/work/repo-a/App.xcodeproj")
    #expect(
      LastResultStore.canonicalProject("App.xcodeproj", cwd: "/work/repo-b")
        != LastResultStore.canonicalProject("App.xcodeproj", cwd: cwd))
    let long = "/" + String(repeating: "deep/", count: 80) + "App.xcodeproj"
    #expect(LastResultStore.fileName(for: long).utf8.count < 255)
    #expect(LastResultStore.fileName(for: long) == LastResultStore.fileName(for: long))
  }

  // MARK: - Docs

  @Test("SKILL.md states the listed tool count and the references name every listed tool")
  func docsMatchTools() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().path
    let skill = try String(contentsOfFile: root + "/Skills/xcforge/SKILL.md", encoding: .utf8)
    let listed = ToolRegistry.allTools
    if ToolRegistry.disabledGroups == ToolSurface.defaultOffGroups {
      #expect(skill.contains("\(listed.count) MCP tools"), "SKILL.md should say \(listed.count) MCP tools")
    }
    let referencesDir = root + "/Skills/xcforge/references"
    var docs = skill
    let files = (try? FileManager.default.contentsOfDirectory(atPath: referencesDir)) ?? []
    for file in files where file.hasSuffix(".md") {
      docs += (try? String(contentsOfFile: referencesDir + "/" + file, encoding: .utf8)) ?? ""
    }
    let undocumented = listed.map(\.name).filter { !docs.contains("`\($0)`") && !docs.contains("## \($0)") }
    #expect(undocumented.isEmpty, "Undocumented tools: \(undocumented.joined(separator: ", "))")
  }
}

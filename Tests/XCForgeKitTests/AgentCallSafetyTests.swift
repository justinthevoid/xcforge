import Foundation
import MCP
import Testing

@testable import XCForgeKit

@Suite("Agent call safety: cancellation, queueing, config scoping, argument checks", .serialized)
struct AgentCallSafetyTests {

  private func makeRepo(yaml: String?) -> String {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("xcforge-callsafety-\(UUID().uuidString)", isDirectory: true)
    try! FileManager.default.createDirectory(
      at: dir.appendingPathComponent(".git"), withIntermediateDirectories: true)
    if let yaml {
      try! yaml.write(
        to: dir.appendingPathComponent(".xcforge.yaml"), atomically: true, encoding: .utf8)
    }
    return dir.path
  }

  private func isAlive(_ pid: pid_t) -> Bool { kill(pid, 0) == 0 }

  private func waitUntil(seconds: Double, _ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
      if condition() { return true }
      try? await Task.sleep(nanoseconds: 50_000_000)
    }
    return condition()
  }

  // MARK: - Cancellation stops the process tree

  @Test("cancelling a shell call kills the child and its children", .timeLimit(.minutes(1)))
  func cancelKillsTree() async throws {
    let before = Set(ChildProcesses.running)
    // `; true` keeps sh from exec'ing sleep, so sleep is a grandchild of xcforge.
    let task = Task {
      try await Shell.run("/bin/sh", arguments: ["-c", "/bin/sleep 30; true"], timeout: 60)
    }

    var shell: pid_t = 0
    let started = await waitUntil(seconds: 10) {
      guard let pid = Set(ChildProcesses.running).subtracting(before).first else { return false }
      shell = pid
      return !ProcessTree.children(of: pid).isEmpty
    }
    #expect(started, "sh and its sleep child should be running")
    let sleeper = ProcessTree.children(of: shell)

    task.cancel()
    let result = try await task.value
    #expect(result.exitCode == -2)

    let gone = await waitUntil(seconds: 5) { !isAlive(shell) && sleeper.allSatisfy { !isAlive($0) } }
    #expect(gone, "cancel must not leave sh or sleep running")
    #expect(!ChildProcesses.running.contains(shell))
  }

  @Test("a timeout kills grandchildren too", .timeLimit(.minutes(1)))
  func timeoutKillsTree() async throws {
    let marker = FileManager.default.temporaryDirectory
      .appendingPathComponent("xcforge-tree-\(UUID().uuidString)").path
    // The grandchild records its pid so we can check it after the parent is gone.
    let script = "/bin/sh -c 'echo $$ > \(marker); exec /bin/sleep 30' ; true"
    let result = try await Shell.run("/bin/sh", arguments: ["-c", script], timeout: 1)
    #expect(result.exitCode == -1)
    let pid = (try? String(contentsOfFile: marker, encoding: .utf8))
      .flatMap { pid_t($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    #expect(pid != nil)
    if let pid {
      let gone = await waitUntil(seconds: 5) { !isAlive(pid) }
      #expect(gone, "the sleeping grandchild must be killed with its parent")
    }
    try? FileManager.default.removeItem(atPath: marker)
  }

  @Test("tool activity keeps the last non-empty output line")
  func activityLastLine() async throws {
    #expect(ToolActivity.lastLine(in: "CompileSwift a.swift\nLd App\n\n") == "Ld App")
    #expect(ToolActivity.lastLine(in: "\n  \n") == nil)
    let long = String(repeating: "x", count: 300)
    #expect(ToolActivity.lastLine(in: long)?.count == 201)

    let activity = ToolActivity()
    _ = try await ToolActivity.$current.withValue(activity) {
      try await Shell.run("/bin/sh", arguments: ["-c", "echo first; echo second"], timeout: 10)
    }
    #expect(activity.lastLine == "second")
  }

  // MARK: - In-process xcodebuild queue

  @Test("a second xcodebuild on the same DerivedData waits for the first", .timeLimit(.minutes(1)))
  func queueSerializesSameKey() async {
    let queue = XcodebuildQueue()
    let first = await queue.enter(key: "dd:/a")
    let second = Task { await queue.enter(key: "dd:/a") }
    let other = await queue.enter(key: "dd:/b")  // a different folder never waits
    #expect(other.key == "dd:/b")

    let queued = await waitUntilAsync { await queue.waiting(for: "dd:/a") == 1 }
    #expect(queued)
    await queue.leave(first)
    let ticket = await second.value
    #expect(ticket.key == "dd:/a")
    await queue.leave(ticket)
    await queue.leave(other)
    #expect(await queue.waiting(for: "dd:/a") == 0)
  }

  private func waitUntilAsync(_ condition: () async -> Bool) async -> Bool {
    for _ in 0..<100 {
      if await condition() { return true }
      try? await Task.sleep(nanoseconds: 20_000_000)
    }
    return await condition()
  }

  @Test("queue key prefers DerivedData, then the absolute project path")
  func queueKeys() {
    #expect(Xcodebuild.queueKey(["-derivedDataPath", "/dd/../dd2", "build"], workingDirectory: nil) == "dd:/dd2")
    #expect(
      Xcodebuild.queueKey(["-project", "App.xcodeproj", "build"], workingDirectory: "/repo")
        == "project:/repo/App.xcodeproj")
    #expect(Xcodebuild.projectDirectory(["-workspace", "/w/App.xcworkspace"], workingDirectory: nil) == "/w")
    #expect(Xcodebuild.projectDirectory(["build"], workingDirectory: nil) == nil)
  }

  // MARK: - .xcforge.yaml parsing and scoping

  @Test("yaml values lose quotes and trailing comments")
  func yamlCleanValue() {
    #expect(RepoConfig.cleanValue(" \"My App\" ") == "My App")
    #expect(RepoConfig.cleanValue("'My App' # dev") == "My App")
    #expect(RepoConfig.cleanValue("iPhone 16 # dev sim") == "iPhone 16")
    #expect(RepoConfig.cleanValue("a#b") == "a#b")
    #expect(RepoConfig.cleanValue("Plain") == "Plain")
  }

  @Test("yaml problems are collected as warnings with suggestions")
  func yamlWarnings() {
    let root = makeRepo(yaml: "scheme: \"App\"  # main\ntestplan: quick\nminFreeGB: lots\n")
    defer { try? FileManager.default.removeItem(atPath: root) }
    let values = RepoConfig.discover(from: root)
    #expect(values?.scheme == "App")
    #expect(values?.minFreeGB == nil)
    let warnings = values?.warnings ?? []
    #expect(warnings.contains { $0.contains("'testplan'") && $0.contains("did you mean 'testPlan'") })
    #expect(warnings.contains { $0.contains("minFreeGB") })
    #expect(values?.sourcePath?.hasSuffix(".xcforge.yaml") == true)
  }

  @Test("a yaml with only bad keys still reports them")
  func yamlOnlyBadKeys() {
    let root = makeRepo(yaml: "shceme: App\n")
    defer { try? FileManager.default.removeItem(atPath: root) }
    let values = RepoConfig.discover(from: root)
    #expect(values?.scheme == nil)
    #expect(values?.warnings.first?.contains("did you mean 'scheme'") == true)
  }

  @Test("an explicit project in another repo uses that repo's .xcforge.yaml")
  func explicitProjectUsesItsOwnConfig() async throws {
    let repoA = makeRepo(yaml: "scheme: SchemeA\ntestPlan: planA\n")
    let repoB = makeRepo(yaml: "scheme: SchemeB\ntestPlan: planB\n")
    defer {
      try? FileManager.default.removeItem(atPath: repoA)
      try? FileManager.default.removeItem(atPath: repoB)
    }
    let store = DefaultsStore(
      baseDirectory: URL(fileURLWithPath: repoA).appendingPathComponent("store", isDirectory: true))
    let session = SessionState(defaultsStore: store, cwd: repoA)
    #expect(await session.resolveTestPlan(nil) == "planA")

    let projectB = (repoB as NSString).appendingPathComponent("B.xcodeproj")
    _ = try await session.resolveProject(projectB)
    #expect(try await session.resolveScheme(nil, project: projectB) == "SchemeB")
    #expect(await session.resolveTestPlan(nil) == "planB")
    #expect(await session.activeProject == projectB)
    #expect(await session.showDefaults().contains("config: "))
  }

  // MARK: - Unknown MCP arguments

  @Test("unknown arguments are rejected with the closest real name")
  func unknownArguments() {
    let snake = ToolRegistry.unknownArgumentsError("build_sim", ["derived_data_path": .string("/dd")])
    #expect(snake?.isError == true)
    #expect(text(snake).contains("did you mean 'derivedDataPath'"))

    let typo = ToolRegistry.unknownArgumentsError("build_sim", ["shceme": .string("A")])
    #expect(text(typo).contains("did you mean 'scheme'"))

    #expect(ToolRegistry.unknownArgumentsError("build_sim", ["scheme": .string("A")]) == nil)
    #expect(ToolRegistry.unknownArgumentsError("build_sim", nil) == nil)
    #expect(ToolRegistry.unknownArgumentsError("list_elements", ["source": .string("wda")]) == nil)
  }

  private func text(_ result: CallTool.Result?) -> String {
    guard let result else { return "" }
    return result.content.compactMap {
      if case .text(let text, _, _) = $0 { return text }
      return nil
    }.joined(separator: "\n")
  }
}

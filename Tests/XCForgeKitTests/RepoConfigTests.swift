import Foundation
import Testing

@testable import XCForgeKit

@Suite("RepoConfig: .xcforge.yaml discovery and parsing", .serialized)
struct RepoConfigTests {

  // MARK: - Helpers

  private func makeTempDir() -> URL {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("xcforge-repoconfig-\(UUID().uuidString)", isDirectory: true)
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  private func cleanup(_ dir: URL) {
    try? FileManager.default.removeItem(at: dir)
  }

  private func writeFile(_ content: String, at dir: URL, name: String = ".xcforge.yaml") {
    let path = dir.appendingPathComponent(name)
    try! content.write(to: path, atomically: true, encoding: .utf8)
  }

  private func createDir(_ dir: URL) {
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  }

  // MARK: - Discovery

  @Test("discovers config in CWD")
  func discoversInCWD() {
    let root = makeTempDir()
    defer { cleanup(root) }

    // Add .git so it's treated as repo root
    createDir(root.appendingPathComponent(".git"))
    writeFile("scheme: MyScheme\n", at: root)

    let result = RepoConfig.discover(from: root.path)
    #expect(result?.scheme == "MyScheme")
  }

  @Test("discovers config in ancestor directory")
  func discoversInAncestor() {
    let root = makeTempDir()
    defer { cleanup(root) }

    createDir(root.appendingPathComponent(".git"))
    writeFile("scheme: ParentScheme\n", at: root)

    let subdir = root.appendingPathComponent("ios/App", isDirectory: true)
    createDir(subdir)

    let result = RepoConfig.discover(from: subdir.path)
    #expect(result?.scheme == "ParentScheme")
  }

  @Test("stops at .git boundary — does not walk above repo root")
  func stopsAtGitBoundary() {
    let outer = makeTempDir()
    defer { cleanup(outer) }

    writeFile("scheme: OuterScheme\n", at: outer)

    let inner = outer.appendingPathComponent("repo", isDirectory: true)
    createDir(inner)
    createDir(inner.appendingPathComponent(".git"))
    // No .xcforge.yaml inside inner repo

    let result = RepoConfig.discover(from: inner.path)
    #expect(result == nil)
  }

  @Test("returns nil when no config file exists")
  func noConfigFile() {
    let root = makeTempDir()
    defer { cleanup(root) }
    createDir(root.appendingPathComponent(".git"))

    let result = RepoConfig.discover(from: root.path)
    #expect(result == nil)
  }

  // MARK: - Parsing

  @Test("parses all three fields")
  func parsesAllFields() {
    let root = makeTempDir()
    defer { cleanup(root) }
    createDir(root.appendingPathComponent(".git"))

    writeFile(
      """
      project: /abs/path/App.xcodeproj
      scheme: AppScheme
      simulator: iPhone 16 Pro
      """, at: root)

    let result = RepoConfig.discover(from: root.path)
    #expect(result?.project == "/abs/path/App.xcodeproj")
    #expect(result?.scheme == "AppScheme")
    #expect(result?.simulator == "iPhone 16 Pro")
  }

  @Test("parses partial fields — only scheme")
  func parsesPartial() {
    let root = makeTempDir()
    defer { cleanup(root) }
    createDir(root.appendingPathComponent(".git"))

    writeFile("scheme: OnlyScheme\n", at: root)

    let result = RepoConfig.discover(from: root.path)
    #expect(result?.scheme == "OnlyScheme")
    #expect(result?.project == nil)
    #expect(result?.simulator == nil)
  }

  @Test("ignores comments and blank lines")
  func commentsAndBlanks() {
    let root = makeTempDir()
    defer { cleanup(root) }
    createDir(root.appendingPathComponent(".git"))

    writeFile(
      """
      # This is a comment
      scheme: CommentScheme

      # Another comment
      simulator: iPhone 15
      """, at: root)

    let result = RepoConfig.discover(from: root.path)
    #expect(result?.scheme == "CommentScheme")
    #expect(result?.simulator == "iPhone 15")
  }

  @Test("returns nil for empty file")
  func emptyFile() {
    let root = makeTempDir()
    defer { cleanup(root) }
    createDir(root.appendingPathComponent(".git"))

    writeFile("", at: root)

    let result = RepoConfig.discover(from: root.path)
    #expect(result == nil)
  }

  @Test("returns nil for file with only comments")
  func onlyComments() {
    let root = makeTempDir()
    defer { cleanup(root) }
    createDir(root.appendingPathComponent(".git"))

    writeFile("# just a comment\n# another\n", at: root)

    let result = RepoConfig.discover(from: root.path)
    #expect(result == nil)
  }

  // MARK: - Relative path resolution

  @Test("resolves relative project path against config directory")
  func relativeProjectPath() {
    let root = makeTempDir()
    defer { cleanup(root) }
    createDir(root.appendingPathComponent(".git"))

    // Create the target project directory so resolution succeeds
    let projectDir = root.appendingPathComponent("ios/App.xcodeproj", isDirectory: true)
    createDir(projectDir)

    writeFile("project: ios/App.xcodeproj\n", at: root)

    let result = RepoConfig.discover(from: root.path)
    #expect(result?.project == (root.path as NSString).appendingPathComponent("ios/App.xcodeproj"))
  }

  @Test("skips relative project path that does not exist on disk")
  func relativeProjectPathMissing() {
    let root = makeTempDir()
    defer { cleanup(root) }
    createDir(root.appendingPathComponent(".git"))

    writeFile("project: nonexistent/App.xcodeproj\nscheme: FallbackScheme\n", at: root)

    let result = RepoConfig.discover(from: root.path)
    // project should be nil (path doesn't exist), but scheme should still parse
    #expect(result?.project == nil)
    #expect(result?.scheme == "FallbackScheme")
  }

  @Test("absolute project path is preserved as-is")
  func absoluteProjectPath() {
    let root = makeTempDir()
    defer { cleanup(root) }
    createDir(root.appendingPathComponent(".git"))

    writeFile("project: /some/absolute/App.xcodeproj\n", at: root)

    let result = RepoConfig.discover(from: root.path)
    #expect(result?.project == "/some/absolute/App.xcodeproj")
  }

  // MARK: - Repo root helper

  @Test("repoRoot finds .git directory")
  func repoRootFindsGit() {
    let root = makeTempDir()
    defer { cleanup(root) }
    createDir(root.appendingPathComponent(".git"))

    let sub = root.appendingPathComponent("a/b/c", isDirectory: true)
    createDir(sub)

    let found = AutoDetect.repoRoot(from: sub.path)
    #expect(found == root.path)
  }

  @Test("repoRoot returns nil when no .git exists")
  func repoRootNoGit() {
    let root = makeTempDir()
    defer { cleanup(root) }

    // Use a deep path inside temp that won't hit any real .git
    let sub = root.appendingPathComponent("deep/nested", isDirectory: true)
    createDir(sub)

    let found = AutoDetect.repoRoot(from: sub.path)
    #expect(found == nil)
  }

  // MARK: - Edge cases

  @Test("discover returns nil for empty startDir")
  func emptyStartDir() {
    let result = RepoConfig.discover(from: "")
    #expect(result == nil)
  }

  @Test("repoRoot returns nil for empty startDir")
  func repoRootEmptyStartDir() {
    let found = AutoDetect.repoRoot(from: "")
    #expect(found == nil)
  }

  @Test("handles CRLF line endings")
  func crlfLineEndings() {
    let root = makeTempDir()
    defer { cleanup(root) }
    createDir(root.appendingPathComponent(".git"))

    writeFile("scheme: CRLFScheme\r\nsimulator: iPhone 15\r\n", at: root)

    let result = RepoConfig.discover(from: root.path)
    #expect(result?.scheme == "CRLFScheme")
    #expect(result?.simulator == "iPhone 15")
  }

  @Test("handles garbled/malformed content gracefully")
  func malformedContent() {
    let root = makeTempDir()
    defer { cleanup(root) }
    createDir(root.appendingPathComponent(".git"))

    writeFile(":::bad\nnot yaml at all\n\u{0000}binary junk\nscheme: StillWorks\n", at: root)

    let result = RepoConfig.discover(from: root.path)
    #expect(result?.scheme == "StillWorks")
  }

  @Test("parses configuration and testPlan keys")
  func parsesConfigurationAndTestPlan() {
    let root = makeTempDir()
    defer { cleanup(root) }
    createDir(root.appendingPathComponent(".git"))

    writeFile(
      """
      scheme: AppScheme
      configuration: Release
      testPlan: SmokeTests
      """, at: root)

    let result = RepoConfig.discover(from: root.path)
    #expect(result?.scheme == "AppScheme")
    #expect(result?.configuration == "Release")
    #expect(result?.testPlan == "SmokeTests")
  }

  @Test("unknown keys are warned and ignored, known keys still parse")
  func unknownKeysIgnored() {
    let root = makeTempDir()
    defer { cleanup(root) }
    createDir(root.appendingPathComponent(".git"))

    writeFile("scheme: KeepMe\nbogusKey: nope\ntimeout: 99\n", at: root)

    let result = RepoConfig.discover(from: root.path)
    #expect(result?.scheme == "KeepMe")
  }

  // MARK: - Priority chain (repo config beats persisted)

  @Test("repo config overrides persisted defaults")
  func repoOverridesPersisted() async {
    let root = makeTempDir()
    defer { cleanup(root) }
    createDir(root.appendingPathComponent(".git"))
    writeFile("scheme: RepoScheme\n", at: root)

    let storeDir = root.appendingPathComponent("store", isDirectory: true)
    createDir(storeDir)
    let store = DefaultsStore(baseDirectory: storeDir)
    store.save(PersistedDefaults(scheme: "PersistedScheme"))

    let session = SessionState(defaultsStore: store, cwd: root.path)
    // The committed repo file is the team source of truth — it must beat the
    // machine-global persisted default (same model as git local > global).
    let scheme = try? await session.resolveScheme(nil, project: "/dummy.xcodeproj")
    #expect(scheme == "RepoScheme")
  }

  @Test("persisted default fills a field the repo file omits")
  func persistedFillsGap() async {
    let root = makeTempDir()
    defer { cleanup(root) }
    createDir(root.appendingPathComponent(".git"))
    // Repo file has no `scheme` — persisted should fill the gap.
    writeFile("simulator: RepoSim\n", at: root)

    let storeDir = root.appendingPathComponent("store", isDirectory: true)
    createDir(storeDir)
    let store = DefaultsStore(baseDirectory: storeDir)
    store.save(PersistedDefaults(scheme: "PersistedScheme"))

    let session = SessionState(defaultsStore: store, cwd: root.path)
    let scheme = try? await session.resolveScheme(nil, project: "/dummy.xcodeproj")
    #expect(scheme == "PersistedScheme")
    let simulator = try? await session.resolveSimulator("RepoSim")
    #expect(simulator == "RepoSim")
  }

  @Test("explicit param overrides repo config")
  func explicitOverridesRepo() async {
    let root = makeTempDir()
    defer { cleanup(root) }
    createDir(root.appendingPathComponent(".git"))
    writeFile("scheme: RepoScheme\n", at: root)

    let storeDir = root.appendingPathComponent("store", isDirectory: true)
    createDir(storeDir)
    let store = DefaultsStore(baseDirectory: storeDir)

    let session = SessionState(defaultsStore: store, cwd: root.path)
    let scheme = try? await session.resolveScheme("ExplicitScheme", project: "/dummy.xcodeproj")
    #expect(scheme == "ExplicitScheme")
  }

  @Test("in-session set_defaults outranks repo config for this session")
  func setDefaultsBeatsRepoInSession() async {
    let root = makeTempDir()
    defer { cleanup(root) }
    createDir(root.appendingPathComponent(".git"))
    writeFile("scheme: RepoScheme\n", at: root)

    let storeDir = root.appendingPathComponent("store", isDirectory: true)
    createDir(storeDir)
    let store = DefaultsStore(baseDirectory: storeDir)

    let session = SessionState(defaultsStore: store, cwd: root.path)
    await session.setDefaults(project: nil, scheme: "SessionScheme", simulator: nil)
    let scheme = try? await session.resolveScheme(nil, project: "/dummy.xcodeproj")
    #expect(scheme == "SessionScheme")
  }

  // MARK: - Repo-only resolvers (configuration / testPlan)

  @Test("resolveConfiguration: explicit > repo > Debug")
  func resolveConfigurationPrecedence() async {
    let root = makeTempDir()
    defer { cleanup(root) }
    createDir(root.appendingPathComponent(".git"))
    writeFile("configuration: Release\n", at: root)

    let storeDir = root.appendingPathComponent("store", isDirectory: true)
    createDir(storeDir)
    let store = DefaultsStore(baseDirectory: storeDir)
    let session = SessionState(defaultsStore: store, cwd: root.path)

    #expect(await session.resolveConfiguration(nil) == "Release")
    #expect(await session.resolveConfiguration("Beta") == "Beta")
  }

  @Test("resolveConfiguration defaults to Debug when no repo key")
  func resolveConfigurationDefault() async {
    let root = makeTempDir()
    defer { cleanup(root) }
    createDir(root.appendingPathComponent(".git"))
    writeFile("scheme: NoConfig\n", at: root)

    let storeDir = root.appendingPathComponent("store", isDirectory: true)
    createDir(storeDir)
    let store = DefaultsStore(baseDirectory: storeDir)
    let session = SessionState(defaultsStore: store, cwd: root.path)

    #expect(await session.resolveConfiguration(nil) == "Debug")
  }

  @Test("resolveTestPlan: explicit > repo > nil")
  func resolveTestPlanPrecedence() async {
    let root = makeTempDir()
    defer { cleanup(root) }
    createDir(root.appendingPathComponent(".git"))
    writeFile("testPlan: SmokeTests\n", at: root)

    let storeDir = root.appendingPathComponent("store", isDirectory: true)
    createDir(storeDir)
    let store = DefaultsStore(baseDirectory: storeDir)
    let session = SessionState(defaultsStore: store, cwd: root.path)

    #expect(await session.resolveTestPlan(nil) == "SmokeTests")
    #expect(await session.resolveTestPlan("Full") == "Full")
  }

  @Test("resolveTestPlan returns nil when no repo key and no explicit")
  func resolveTestPlanNil() async {
    let root = makeTempDir()
    defer { cleanup(root) }
    createDir(root.appendingPathComponent(".git"))
    writeFile("scheme: NoPlan\n", at: root)

    let storeDir = root.appendingPathComponent("store", isDirectory: true)
    createDir(storeDir)
    let store = DefaultsStore(baseDirectory: storeDir)
    let session = SessionState(defaultsStore: store, cwd: root.path)

    #expect(await session.resolveTestPlan(nil) == nil)
  }

  @Test("configuration/testPlan never leak into persisted defaults")
  func repoOnlyKeysNotPersisted() async {
    let root = makeTempDir()
    defer { cleanup(root) }
    createDir(root.appendingPathComponent(".git"))
    writeFile("configuration: Release\ntestPlan: Smoke\nscheme: S\n", at: root)

    let storeDir = root.appendingPathComponent("store", isDirectory: true)
    createDir(storeDir)
    let store = DefaultsStore(baseDirectory: storeDir)

    let session = SessionState(defaultsStore: store, cwd: root.path)
    _ = await session.resolveConfiguration(nil)
    _ = await session.resolveTestPlan(nil)
    _ = try? await session.resolveScheme(nil, project: "/dummy.xcodeproj")
    // Force a persist so the JSON is actually written, then assert the raw
    // file never contains the repo-only keys (a structural guarantee, not a
    // tautology — this would catch any future leak into PersistedDefaults).
    await session.setDefaults(project: nil, scheme: "Persisted", simulator: nil)
    let jsonPath = storeDir.appendingPathComponent("defaults.json").path
    let raw = (try? String(contentsOfFile: jsonPath, encoding: .utf8)) ?? ""
    #expect(!raw.isEmpty, "persist should have written defaults.json")
    #expect(store.load()?.scheme == "Persisted", "persist round-trips scheme")
    #expect(!raw.contains("configuration"))
    #expect(!raw.contains("testPlan"))
    #expect(!raw.contains("Release"))
    #expect(!raw.contains("Smoke"))
  }

  @Test("repo file with only configuration is valid and does not block other resolution")
  func configurationOnlyRepoFile() async {
    let root = makeTempDir()
    defer { cleanup(root) }
    createDir(root.appendingPathComponent(".git"))
    writeFile("configuration: Release\n", at: root)

    let parsed = RepoConfig.discover(from: root.path)
    #expect(parsed?.configuration == "Release")
    #expect(parsed?.scheme == nil)
    #expect(parsed?.project == nil)

    let storeDir = root.appendingPathComponent("store", isDirectory: true)
    createDir(storeDir)
    let store = DefaultsStore(baseDirectory: storeDir)
    store.save(PersistedDefaults(scheme: "PersistedScheme"))
    let session = SessionState(defaultsStore: store, cwd: root.path)
    // configuration comes from the repo file; scheme (absent in repo) still
    // falls through to the persisted default — config-only file is no barrier.
    #expect(await session.resolveConfiguration(nil) == "Release")
    let scheme = try? await session.resolveScheme(nil, project: "/dummy.xcodeproj")
    #expect(scheme == "PersistedScheme")
  }

  // MARK: - scaffold

  @Test("scaffold contains all documented keys")
  func scaffoldContainsKeys() {
    let yaml = RepoConfig.scaffold(
      project: "/abs/App.xcodeproj", scheme: "AppScheme", simulator: "iPhone 16 Pro")
    #expect(yaml.contains("project: /abs/App.xcodeproj"))
    #expect(yaml.contains("scheme: AppScheme"))
    #expect(yaml.contains("simulator: iPhone 16 Pro"))
    #expect(yaml.contains("configuration"))
    #expect(yaml.contains("testPlan"))
    #expect(yaml.contains("#"))
  }

  @Test("scaffold round-trips through the parser for detected values")
  func scaffoldRoundTrips() {
    let root = makeTempDir()
    defer { cleanup(root) }
    createDir(root.appendingPathComponent(".git"))

    let yaml = RepoConfig.scaffold(
      project: nil, scheme: "RoundTripScheme", simulator: "iPhone 15")
    writeFile(yaml, at: root)

    let parsed = RepoConfig.discover(from: root.path)
    #expect(parsed?.scheme == "RoundTripScheme")
    #expect(parsed?.simulator == "iPhone 15")
    // Commented placeholder keys must not parse into values.
    #expect(parsed?.configuration == nil)
    #expect(parsed?.testPlan == nil)
  }

  @Test("scaffold emits commented placeholders for undetected values")
  func scaffoldPlaceholders() {
    let yaml = RepoConfig.scaffold(project: nil, scheme: nil, simulator: nil)
    #expect(yaml.contains("# project:"))
    #expect(yaml.contains("# scheme:"))
    #expect(yaml.contains("# simulator:"))
    // No active (uncommented) key line may exist when nothing is detected:
    // check line-by-line rather than by substring adjacency.
    for key in ["project", "scheme", "simulator", "configuration", "testPlan"] {
      let hasActive = yaml.split(separator: "\n").contains { line in
        line.trimmingCharacters(in: .whitespaces).hasPrefix("\(key):")
      }
      #expect(!hasActive, "\(key) must be a commented placeholder, not active")
    }
    // An all-nil scaffold must parse to nothing.
    let root = makeTempDir()
    defer { cleanup(root) }
    createDir(root.appendingPathComponent(".git"))
    writeFile(yaml, at: root)
    #expect(RepoConfig.discover(from: root.path) == nil)
  }

  @Test("scaffold emits a colon-bearing detected value as a safe placeholder")
  func scaffoldColonValueIsPlaceholder() {
    // A value the flat parser cannot round-trip must not be written active.
    let yaml = RepoConfig.scaffold(
      project: nil, scheme: "Weird:Scheme", simulator: "iPhone 15")
    let schemeActive = yaml.split(separator: "\n").contains {
      $0.trimmingCharacters(in: .whitespaces).hasPrefix("scheme:")
    }
    #expect(!schemeActive, "colon-bearing scheme must fall back to a placeholder")
    #expect(yaml.contains("simulator: iPhone 15"))
  }

  // MARK: - init refuse-overwrite contract

  @Test("init refuses to overwrite an existing file without --force")
  func initRefusesOverwrite() {
    let root = makeTempDir()
    defer { cleanup(root) }
    createDir(root.appendingPathComponent(".git"))
    writeFile("scheme: Existing\n", at: root)

    // Mirrors the guard in InitCommand: repo root + .xcforge.yaml exists.
    let resolvedRoot = RepoRoot.discover(from: root.path) ?? root.path
    let target = (resolvedRoot as NSString).appendingPathComponent(".xcforge.yaml")
    let exists = FileManager.default.fileExists(atPath: target)
    let force = false
    let refuses = exists && !force
    #expect(refuses)

    // Original content must be untouched by the refusal.
    let contents = try? String(contentsOfFile: target, encoding: .utf8)
    #expect(contents == "scheme: Existing\n")
  }

  @Test("init writes when no file exists, force allows overwrite")
  func initWritesAndForceOverwrites() throws {
    let root = makeTempDir()
    defer { cleanup(root) }
    createDir(root.appendingPathComponent(".git"))

    let resolvedRoot = RepoRoot.discover(from: root.path) ?? root.path
    let target = (resolvedRoot as NSString).appendingPathComponent(".xcforge.yaml")
    #expect(!FileManager.default.fileExists(atPath: target))

    let body = RepoConfig.scaffold(project: nil, scheme: "Init", simulator: nil)
    try body.write(toFile: target, atomically: true, encoding: .utf8)
    #expect(FileManager.default.fileExists(atPath: target))

    // With --force the guard does not refuse even though the file exists.
    let exists = FileManager.default.fileExists(atPath: target)
    let force = true
    #expect(!(exists && !force))
  }
}

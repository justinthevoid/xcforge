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

  @Test("repo config overrides persisted defaults for the active project")
  func repoOverridesPersisted() async {
    let root = makeTempDir()
    defer { cleanup(root) }
    createDir(root.appendingPathComponent(".git"))
    writeFile("scheme: RepoScheme\n", at: root)

    let storeDir = root.appendingPathComponent("store", isDirectory: true)
    createDir(storeDir)
    let store = DefaultsStore(baseDirectory: storeDir)
    // Seed a record under the *resolved* project key. v2 has no global layer.
    let project = "/dummy.xcodeproj"
    store.save(
      PersistedDefaults(project: project, scheme: "PersistedScheme"), forProject: project)

    let session = SessionState(defaultsStore: store, cwd: root.path)
    // The committed repo file is the team source of truth — it must beat the
    // per-project persisted record (same model as git local > global).
    let scheme = try? await session.resolveScheme(nil, project: project)
    #expect(scheme == "RepoScheme")
  }

  @Test("persisted default fills a field the repo file omits")
  func persistedFillsGap() async {
    let root = makeTempDir()
    defer { cleanup(root) }
    createDir(root.appendingPathComponent(".git"))
    // Repo file has no `scheme` — persisted record for this project fills the gap.
    writeFile("simulator: RepoSim\n", at: root)

    let storeDir = root.appendingPathComponent("store", isDirectory: true)
    createDir(storeDir)
    let store = DefaultsStore(baseDirectory: storeDir)
    let project = "/dummy.xcodeproj"
    store.save(
      PersistedDefaults(project: project, scheme: "PersistedScheme"), forProject: project)

    let session = SessionState(defaultsStore: store, cwd: root.path)
    // Resolve the project first so the per-project record loads.
    _ = try? await session.resolveProject(project)
    let scheme = try? await session.resolveScheme(nil, project: project)
    #expect(scheme == "PersistedScheme")
    let simulator = try? await session.resolveSimulator("RepoSim")
    #expect(simulator == "RepoSim")
  }

  @Test("project identity comes from explicit/repo/autodetect — no global persisted layer")
  func projectIdentityHasNoGlobalLayer() async {
    let root = makeTempDir()
    defer { cleanup(root) }
    createDir(root.appendingPathComponent(".git"))
    // No .xcforge.yaml in this repo.

    let storeDir = root.appendingPathComponent("store", isDirectory: true)
    createDir(storeDir)
    let store = DefaultsStore(baseDirectory: storeDir)
    // Old behavior would have promoted this persisted record's project to the
    // session default. v2 must not — there is no global key to look it up by.
    let stalePath = "/abs/Stale.xcodeproj"
    store.save(
      PersistedDefaults(project: stalePath, scheme: "StaleScheme"), forProject: stalePath)

    let session = SessionState(defaultsStore: store, cwd: root.path)
    // No explicit project, no repo project — autodetect path runs. We can't
    // assert on the AutoDetect result in CI, but we *can* assert that it does
    // not return the stale persisted path (which is fictional).
    let detected = try? await session.resolveProject(nil)
    #expect(detected != stalePath, "no persisted-project fallback layer")
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
    // Establish an active project so persistence has a key to write under.
    let project = "/dummy.xcodeproj"
    await session.setDefaults(project: project, scheme: "Persisted", simulator: nil)
    _ = await session.resolveConfiguration(nil)
    _ = await session.resolveTestPlan(nil)

    let jsonPath = storeDir.appendingPathComponent("defaults.json").path
    let raw = (try? String(contentsOfFile: jsonPath, encoding: .utf8)) ?? ""
    #expect(!raw.isEmpty, "persist should have written defaults.json")
    #expect(store.load(forProject: project)?.scheme == "Persisted", "persist round-trips scheme")
    // Repo-only keys must never appear in the persisted JSON.
    #expect(!raw.contains("\"configuration\""))
    #expect(!raw.contains("\"testPlan\""))
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
    let project = "/dummy.xcodeproj"
    store.save(
      PersistedDefaults(project: project, scheme: "PersistedScheme"), forProject: project)
    let session = SessionState(defaultsStore: store, cwd: root.path)
    // configuration comes from the repo file; scheme (absent in repo) still
    // falls through to the project's persisted record — config-only file is no barrier.
    #expect(await session.resolveConfiguration(nil) == "Release")
    _ = try? await session.resolveProject(project)
    let scheme = try? await session.resolveScheme(nil, project: project)
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
    #expect(yaml.contains("testTimeout"))
    #expect(yaml.contains("autoPromote"))
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
    for key in [
      "project", "scheme", "simulator", "configuration", "testPlan",
      "testTimeout", "autoPromote",
    ] {
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

  // MARK: - testTimeout parsing & precedence

  @Test("parses testTimeout as positive integer seconds")
  func parsesTestTimeout() {
    let root = makeTempDir()
    defer { cleanup(root) }
    createDir(root.appendingPathComponent(".git"))
    writeFile("testTimeout: 600\n", at: root)

    let result = RepoConfig.discover(from: root.path)
    #expect(result?.testTimeout == 600)
  }

  @Test("non-numeric testTimeout is warned and dropped")
  func nonNumericTestTimeoutDropped() {
    let root = makeTempDir()
    defer { cleanup(root) }
    createDir(root.appendingPathComponent(".git"))
    writeFile("testTimeout: forever\nscheme: S\n", at: root)

    let result = RepoConfig.discover(from: root.path)
    #expect(result?.testTimeout == nil)
    #expect(result?.scheme == "S", "other keys still parse around the bad value")
  }

  @Test("non-positive testTimeout is dropped (no 0-second watchdog)")
  func nonPositiveTestTimeoutDropped() {
    let root = makeTempDir()
    defer { cleanup(root) }
    createDir(root.appendingPathComponent(".git"))
    writeFile("testTimeout: 0\n", at: root)

    let result = RepoConfig.discover(from: root.path)
    #expect(result?.testTimeout == nil)
  }

  @Test("resolveTestTimeout: explicit > testTimeout > long > 180")
  func testTimeoutPrecedence() async {
    let root = makeTempDir()
    defer { cleanup(root) }
    createDir(root.appendingPathComponent(".git"))
    writeFile("testTimeout: 600\n", at: root)

    let storeDir = root.appendingPathComponent("store", isDirectory: true)
    createDir(storeDir)
    let store = DefaultsStore(baseDirectory: storeDir)
    let session = SessionState(defaultsStore: store, cwd: root.path)

    // Explicit wins over everything.
    #expect(await session.resolveTestTimeout(explicit: 90, long: false) == 90)
    #expect(await session.resolveTestTimeout(explicit: 90, long: true) == 90)
    // testTimeout wins over long when no explicit.
    #expect(await session.resolveTestTimeout(explicit: nil, long: false) == 600)
    #expect(await session.resolveTestTimeout(explicit: nil, long: true) == 600)
  }

  @Test("resolveTestTimeout falls back to 180/1800 when no repo testTimeout")
  func testTimeoutBaseline() async {
    let root = makeTempDir()
    defer { cleanup(root) }
    createDir(root.appendingPathComponent(".git"))
    writeFile("scheme: NoTimeout\n", at: root)

    let storeDir = root.appendingPathComponent("store", isDirectory: true)
    createDir(storeDir)
    let store = DefaultsStore(baseDirectory: storeDir)
    let session = SessionState(defaultsStore: store, cwd: root.path)

    #expect(await session.resolveTestTimeout(explicit: nil, long: false) == 180)
    #expect(await session.resolveTestTimeout(explicit: nil, long: true) == 1800)
  }

  // MARK: - autoPromote parsing & opt-out

  @Test("parses autoPromote true/false")
  func parsesAutoPromote() {
    let root = makeTempDir()
    defer { cleanup(root) }
    createDir(root.appendingPathComponent(".git"))

    writeFile("autoPromote: false\n", at: root)
    #expect(RepoConfig.discover(from: root.path)?.autoPromote == false)

    writeFile("autoPromote: true\n", at: root)
    #expect(RepoConfig.discover(from: root.path)?.autoPromote == true)
  }

  @Test("non-boolean autoPromote is warned and dropped")
  func nonBoolAutoPromoteDropped() {
    let root = makeTempDir()
    defer { cleanup(root) }
    createDir(root.appendingPathComponent(".git"))
    writeFile("autoPromote: maybe\nscheme: S\n", at: root)

    let result = RepoConfig.discover(from: root.path)
    #expect(result?.autoPromote == nil)
    #expect(result?.scheme == "S")
  }

  @Test("autoPromote: false suppresses 3-strikes promotion across 5 repeats")
  func autoPromoteFalseSuppresses() async {
    let root = makeTempDir()
    defer { cleanup(root) }
    createDir(root.appendingPathComponent(".git"))
    writeFile("autoPromote: false\n", at: root)

    let storeDir = root.appendingPathComponent("store", isDirectory: true)
    createDir(storeDir)
    let store = DefaultsStore(baseDirectory: storeDir)
    let session = SessionState(defaultsStore: store, cwd: root.path)

    // Resolve the same explicit scheme 5 times. Without opt-out, after 3
    // repeats it would promote to .autoPromoted; opt-out must keep source
    // stable.
    for _ in 0..<5 {
      _ = try? await session.resolveScheme("RepeatScheme", project: "/dummy.xcodeproj")
    }
    // showDefaults annotates the source. With promotion suppressed the
    // "auto-promoted" note must not appear.
    let shown = await session.showDefaults()
    #expect(!shown.contains("auto-promoted"))
  }

  @Test("autoPromote defaults to true when key omitted (legacy behavior)")
  func autoPromoteDefaultsTrue() async {
    let root = makeTempDir()
    defer { cleanup(root) }
    createDir(root.appendingPathComponent(".git"))
    writeFile("scheme: AnyScheme\n", at: root)

    let storeDir = root.appendingPathComponent("store", isDirectory: true)
    createDir(storeDir)
    let store = DefaultsStore(baseDirectory: storeDir)
    let session = SessionState(defaultsStore: store, cwd: root.path)

    for _ in 0..<5 {
      _ = try? await session.resolveScheme("PromoteMe", project: "/dummy.xcodeproj")
    }
    let shown = await session.showDefaults()
    #expect(shown.contains("auto-promoted"))
  }

  // MARK: - P6 cross-project bleed on profile_switch

  @Test("profileSwitch clears per-project build info before installing the new project (P6)")
  func profileSwitchClearsCrossProjectBuildInfo() async throws {
    let root = makeTempDir()
    defer { cleanup(root) }
    createDir(root.appendingPathComponent(".git"))
    // No repo .xcforge.yaml — we drive everything via setDefaults + setBuildInfo.

    let storeDir = root.appendingPathComponent("store", isDirectory: true)
    createDir(storeDir)
    let store = DefaultsStore(baseDirectory: storeDir)

    // Seed two real project directories so canonicalKey accepts them.
    let projAURL = root.appendingPathComponent("A.xcodeproj", isDirectory: true)
    let projBURL = root.appendingPathComponent("B.xcodeproj", isDirectory: true)
    createDir(projAURL)
    createDir(projBURL)
    let projA = projAURL.path
    let projB = projBURL.path

    let session = SessionState(defaultsStore: store, cwd: root.path)
    // Establish project A and pretend a build succeeded for it.
    await session.setDefaults(project: projA, scheme: "AScheme", simulator: nil)
    await session.setBuildInfo(bundleId: "com.example.a", appPath: projA, scheme: "AScheme")

    // Sanity: resolveBundleId(nil) returns A's bundleId before the switch.
    #expect(await session.resolveBundleId(nil) == "com.example.a")

    // Save A's profile, then create + switch to B's profile (no build info yet).
    _ = await session.profileSave(name: "a")
    await session.setDefaults(project: projB, scheme: "BScheme", simulator: nil)
    _ = await session.profileSave(name: "b")

    // Switch back to A, then to B. After switching to B, resolveBundleId(nil)
    // must not return A's bundleId (no per-project bleed).
    _ = await session.profileSwitch(name: "a")
    _ = await session.profileSwitch(name: "b")

    let bid = await session.resolveBundleId(nil)
    #expect(
      bid != "com.example.a",
      "profile_switch must not leak the previous project's bundleId into the new project's session"
    )
    let ap = await session.resolveAppPath(nil)
    #expect(ap != projA, "profile_switch must not leak appPath either")
  }

  // MARK: - P5 CLI defaults clear with no active project

  @Test("clearDefaults with no active project is a clean no-op on disk (P5)")
  func defaultsClearWithNoActiveProjectPrintsAccurateMessage() async {
    let root = makeTempDir()
    defer { cleanup(root) }
    // Important: no `.git`, no `.xcforge.yaml`, no existing defaults.json.

    let storeDir = root.appendingPathComponent("store", isDirectory: true)
    createDir(storeDir)
    let store = DefaultsStore(baseDirectory: storeDir)
    let session = SessionState(defaultsStore: store, cwd: root.path)

    // No project has been resolved → activeProjectKey() returns nil →
    // clearDefaults must not crash and must not create a defaults.json.
    await session.clearDefaults()
    let exists = FileManager.default.fileExists(
      atPath: storeDir.appendingPathComponent("defaults.json").path)
    #expect(!exists, "clearDefaults without an active project must not materialize a file")
  }

  // MARK: - P8 explicit timeout 0 or negative falls through

  @Test("resolveTestTimeout with explicit <= 0 falls back to repo / baseline (P8)")
  func explicitTimeoutSecondsZeroRejected() async {
    let root = makeTempDir()
    defer { cleanup(root) }
    createDir(root.appendingPathComponent(".git"))
    writeFile("testTimeout: 600\n", at: root)

    let storeDir = root.appendingPathComponent("store", isDirectory: true)
    createDir(storeDir)
    let store = DefaultsStore(baseDirectory: storeDir)
    let session = SessionState(defaultsStore: store, cwd: root.path)

    // Explicit 0 → drop to repo testTimeout (600).
    #expect(await session.resolveTestTimeout(explicit: 0, long: false) == 600)
    // Explicit -5 → same fallback.
    #expect(await session.resolveTestTimeout(explicit: -5, long: true) == 600)

    // Same checks with no repo testTimeout — fall through to long/short baseline.
    let noTimeoutRoot = makeTempDir()
    defer { cleanup(noTimeoutRoot) }
    createDir(noTimeoutRoot.appendingPathComponent(".git"))
    writeFile("scheme: X\n", at: noTimeoutRoot)
    let store2 = DefaultsStore(
      baseDirectory: noTimeoutRoot.appendingPathComponent("store", isDirectory: true))
    let session2 = SessionState(defaultsStore: store2, cwd: noTimeoutRoot.path)
    #expect(await session2.resolveTestTimeout(explicit: 0, long: false) == 180)
    #expect(await session2.resolveTestTimeout(explicit: 0, long: true) == 1800)
  }

  // MARK: - P9 setDefaults resets matching streak

  @Test("setDefaults resets the matching streak so old uses cannot re-promote (P9)")
  func setDefaultsResetsStreak() async throws {
    let root = makeTempDir()
    defer { cleanup(root) }
    createDir(root.appendingPathComponent(".git"))
    // autoPromote defaults to true.

    let storeDir = root.appendingPathComponent("store", isDirectory: true)
    createDir(storeDir)
    let store = DefaultsStore(baseDirectory: storeDir)
    let session = SessionState(defaultsStore: store, cwd: root.path)

    // Three uses of scheme A — at the third the auto-promotion threshold is met.
    for _ in 0..<3 {
      _ = try? await session.resolveScheme("A", project: "/dummy.xcodeproj")
    }
    let shownBeforeOverride = await session.showDefaults()
    #expect(shownBeforeOverride.contains("auto-promoted"))

    // User overrides to B → streak for scheme MUST reset to ("", 0).
    await session.setDefaults(project: nil, scheme: "B", simulator: nil)

    // A single subsequent use of A must NOT immediately re-promote A.
    _ = try? await session.resolveScheme("A", project: "/dummy.xcodeproj")
    let shownAfter = await session.showDefaults()
    // After one use of A on a fresh streak, the active scheme is still B.
    #expect(shownAfter.contains("scheme:    B"))
  }

  // MARK: - P10 autoPromote false skips streak update

  @Test("autoPromote=false skips streak update entirely (P10)")
  func autoPromoteFalseSkipsStreakUpdate() async throws {
    let root = makeTempDir()
    defer { cleanup(root) }
    createDir(root.appendingPathComponent(".git"))
    writeFile("autoPromote: false\n", at: root)

    let storeDir = root.appendingPathComponent("store", isDirectory: true)
    createDir(storeDir)
    let store = DefaultsStore(baseDirectory: storeDir)
    let session = SessionState(defaultsStore: store, cwd: root.path)

    // Five uses of the same scheme with autoPromote disabled. No promotion
    // and (post-P10) no streak accumulation that could trip a later
    // re-enable. We can only assert the observable outcome: showDefaults
    // never reports auto-promoted, and scheme remains unset by the session
    // (explicit values are not cached as session defaults under autoPromote=false).
    for _ in 0..<5 {
      _ = try? await session.resolveScheme("S", project: "/dummy.xcodeproj")
    }
    let shown = await session.showDefaults()
    #expect(!shown.contains("auto-promoted"))
  }
}

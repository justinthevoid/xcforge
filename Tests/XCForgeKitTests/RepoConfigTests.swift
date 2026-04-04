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

  // MARK: - Priority chain

  @Test("persisted defaults override repo config")
  func persistedOverridesRepo() async {
    let root = makeTempDir()
    defer { cleanup(root) }
    createDir(root.appendingPathComponent(".git"))
    writeFile("scheme: RepoScheme\n", at: root)

    let storeDir = root.appendingPathComponent("store", isDirectory: true)
    createDir(storeDir)
    let store = DefaultsStore(baseDirectory: storeDir)
    store.save(PersistedDefaults(scheme: "PersistedScheme"))

    let session = SessionState(defaultsStore: store, cwd: root.path)
    // resolveScheme needs a project — use a dummy since we only test scheme resolution priority
    // The persisted value should win over repo config
    let scheme = try? await session.resolveScheme(nil, project: "/dummy.xcodeproj")
    #expect(scheme == "PersistedScheme")
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
}

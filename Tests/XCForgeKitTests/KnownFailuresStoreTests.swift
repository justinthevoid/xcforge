import Foundation
import Testing

@testable import XCForgeKit

@Suite("KnownFailuresStore: tolerant YAML loader", .serialized)
struct KnownFailuresStoreTests {

  private func makeRepoRoot() -> URL {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("xcforge-known-\(UUID().uuidString)", isDirectory: true)
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  private func cleanup(_ dir: URL) { try? FileManager.default.removeItem(at: dir) }

  private func writeRegistry(_ contents: String, at root: URL) {
    let configDir = root.appendingPathComponent(".xcforge", isDirectory: true)
    try! FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
    let file = configDir.appendingPathComponent("known-failures.yaml")
    try! contents.write(to: file, atomically: true, encoding: .utf8)
  }

  @Test("missing file returns empty result with no warning")
  func missingFile() {
    let root = makeRepoRoot()
    defer { cleanup(root) }
    let result = KnownFailuresStore.load(repoRoot: root.path)
    #expect(result.ids.isEmpty)
    #expect(result.warning == nil)
  }

  @Test("valid registry parses three-field items")
  func validRegistry() {
    let root = makeRepoRoot()
    defer { cleanup(root) }
    writeRegistry(
      """
      - id: SuiteA/testFoo
        reason: flaky on CI
        first_seen: 2026-05-01
      - id: SuiteB/testBar
        reason: pending fix
        first_seen: 2026-05-02
      """, at: root)
    let result = KnownFailuresStore.load(repoRoot: root.path)
    #expect(result.ids == ["SuiteA/testFoo", "SuiteB/testBar"])
    #expect(result.warning == nil)
  }

  @Test("quoted id values are unquoted")
  func quotedIDs() {
    let root = makeRepoRoot()
    defer { cleanup(root) }
    writeRegistry(
      """
      - id: "Suite With Space/test"
        reason: ws
        first_seen: 2026-05-03
      """, at: root)
    let result = KnownFailuresStore.load(repoRoot: root.path)
    #expect(result.ids == ["Suite With Space/test"])
  }

  @Test("malformed content (no list entries) emits a warning")
  func malformedNoList() {
    let root = makeRepoRoot()
    defer { cleanup(root) }
    writeRegistry("garbled: not a list\nfoo bar baz\n", at: root)
    let result = KnownFailuresStore.load(repoRoot: root.path)
    #expect(result.ids.isEmpty)
    #expect(result.warning != nil)
  }

  @Test("comments and blank lines are skipped")
  func commentsAndBlanks() {
    let root = makeRepoRoot()
    defer { cleanup(root) }
    writeRegistry(
      """
      # registry version 1

      - id: A/b
        reason: x
        first_seen: 2026-01-01

      # trailing comment
      """, at: root)
    let result = KnownFailuresStore.load(repoRoot: root.path)
    #expect(result.ids == ["A/b"])
  }

  @Test("item missing id raises a skipped-item warning")
  func itemMissingID() {
    let root = makeRepoRoot()
    defer { cleanup(root) }
    writeRegistry(
      """
      - reason: orphan
        first_seen: 2026-05-04
      - id: Good/ok
        reason: ok
        first_seen: 2026-05-05
      """, at: root)
    let result = KnownFailuresStore.load(repoRoot: root.path)
    #expect(result.ids == ["Good/ok"])
    #expect(result.warning?.contains("missing 'id'") == true)
  }

  @Test("empty file returns empty result")
  func emptyFile() {
    let root = makeRepoRoot()
    defer { cleanup(root) }
    writeRegistry("", at: root)
    let result = KnownFailuresStore.load(repoRoot: root.path)
    #expect(result.ids.isEmpty)
    #expect(result.warning == nil)
  }
}

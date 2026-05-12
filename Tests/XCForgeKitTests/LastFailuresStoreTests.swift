import Foundation
import Testing

@testable import XCForgeKit

@Suite("LastFailuresStore: atomic write/read/clear", .serialized)
struct LastFailuresStoreTests {

  private func makeRepoRoot() -> URL {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("xcforge-lastfail-\(UUID().uuidString)", isDirectory: true)
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  private func cleanup(_ dir: URL) { try? FileManager.default.removeItem(at: dir) }

  @Test("write then read roundtrips failure IDs and scheme metadata")
  func roundTrip() {
    let root = makeRepoRoot()
    defer { cleanup(root) }
    let ok = LastFailuresStore.write(
      failures: ["A/test1", "B/test2"], scheme: "MyApp", simulator: "iPhone 16",
      at: root.path)
    #expect(ok)

    let read = LastFailuresStore.read(at: root.path)
    #expect(read?.failures == ["A/test1", "B/test2"])
    #expect(read?.scheme == "MyApp")
    #expect(read?.simulator == "iPhone 16")
  }

  @Test("read returns nil when file is absent")
  func readMissing() {
    let root = makeRepoRoot()
    defer { cleanup(root) }
    #expect(LastFailuresStore.read(at: root.path) == nil)
  }

  @Test("write overwrites prior payload atomically")
  func writeOverwrite() {
    let root = makeRepoRoot()
    defer { cleanup(root) }
    _ = LastFailuresStore.write(
      failures: ["X/old"], scheme: nil, simulator: nil, at: root.path)
    _ = LastFailuresStore.write(
      failures: ["Y/new1", "Y/new2"], scheme: nil, simulator: nil, at: root.path)
    let read = LastFailuresStore.read(at: root.path)
    #expect(read?.failures == ["Y/new1", "Y/new2"])
  }

  @Test("atomic write does not leave .tmp residue")
  func atomicNoTempResidue() {
    let root = makeRepoRoot()
    defer { cleanup(root) }
    _ = LastFailuresStore.write(
      failures: ["A/b"], scheme: nil, simulator: nil, at: root.path)
    let tmpPath = LastFailuresStore.path(at: root.path) + ".tmp"
    #expect(!FileManager.default.fileExists(atPath: tmpPath))
  }

  @Test("clear removes existing file")
  func clearRemovesFile() {
    let root = makeRepoRoot()
    defer { cleanup(root) }
    _ = LastFailuresStore.write(
      failures: ["A/b"], scheme: nil, simulator: nil, at: root.path)
    #expect(FileManager.default.fileExists(atPath: LastFailuresStore.path(at: root.path)))
    LastFailuresStore.clear(at: root.path)
    #expect(!FileManager.default.fileExists(atPath: LastFailuresStore.path(at: root.path)))
  }

  @Test("clear is a no-op when file is absent")
  func clearAbsent() {
    let root = makeRepoRoot()
    defer { cleanup(root) }
    LastFailuresStore.clear(at: root.path)  // must not throw
    #expect(LastFailuresStore.read(at: root.path) == nil)
  }

  @Test("write creates .xcforge directory when missing")
  func createsDirectory() {
    let root = makeRepoRoot()
    defer { cleanup(root) }
    let dir = root.appendingPathComponent(".xcforge")
    #expect(!FileManager.default.fileExists(atPath: dir.path))
    _ = LastFailuresStore.write(
      failures: ["A/b"], scheme: nil, simulator: nil, at: root.path)
    var isDir: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir)
    #expect(exists)
    #expect(isDir.boolValue)
  }
}

import Foundation
import Testing

@testable import XCForgeKit

@Suite("DefaultsStore: persistence round-trip", .serialized)
struct DefaultsStoreTests {

  private func makeTempStore() -> (DefaultsStore, URL) {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("xcforge-test-\(UUID().uuidString)", isDirectory: true)
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let store = DefaultsStore(baseDirectory: dir)
    return (store, dir)
  }

  private func cleanup(_ dir: URL) {
    try? FileManager.default.removeItem(at: dir)
  }

  @Test("save and load round-trip preserves all fields")
  func roundTrip() {
    let (store, dir) = makeTempStore()
    defer { cleanup(dir) }

    // Use the temp dir for path-shaped fields so the stale-path filter (which
    // strips non-existent project / appPath entries on load) does not interfere.
    let defaults = PersistedDefaults(
      project: dir.path,
      scheme: "FooScheme",
      simulator: "iPhone 16",
      bundleId: "com.example.foo",
      appPath: dir.path
    )

    store.save(defaults)
    let loaded = store.load()

    #expect(loaded == defaults)
  }

  @Test("load returns nil when no file exists")
  func loadMissingFile() {
    let (store, dir) = makeTempStore()
    defer { cleanup(dir) }

    #expect(store.load() == nil)
  }

  @Test("clear removes the defaults file")
  func clearRemovesFile() {
    let (store, dir) = makeTempStore()
    defer { cleanup(dir) }

    store.save(PersistedDefaults(project: dir.path))
    #expect(store.load() != nil)

    store.clear()
    #expect(store.load() == nil)
    #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))
  }

  @Test("clear is safe when no file exists")
  func clearNoFile() {
    let (store, dir) = makeTempStore()
    defer { cleanup(dir) }

    // Should not throw
    store.clear()
  }

  @Test("corrupt file returns nil and does not crash")
  func corruptFile() {
    let (store, dir) = makeTempStore()
    defer { cleanup(dir) }

    try! FileManager.default.createDirectory(
      at: store.fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try! Data("not json".utf8).write(to: store.fileURL)

    #expect(store.load() == nil)
  }

  @Test("save merges new values with existing persisted defaults")
  func updateExisting() {
    let (store, dir) = makeTempStore()
    defer { cleanup(dir) }

    store.save(PersistedDefaults(project: dir.path, scheme: "A"))

    // Simulate update: load, modify, save
    var existing = store.load()!
    existing.scheme = "B"
    store.save(existing)

    let loaded = store.load()
    #expect(loaded?.project == dir.path)
    #expect(loaded?.scheme == "B")
  }

  @Test("PersistedDefaults.isEmpty is true when all fields are nil")
  func isEmptyCheck() {
    #expect(PersistedDefaults().isEmpty)
    #expect(!PersistedDefaults(project: "/path").isEmpty)
  }

  @Test("save with nil fields preserves existing disk values")
  func mergePreservesExisting() {
    let (store, dir) = makeTempStore()
    defer { cleanup(dir) }

    store.save(PersistedDefaults(project: dir.path, scheme: "A", simulator: "iPhone 16"))

    // Save with only project — scheme and simulator should survive
    let secondPath = dir.appendingPathComponent("nested", isDirectory: true)
    try! FileManager.default.createDirectory(at: secondPath, withIntermediateDirectories: true)
    store.save(PersistedDefaults(project: secondPath.path))

    let loaded = store.load()
    #expect(loaded?.project == secondPath.path)
    #expect(loaded?.scheme == "A")
    #expect(loaded?.simulator == "iPhone 16")
  }

  @Test("concurrent saves with disjoint fields both survive")
  func concurrentDisjointSaves() async {
    let (store, dir) = makeTempStore()
    defer { cleanup(dir) }

    // Run two concurrent saves with disjoint fields. Use the temp dir's path
    // for `project` so the stale-path filter does not strip it on load.
    let projectPath = dir.path
    await withTaskGroup(of: Void.self) { group in
      group.addTask {
        store.save(PersistedDefaults(project: projectPath))
      }
      group.addTask {
        store.save(PersistedDefaults(scheme: "ConcurrentScheme"))
      }
    }

    let loaded = store.load()
    #expect(loaded?.project == projectPath)
    #expect(loaded?.scheme == "ConcurrentScheme")
  }

  @Test("load drops stale project and appPath when files no longer exist")
  func loadFiltersStalePaths() throws {
    let (store, dir) = makeTempStore()
    defer { cleanup(dir) }

    // Bypass the save() filter by writing the file directly with a non-existent path,
    // simulating a defaults.json shipped from another machine or pointing at a
    // since-deleted DerivedData app bundle.
    let stale = PersistedDefaults(
      project: "/tmp/Fake.xcodeproj",
      scheme: "FakeScheme",
      simulator: "iPhone Test",
      bundleId: "com.example.fake",
      appPath: "/tmp/Fake.app"
    )
    try FileManager.default.createDirectory(
      at: store.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    let data = try encoder.encode(stale)
    try data.write(to: store.fileURL)

    let loaded = store.load()
    #expect(loaded != nil)
    // Path-shaped stale fields are dropped.
    #expect(loaded?.project == nil)
    #expect(loaded?.appPath == nil)
    // Non-path fields survive — they may still be valid even if paths are stale.
    #expect(loaded?.scheme == "FakeScheme")
    #expect(loaded?.simulator == "iPhone Test")
    #expect(loaded?.bundleId == "com.example.fake")
  }

  @Test("merging applies non-nil fields from other over self")
  func mergingLogic() {
    let base = PersistedDefaults(project: "/base", scheme: "BaseScheme", simulator: "iPhone 15")
    let overlay = PersistedDefaults(project: "/overlay", scheme: nil, simulator: "iPhone 16")

    let merged = base.merging(overlay)
    #expect(merged.project == "/overlay")
    #expect(merged.scheme == "BaseScheme")
    #expect(merged.simulator == "iPhone 16")
  }
}

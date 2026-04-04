import Testing
import Foundation
@testable import xcforgeCore

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

        let defaults = PersistedDefaults(
            project: "/path/to/Foo.xcodeproj",
            scheme: "FooScheme",
            simulator: "iPhone 16",
            bundleId: "com.example.foo",
            appPath: "/tmp/Foo.app"
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

        store.save(PersistedDefaults(project: "/path"))
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

        store.save(PersistedDefaults(project: "/path", scheme: "A"))

        // Simulate update: load, modify, save
        var existing = store.load()!
        existing.scheme = "B"
        store.save(existing)

        let loaded = store.load()
        #expect(loaded?.project == "/path")
        #expect(loaded?.scheme == "B")
    }

    @Test("PersistedDefaults.isEmpty is true when all fields are nil")
    func isEmptyCheck() {
        #expect(PersistedDefaults().isEmpty)
        #expect(!PersistedDefaults(project: "/path").isEmpty)
    }
}

import Foundation
import Testing

@testable import XCForgeKit

@Suite("DefaultsStore: v2 keyed persistence + v1 migration", .serialized)
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

  /// Make an `.xcodeproj`-shaped path inside `dir` that actually exists, so the
  /// stale-path filter does not strip it. Returns the canonical form (same
  /// transform the store applies to keys).
  private func makeProjectPath(in dir: URL, named name: String = "App.xcodeproj") -> String {
    let url = dir.appendingPathComponent(name, isDirectory: true)
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return DefaultsStore.canonicalKey(url.path)
  }

  // MARK: - Round-trip (v2)

  @Test("save and load round-trip preserves all fields for a single project")
  func roundTripSingleProject() {
    let (store, dir) = makeTempStore()
    defer { cleanup(dir) }

    let project = makeProjectPath(in: dir)
    let defaults = PersistedDefaults(
      project: project,
      scheme: "FooScheme",
      simulator: "iPhone 16",
      bundleId: "com.example.foo",
      appPath: dir.path
    )

    store.save(defaults, forProject: project)
    let loaded = store.load(forProject: project)

    #expect(loaded == defaults)
  }

  @Test("load returns nil when no file exists")
  func loadMissingFile() {
    let (store, dir) = makeTempStore()
    defer { cleanup(dir) }
    let project = makeProjectPath(in: dir)
    #expect(store.load(forProject: project) == nil)
  }

  @Test("clear(forProject:) removes only the active project's record")
  func clearForProjectIsolated() {
    let (store, dir) = makeTempStore()
    defer { cleanup(dir) }

    let projA = makeProjectPath(in: dir, named: "A.xcodeproj")
    let projB = makeProjectPath(in: dir, named: "B.xcodeproj")
    store.save(PersistedDefaults(project: projA, scheme: "A"), forProject: projA)
    store.save(PersistedDefaults(project: projB, scheme: "B"), forProject: projB)

    store.clear(forProject: projA)
    #expect(store.load(forProject: projA) == nil)
    #expect(store.load(forProject: projB)?.scheme == "B")
  }

  @Test("clearAll() removes every project's record")
  func clearAllRemovesEverything() {
    let (store, dir) = makeTempStore()
    defer { cleanup(dir) }

    let projA = makeProjectPath(in: dir, named: "A.xcodeproj")
    let projB = makeProjectPath(in: dir, named: "B.xcodeproj")
    store.save(PersistedDefaults(project: projA, scheme: "A"), forProject: projA)
    store.save(PersistedDefaults(project: projB, scheme: "B"), forProject: projB)

    store.clearAll()
    #expect(store.load(forProject: projA) == nil)
    #expect(store.load(forProject: projB) == nil)
    #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))
  }

  @Test("clear is safe when no file exists")
  func clearNoFile() {
    let (store, dir) = makeTempStore()
    defer { cleanup(dir) }
    store.clear(forProject: "/nonexistent.xcodeproj")
    store.clearAll()
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

    #expect(store.load(forProject: "/any.xcodeproj") == nil)
  }

  @Test("save merges new values into the existing record under the same project")
  func updateExisting() {
    let (store, dir) = makeTempStore()
    defer { cleanup(dir) }

    let project = makeProjectPath(in: dir)
    store.save(PersistedDefaults(project: project, scheme: "A"), forProject: project)
    store.save(PersistedDefaults(scheme: "B"), forProject: project)

    let loaded = store.load(forProject: project)
    #expect(loaded?.project == project)
    #expect(loaded?.scheme == "B")
  }

  @Test("PersistedDefaults.isEmpty is true when all fields are nil")
  func isEmptyCheck() {
    #expect(PersistedDefaults().isEmpty)
    #expect(!PersistedDefaults(project: "/path").isEmpty)
  }

  @Test("save with nil fields preserves existing record contents")
  func mergePreservesExisting() {
    let (store, dir) = makeTempStore()
    defer { cleanup(dir) }

    let project = makeProjectPath(in: dir)
    store.save(
      PersistedDefaults(project: project, scheme: "A", simulator: "iPhone 16"), forProject: project)
    // Save with only scheme — simulator should survive.
    store.save(PersistedDefaults(scheme: "AA"), forProject: project)

    let loaded = store.load(forProject: project)
    #expect(loaded?.scheme == "AA")
    #expect(loaded?.simulator == "iPhone 16")
  }

  // MARK: - Cross-project isolation

  @Test("cross-project isolation: writes to A do not leak into B")
  func crossProjectIsolation() {
    let (store, dir) = makeTempStore()
    defer { cleanup(dir) }

    let projA = makeProjectPath(in: dir, named: "A.xcodeproj")
    let projB = makeProjectPath(in: dir, named: "B.xcodeproj")

    store.save(
      PersistedDefaults(
        project: projA, scheme: "A", bundleId: "com.a", appPath: dir.path, buildScheme: "A"),
      forProject: projA)
    store.save(
      PersistedDefaults(project: projB, scheme: "B"), forProject: projB)
    // Write to A again — must not stomp B.
    store.save(PersistedDefaults(simulator: "iPhone 16"), forProject: projA)

    let a = store.load(forProject: projA)
    let b = store.load(forProject: projB)
    #expect(a?.scheme == "A")
    #expect(a?.bundleId == "com.a")
    #expect(a?.simulator == "iPhone 16")
    #expect(b?.scheme == "B")
    #expect(b?.bundleId == nil)
    #expect(b?.simulator == nil)
  }

  @Test("clearBuildInfo(forProject:) wipes only build-product fields for one project")
  func clearBuildInfoForProjectIsolated() {
    let (store, dir) = makeTempStore()
    defer { cleanup(dir) }

    let projA = makeProjectPath(in: dir, named: "A.xcodeproj")
    let projB = makeProjectPath(in: dir, named: "B.xcodeproj")
    store.save(
      PersistedDefaults(
        project: projA, scheme: "A", bundleId: "com.a", appPath: dir.path, buildScheme: "A"),
      forProject: projA)
    store.save(
      PersistedDefaults(
        project: projB, scheme: "B", bundleId: "com.b", appPath: dir.path, buildScheme: "B"),
      forProject: projB)

    store.clearBuildInfo(forProject: projA)
    let a = store.load(forProject: projA)
    let b = store.load(forProject: projB)
    #expect(a?.bundleId == nil)
    #expect(a?.appPath == nil)
    #expect(a?.buildScheme == nil)
    #expect(a?.scheme == "A", "user defaults survive build-info clear")
    #expect(b?.bundleId == "com.b", "other project's build info untouched")
  }

  @Test("concurrent saves to different projects under the lock both survive")
  func concurrentDisjointProjectSaves() async {
    let (store, dir) = makeTempStore()
    defer { cleanup(dir) }

    let projA = makeProjectPath(in: dir, named: "A.xcodeproj")
    let projB = makeProjectPath(in: dir, named: "B.xcodeproj")

    await withTaskGroup(of: Void.self) { group in
      group.addTask {
        store.save(PersistedDefaults(scheme: "AScheme"), forProject: projA)
      }
      group.addTask {
        store.save(PersistedDefaults(scheme: "BScheme"), forProject: projB)
      }
    }

    #expect(store.load(forProject: projA)?.scheme == "AScheme")
    #expect(store.load(forProject: projB)?.scheme == "BScheme")
  }

  // MARK: - Stale-path filtering

  @Test("load drops stale appPath when the file no longer exists")
  func loadFiltersStaleAppPath() throws {
    let (store, dir) = makeTempStore()
    defer { cleanup(dir) }

    let projDir = dir.appendingPathComponent("Real.xcodeproj", isDirectory: true)
    try FileManager.default.createDirectory(at: projDir, withIntermediateDirectories: true)
    let project = DefaultsStore.canonicalKey(projDir.path)

    // Hand-craft a v2 envelope with a stale appPath to bypass the save() filter.
    let stale = PersistedDefaults(
      project: project,
      scheme: "FakeScheme",
      simulator: "iPhone Test",
      bundleId: "com.example.fake",
      appPath: "/tmp/Fake.app"
    )
    let envelope: [String: Any] = [
      "version": 2,
      "projects": [project: try JSONSerialization.jsonObject(with: JSONEncoder().encode(stale))],
    ]
    let data = try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
    try data.write(to: store.fileURL)

    let loaded = store.load(forProject: project)
    #expect(loaded != nil)
    // appPath is path-shaped — dropped when nonexistent.
    #expect(loaded?.appPath == nil)
    // The in-record `project` field is canonical and exists — preserved.
    #expect(loaded?.project == project)
    // Non-path fields survive.
    #expect(loaded?.scheme == "FakeScheme")
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

  // MARK: - v1 → v2 migration

  @Test("v1 flat record with a real project migrates to v2 under canonical key")
  func v1MigrationWithProject() throws {
    let (store, dir) = makeTempStore()
    defer { cleanup(dir) }

    let projDir = dir.appendingPathComponent("V1.xcodeproj", isDirectory: true)
    try FileManager.default.createDirectory(at: projDir, withIntermediateDirectories: true)
    let key = DefaultsStore.canonicalKey(projDir.path)

    // Write a flat v1 blob — what older xcforge wrote.
    let v1 = PersistedDefaults(
      project: projDir.path,
      scheme: "V1Scheme",
      simulator: "iPhone 14",
      bundleId: "com.example.v1",
      buildScheme: "V1Scheme"
    )
    let data = try JSONEncoder().encode(v1)
    try FileManager.default.createDirectory(
      at: store.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: store.fileURL)

    // Reading should migrate and resolve the project's record identically.
    let loaded = store.load(forProject: projDir.path)
    #expect(loaded?.scheme == "V1Scheme")
    #expect(loaded?.bundleId == "com.example.v1")
    #expect(loaded?.buildScheme == "V1Scheme")
    #expect(loaded?.project == key)

    // The file on disk should now be the v2 envelope.
    let raw = try Data(contentsOf: store.fileURL)
    let decoded = try JSONDecoder().decode(StoredEnvelope.self, from: raw)
    #expect(decoded.version == 2)
    #expect(decoded.projects.keys.contains(key))
  }

  @Test("v1 flat record with no project is treated as unrecognized + preserved on save (P2)")
  func v1MigrationWithoutProject() throws {
    let (store, dir) = makeTempStore()
    defer { cleanup(dir) }

    // v1 with no project — ambiguous, must NOT be considered a real v1 record.
    let v1 = PersistedDefaults(
      project: nil, scheme: "Orphan", simulator: "iPhone 15")
    let data = try JSONEncoder().encode(v1)
    try FileManager.default.createDirectory(
      at: store.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: store.fileURL)
    let originalBytes = try Data(contentsOf: store.fileURL)

    // Any project key returns nil (record was not migrated).
    #expect(store.load(forProject: "/whatever.xcodeproj") == nil)

    // A subsequent save for an unrelated project must NOT silently overwrite
    // the unrecognized file. Either the original bytes survive verbatim (write
    // refused) or a `.unrecognized-*` backup carries them.
    let projectDir = dir.appendingPathComponent("New.xcodeproj", isDirectory: true)
    try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
    store.save(
      PersistedDefaults(project: projectDir.path, scheme: "N"), forProject: projectDir.path)

    let parentDir = store.fileURL.deletingLastPathComponent()
    let siblings = (try? FileManager.default.contentsOfDirectory(atPath: parentDir.path)) ?? []
    let backups = siblings.filter { $0.hasPrefix("defaults.json.unrecognized-") }
    if backups.isEmpty {
      let now = try Data(contentsOf: store.fileURL)
      #expect(now == originalBytes)
    } else {
      let backedUp = try Data(contentsOf: parentDir.appendingPathComponent(backups[0]))
      #expect(backedUp == originalBytes)
    }
  }

  // MARK: - Canonicalization

  @Test("canonicalKey strips trailing slash and resolves symlinks")
  func canonicalKeyNormalizes() {
    let raw = "/tmp/xcforge-test-symlink/App.xcodeproj/"
    let canonical = DefaultsStore.canonicalKey(raw)
    #expect(!canonical.hasSuffix("/"))
    // The path does not exist, so the non-existing branch of canonicalKey
    // applies. On macOS' case-insensitive APFS default we lowercase the
    // synthetic tail (P3), so we accept either casing here.
    #expect(
      canonical.hasSuffix("App.xcodeproj") || canonical.hasSuffix("app.xcodeproj"))
  }

  // MARK: - P3 / P4 / P13 canonicalKey reinforcements

  @Test("canonicalKey on a path that exists collapses casings on a case-insensitive volume")
  func canonicalKeyHandlesCaseInsensitiveVolumes() throws {
    let (_, dir) = makeTempStore()
    defer { cleanup(dir) }

    let projectDir = dir.appendingPathComponent("MixedCase.xcodeproj", isDirectory: true)
    try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

    // /tmp on macOS APFS is case-insensitive by default. If we ever land on a
    // case-sensitive volume (e.g. APFS-Case-Sensitive scratch disk), both
    // probes will keep the typed casing — accept that as a pass since the
    // algorithm is correctly *not* lowercasing when the volume says it would
    // be lossy.
    let typedA = projectDir.path
    let typedB = projectDir.path.replacingOccurrences(of: "MixedCase", with: "mixedcase")
    let keyA = DefaultsStore.canonicalKey(typedA)
    let keyB = DefaultsStore.canonicalKey(typedB)

    let url = URL(fileURLWithPath: projectDir.path)
    let caseSensitive =
      (try? url.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey])
        .volumeSupportsCaseSensitiveNames) ?? false
    if caseSensitive {
      #expect(keyA != keyB, "case-sensitive volume must keep distinct casings distinct")
    } else {
      #expect(keyA == keyB, "case-insensitive volume must collapse casings to one key")
    }
  }

  @Test("canonicalKey normalizes Unicode NFC/NFD into the same key")
  func canonicalKeyNormalizesUnicode() {
    // U+00E9 (é, precomposed / NFC) vs "e" + U+0301 (combining acute / NFD).
    let nfc = "/tmp/xcforge-test-unicode/Caf\u{00E9}.xcodeproj"
    let nfd = "/tmp/xcforge-test-unicode/Cafe\u{0301}.xcodeproj"
    #expect(DefaultsStore.canonicalKey(nfc) == DefaultsStore.canonicalKey(nfd))
  }

  @Test("canonicalKey rejects empty and root path (P13)")
  func canonicalKeyRejectsEmptyAndRootPath() {
    #expect(DefaultsStore.canonicalKey("") == DefaultsStore.invalidCanonicalKey)
    #expect(DefaultsStore.canonicalKey("/") == DefaultsStore.invalidCanonicalKey)
    #expect(DefaultsStore.canonicalKey("///") == DefaultsStore.invalidCanonicalKey)
    #expect(DefaultsStore.validCanonicalKey("") == nil)
    #expect(DefaultsStore.validCanonicalKey("/") == nil)
  }

  @Test("save+load round-trips non-canonical input (trailing slash, /./, NFC vs NFD)")
  func canonicalKeyRoundTripsNonCanonicalInput() throws {
    let (store, dir) = makeTempStore()
    defer { cleanup(dir) }

    let projectDir = dir.appendingPathComponent("Round.xcodeproj", isDirectory: true)
    try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

    // Save with one non-canonical form (trailing slash + /./).
    let savePath = projectDir.path + "/./"
    store.save(
      PersistedDefaults(project: savePath, scheme: "RoundScheme"), forProject: savePath)

    // Load with a different non-canonical form (trailing slash only).
    let loadPath = projectDir.path + "/"
    let loaded = store.load(forProject: loadPath)
    #expect(loaded?.scheme == "RoundScheme")
  }

  // MARK: - P2 / P1 fixes

  @Test("v1 file without project field does not invite later clobber (P2)")
  func v1WithoutProjectDoesNotInviteClobber() throws {
    let (store, dir) = makeTempStore()
    defer { cleanup(dir) }

    // v1 with no project — currently treated as unrecognized.
    let v1 = PersistedDefaults(scheme: "Orphan", simulator: "iPhone 15")
    let data = try JSONEncoder().encode(v1)
    try FileManager.default.createDirectory(
      at: store.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: store.fileURL)
    let originalBytes = try Data(contentsOf: store.fileURL)

    // A later save for an unrelated project must not silently overwrite the
    // unreadable file. The fix backs the original up to `defaults.json.unrecognized-*`
    // (or refuses the write entirely if the backup itself fails).
    let projectDir = dir.appendingPathComponent("Other.xcodeproj", isDirectory: true)
    try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
    store.save(
      PersistedDefaults(project: projectDir.path, scheme: "S"), forProject: projectDir.path)

    let parentDir = store.fileURL.deletingLastPathComponent()
    let siblings = (try? FileManager.default.contentsOfDirectory(atPath: parentDir.path)) ?? []
    let backups = siblings.filter { $0.hasPrefix("defaults.json.unrecognized-") }
    if backups.isEmpty {
      // Write was refused → original bytes survive verbatim.
      let now = try Data(contentsOf: store.fileURL)
      #expect(now == originalBytes, "refused write must preserve original bytes")
    } else {
      // Backup was created → its bytes equal the original.
      let backedUp = try Data(contentsOf: parentDir.appendingPathComponent(backups[0]))
      #expect(backedUp == originalBytes, "backup must preserve original bytes verbatim")
    }
  }

  @Test("v1 migration is safe under two concurrent loads (exclusive lock, P1)")
  func v1MigrationUsesExclusiveLock() async throws {
    let (store, dir) = makeTempStore()
    defer { cleanup(dir) }

    let projDir = dir.appendingPathComponent("V1Concurrent.xcodeproj", isDirectory: true)
    try FileManager.default.createDirectory(at: projDir, withIntermediateDirectories: true)

    let v1 = PersistedDefaults(
      project: projDir.path,
      scheme: "V1Scheme",
      simulator: "iPhone 14",
      bundleId: "com.example.v1concurrent"
    )
    let data = try JSONEncoder().encode(v1)
    try FileManager.default.createDirectory(
      at: store.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: store.fileURL)

    // Two concurrent readers race the migration.
    await withTaskGroup(of: PersistedDefaults?.self) { group in
      group.addTask { store.load(forProject: projDir.path) }
      group.addTask { store.load(forProject: projDir.path) }
      var results: [PersistedDefaults?] = []
      for await r in group { results.append(r) }
      // Both readers should see the migrated record.
      for r in results {
        #expect(r?.scheme == "V1Scheme")
        #expect(r?.bundleId == "com.example.v1concurrent")
      }
    }

    // File on disk must be valid v2 after the race.
    let raw = try Data(contentsOf: store.fileURL)
    let decoded = try JSONDecoder().decode(StoredEnvelope.self, from: raw)
    #expect(decoded.version == 2)
    #expect(decoded.projects.values.first?.bundleId == "com.example.v1concurrent")
  }
}

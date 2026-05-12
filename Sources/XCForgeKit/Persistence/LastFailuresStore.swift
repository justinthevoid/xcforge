import Foundation

/// Persists the failing test IDs from the most recent run so
/// `xcforge test rerun-failed` can replay them. Stored at
/// `<repoRoot>/.xcforge/last-failures.json`. Writes are best-effort: callers
/// must not surface a write failure to the user — the test result is what
/// matters.
public enum LastFailuresStore {
  public static let fileName = "last-failures.json"
  public static let directoryName = ".xcforge"

  public struct Payload: Codable, Sendable, Equatable {
    public let failures: [String]
    public let scheme: String?
    public let simulator: String?
    public let recordedAt: Date

    public init(failures: [String], scheme: String?, simulator: String?, recordedAt: Date = Date()) {
      self.failures = failures
      self.scheme = scheme
      self.simulator = simulator
      self.recordedAt = recordedAt
    }
  }

  public static func path(at repoRoot: String) -> String {
    let dir = (repoRoot as NSString).appendingPathComponent(directoryName)
    return (dir as NSString).appendingPathComponent(fileName)
  }

  /// Atomically writes the payload via temp + rename. Returns `true` on
  /// success, `false` on any failure (callers should ignore the return value
  /// unless they want to log a stderr warning in human mode).
  @discardableResult
  public static func write(
    failures: [String],
    scheme: String?,
    simulator: String?,
    at repoRoot: String,
    now: Date = Date()
  ) -> Bool {
    let dir = (repoRoot as NSString).appendingPathComponent(directoryName)
    do {
      try FileManager.default.createDirectory(
        atPath: dir, withIntermediateDirectories: true, attributes: nil)
    } catch {
      return false
    }

    let target = URL(fileURLWithPath: path(at: repoRoot))
    let tmp = URL(fileURLWithPath: target.path + ".tmp")
    let payload = Payload(
      failures: failures, scheme: scheme, simulator: simulator, recordedAt: now)

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    do {
      let data = try encoder.encode(payload)
      try data.write(to: tmp, options: .atomic)
    } catch {
      return false
    }

    do {
      if FileManager.default.fileExists(atPath: target.path) {
        try FileManager.default.removeItem(at: target)
      }
      try FileManager.default.moveItem(at: tmp, to: target)
      return true
    } catch {
      try? FileManager.default.removeItem(at: tmp)
      return false
    }
  }

  public static func read(at repoRoot: String) -> Payload? {
    let p = path(at: repoRoot)
    guard FileManager.default.fileExists(atPath: p) else { return nil }
    do {
      let data = try Data(contentsOf: URL(fileURLWithPath: p))
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      return try decoder.decode(Payload.self, from: data)
    } catch {
      return nil
    }
  }

  /// Removes the file when present. No-op when absent. Errors are swallowed
  /// since green-run cleanup must never break the surrounding command.
  public static func clear(at repoRoot: String) {
    let p = path(at: repoRoot)
    guard FileManager.default.fileExists(atPath: p) else { return }
    try? FileManager.default.removeItem(atPath: p)
  }
}

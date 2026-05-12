import Foundation

/// Tolerant loader for `<repoRoot>/.xcforge/known-failures.yaml`.
///
/// File format (list of objects with three fields):
///
///     - id: SuiteName/testCase
///       reason: flaky on CI
///       first_seen: 2026-05-01
///     - id: AnotherSuite/anotherTest
///       reason: pending fix
///       first_seen: 2026-05-02
///
/// Missing file, malformed YAML, or unknown fields never throw — the loader
/// returns whatever it could parse plus a `warning` string for human-mode
/// emission. Agent mode discards the warning.
public enum KnownFailuresStore {
  public static let fileName = "known-failures.yaml"
  public static let directoryName = ".xcforge"

  public struct LoadResult: Sendable, Equatable {
    public let ids: Set<String>
    public let warning: String?
    public init(ids: Set<String>, warning: String?) {
      self.ids = ids
      self.warning = warning
    }
  }

  /// Locate and parse the registry. Returns an empty result when the file is
  /// absent so callers can treat `--gate` as a no-op without branching.
  public static func load(repoRoot: String) -> LoadResult {
    let path =
      ((repoRoot as NSString).appendingPathComponent(directoryName) as NSString)
      .appendingPathComponent(fileName)
    guard FileManager.default.fileExists(atPath: path) else {
      return LoadResult(ids: [], warning: nil)
    }
    let contents: String
    do {
      contents = try String(contentsOfFile: path, encoding: .utf8)
    } catch {
      return LoadResult(
        ids: [],
        warning: "could not read \(path): \(error.localizedDescription)"
      )
    }
    return parse(contents)
  }

  /// Pure parser exposed for tests. Accepts the list-of-objects shape and
  /// silently skips entries missing `id`. Lines outside that shape produce a
  /// parse warning but never abort.
  public static func parse(_ contents: String) -> LoadResult {
    let normalized =
      contents
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
    var ids: Set<String> = []
    var currentID: String?
    var sawAnyItem = false
    var malformedItemCount = 0

    func commit() {
      if let id = currentID, !id.isEmpty {
        ids.insert(id)
      } else if sawAnyItem {
        malformedItemCount += 1
      }
      currentID = nil
    }

    for rawLine in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
      let line = String(rawLine)
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

      if trimmed.hasPrefix("- ") {
        commit()
        sawAnyItem = true
        let rest = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        if let (key, value) = splitKV(rest), key == "id" {
          currentID = unquote(value)
        }
        continue
      }

      guard let (key, value) = splitKV(trimmed) else { continue }
      if key == "id" {
        currentID = unquote(value)
      }
    }
    commit()

    let warning: String?
    if !sawAnyItem && !normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      warning = "known-failures.yaml: no list entries found (expected '- id: ...')"
    } else if malformedItemCount > 0 {
      warning = "known-failures.yaml: skipped \(malformedItemCount) item(s) missing 'id'"
    } else {
      warning = nil
    }
    return LoadResult(ids: ids, warning: warning)
  }

  private static func splitKV(_ s: String) -> (String, String)? {
    guard let colon = s.firstIndex(of: ":") else { return nil }
    let key = s[s.startIndex..<colon].trimmingCharacters(in: .whitespaces)
    let value = s[s.index(after: colon)...].trimmingCharacters(in: .whitespaces)
    if key.isEmpty { return nil }
    return (key, value)
  }

  private static func unquote(_ s: String) -> String {
    var out = s
    if (out.hasPrefix("\"") && out.hasSuffix("\"") && out.count >= 2)
      || (out.hasPrefix("'") && out.hasSuffix("'") && out.count >= 2)
    {
      out.removeFirst()
      out.removeLast()
    }
    return out
  }
}

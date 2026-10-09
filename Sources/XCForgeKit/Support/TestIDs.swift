import Foundation

/// One test ID format everywhere: `Target/Suite/test()` for Swift Testing,
/// `Target/Class/testMethod` for XCTest, the form `list_tests` prints and
/// `-only-testing` accepts. Shorter forms (`Suite/test()`, `test()`) are accepted as
/// input and compared with `same(_:_:)`.
public enum TestIDs {
  /// Slash-separated components, ignoring slashes inside `[...]` and `(...)`.
  public static func components(_ id: String) -> [String] {
    var parts: [String] = []
    var current = ""
    var depth = 0
    for ch in id {
      if ch == "[" || ch == "(" { depth += 1 }
      if (ch == "]" || ch == ")") && depth > 0 { depth -= 1 }
      if ch == "/" && depth == 0 {
        parts.append(current)
        current = ""
        continue
      }
      current.append(ch)
    }
    parts.append(current)
    return parts
  }

  /// The full ID for a test the result bundle reports as `identifier` (which lacks the
  /// target) inside the test bundle named `target`.
  public static func canonical(target: String?, identifier: String) -> String {
    let id = collapseDoubleParens(identifier)
    guard let target, !target.isEmpty else { return id }
    if id == target || id.hasPrefix(target + "/") { return id }
    return target + "/" + id
  }

  /// `test()()` back to `test()`: the doubled form is only an `-only-testing` workaround.
  static func collapseDoubleParens(_ id: String) -> String {
    id.hasSuffix("()()") ? String(id.dropLast(2)) : id
  }

  /// Comparison key: doubled parens collapsed and a trailing `()` dropped, so the XCTest
  /// and Swift Testing spellings of a name compare equal.
  static func key(_ id: String) -> String {
    let collapsed = collapseDoubleParens(id.trimmingCharacters(in: .whitespaces))
    return collapsed.hasSuffix("()") ? String(collapsed.dropLast(2)) : collapsed
  }

  /// True when `a` and `b` name the same test, allowing either to leave out leading
  /// components (the target, or outer suites). `testFoo` never matches `testFoo2`.
  public static func same(_ a: String, _ b: String) -> Bool {
    let x = key(a)
    let y = key(b)
    guard !x.isEmpty, !y.isEmpty else { return false }
    return x == y || x.hasSuffix("/" + y) || y.hasSuffix("/" + x)
  }

  /// The argument to pass to `-only-testing` for a target-qualified ID. xcodebuild strips a
  /// trailing `()` from the last component, while Swift Testing names its tests with one,
  /// so a Swift Testing test needs it doubled to be found.
  static func onlyTestingArgument(_ id: String) -> String {
    guard components(id).count >= 3, id.hasSuffix("()"), !id.hasSuffix("()()") else { return id }
    return id + "()"
  }
}

/// A failure message with the source location xcresult put in front of it
/// (`File.swift:42: message`) split out.
public struct FailureMessage: Codable, Sendable, Equatable {
  public let text: String
  public let file: String?
  public let line: Int?
  /// The argument, repetition or device the message came from, when the test ran more than once.
  public let label: String?

  public init(text: String, file: String? = nil, line: Int? = nil, label: String? = nil) {
    self.text = text
    self.file = file
    self.line = line
    self.label = label
  }

  /// Split `File.swift:42: message` into its parts. Text without a location is kept whole.
  public static func parse(_ raw: String, label: String? = nil) -> FailureMessage {
    let pattern = #"^([^\s:][^:\n]*\.(?:swift|m|mm|c|cc|cpp|h|hpp)):(\d+):\s?(.*)$"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
      let match = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
      let fileRange = Range(match.range(at: 1), in: raw),
      let lineRange = Range(match.range(at: 2), in: raw),
      let textRange = Range(match.range(at: 3), in: raw)
    else {
      return FailureMessage(text: raw, label: label)
    }
    return FailureMessage(
      text: String(raw[textRange]), file: String(raw[fileRange]), line: Int(raw[lineRange]), label: label)
  }

  /// `[label] File.swift:42: text`, as a person reads it.
  public var display: String {
    var out = ""
    if let label { out += "[\(label)] " }
    if let file { out += "\(file):\(line ?? 0): " }
    return out + text
  }
}

/// Shared text rendering of failure lists: identical messages grouped, the list capped
/// with a count of what was left out, every ID in its full form.
public enum TestFailureText {
  public static let defaultLimit = 20

  public static func lines(
    _ failures: [TestTools.TestFailureObservation], limit: Int = defaultLimit, indent: String = "  "
  ) -> [String] {
    // Group failures whose whole message is identical (a shared setUp failing, say).
    var groups: [(ids: [String], failure: TestTools.TestFailureObservation)] = []
    var indexByMessage: [String: Int] = [:]
    for failure in failures {
      if !failure.message.isEmpty, let i = indexByMessage[failure.message] {
        groups[i].ids.append(failure.testIdentifier)
      } else {
        indexByMessage[failure.message] = groups.count
        groups.append((ids: [failure.testIdentifier], failure: failure))
      }
    }

    var out: [String] = []
    var shownTests = 0
    for group in groups.prefix(limit) {
      shownTests += group.ids.count
      let names =
        group.ids.count == 1
        ? group.ids[0]
        : group.ids.prefix(5).joined(separator: ", ")
          + (group.ids.count > 5 ? " and \(group.ids.count - 5) more" : "")
          + " (\(group.ids.count) tests, same message)"
      out.append("\(indent)FAIL: \(names)")
      let messages = group.failure.messages ?? []
      if messages.isEmpty {
        if !group.failure.message.isEmpty {
          out.append(indent + "  " + group.failure.message.replacingOccurrences(of: "\n", with: "\n\(indent)  "))
        }
      } else {
        for message in messages.prefix(5) {
          out.append(indent + "  " + message.display.replacingOccurrences(of: "\n", with: "\n\(indent)  "))
        }
        if messages.count > 5 { out.append("\(indent)  +\(messages.count - 5) more messages") }
      }
      for path in group.failure.attachments ?? [] {
        out.append("\(indent)  Attachment: \(path)")
      }
      if let console = group.failure.console, !console.isEmpty {
        out.append("\(indent)  Console (last lines):")
        out.append(indent + "    " + console.replacingOccurrences(of: "\n", with: "\n\(indent)    "))
      }
    }
    let hidden = failures.count - shownTests
    if hidden > 0 {
      out.append("\(indent)+\(hidden) more failures (test_failures or `xcforge test failures` lists them all)")
    }
    return out
  }
}

extension TestFailureText {
  /// Compile errors from a failed test build, one per line with file and line, capped.
  public static func buildErrorLines(
    _ failures: [TestTools.TestFailureObservation], limit: Int = defaultLimit, indent: String = "  "
  ) -> [String] {
    let messages = failures.flatMap { failure in
      failure.messages ?? [FailureMessage(text: failure.message)]
    }
    var out = messages.prefix(limit).map {
      indent + $0.display.replacingOccurrences(of: "\n", with: "\n\(indent)  ")
    }
    if messages.count > limit {
      out.append("\(indent)+\(messages.count - limit) more errors")
    }
    return out
  }
}

/// Whether any source under a folder changed after a given time, so a rerun can skip
/// build-for-testing when nothing was edited.
enum SourceChanges {
  static let skippedDirectories: Set<String> = [
    ".git", ".build", ".swiftpm", ".xcforge", "DerivedData", "build", "Build", "node_modules", "Pods",
    "Carthage", "xcuserdata",
  ]

  /// More files than this and the walk gives up and reports a change.
  static let fileCap = 100_000

  static func anyModified(under root: String, after date: Date) -> Bool {
    let url = URL(fileURLWithPath: root)
    guard
      let enumerator = FileManager.default.enumerator(
        at: url, includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
        options: [.skipsHiddenFiles])
    else { return true }
    var count = 0
    for case let file as URL in enumerator {
      let name = file.lastPathComponent
      if skippedDirectories.contains(name) || name.hasSuffix(".xcresult") {
        enumerator.skipDescendants()
        continue
      }
      count += 1
      if count > fileCap { return true }
      guard let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey]),
        values.isDirectory != true,
        let modified = values.contentModificationDate
      else { continue }
      if modified > date { return true }
    }
    return false
  }
}

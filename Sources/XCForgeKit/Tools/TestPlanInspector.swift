import Foundation

// MARK: - Codable models for .xctestplan (version 1 JSON format)

public struct XCTestPlan: Codable {
  var version: Int
  var configurations: [TestPlanConfig]
  var defaultOptions: TestPlanOptions
  var testTargets: [TestPlanTarget]

  // Xcode omits empty sections, so every key is optional on disk.
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
    configurations = try c.decodeIfPresent([TestPlanConfig].self, forKey: .configurations) ?? []
    defaultOptions =
      try c.decodeIfPresent(TestPlanOptions.self, forKey: .defaultOptions)
      ?? TestPlanOptions(codeCoverage: nil, threadSanitizerEnabled: nil, addressSanitizerEnabled: nil)
    testTargets = try c.decodeIfPresent([TestPlanTarget].self, forKey: .testTargets) ?? []
  }
}

public struct TestPlanConfig: Codable {
  public var name: String
  public var options: TestPlanOptions

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    name = try c.decode(String.self, forKey: .name)
    options =
      try c.decodeIfPresent(TestPlanOptions.self, forKey: .options)
      ?? TestPlanOptions(codeCoverage: nil, threadSanitizerEnabled: nil, addressSanitizerEnabled: nil)
  }
}

public struct TestPlanOptions: Codable {
  public var codeCoverage: Bool?
  public var threadSanitizerEnabled: Bool?
  public var addressSanitizerEnabled: Bool?
}

public struct TestPlanTarget: Codable {
  public var target: TestTargetRef
  public var parallelizable: Bool?
  public var enabled: Bool?
  public var skippedTests: [SkippedTest]?
  public var selectedTests: [SkippedTest]?
}

public struct TestTargetRef: Codable {
  public var name: String
  public var containerPath: String?
  public var identifier: String?
}

/// A test reference in a plan. Xcode writes these as plain strings (`"Class/test()"`);
/// older tools wrote `{ "identifier": ... }`. Both decode.
public struct SkippedTest: Codable {
  public var identifier: String

  public init(from decoder: Decoder) throws {
    if let single = try? decoder.singleValueContainer(), let value = try? single.decode(String.self) {
      identifier = value
      return
    }
    let c = try decoder.container(keyedBy: CodingKeys.self)
    identifier = try c.decode(String.self, forKey: .identifier)
  }
}

// MARK: - Inspector

public enum TestPlanInspector {
  public enum InspectError: Error {
    case notFound(name: String, searched: [String])
  }

  public static func inspectTestPlan(name: String, project: String, env: Environment) async throws
    -> String
  {
    let located = locate(name: name, project: project)
    if let path = located.path {
      return try parse(at: path)
    }
    throw InspectError.notFound(name: name, searched: located.searched)
  }

  /// Find the `.xctestplan` named `name` for `project`, and the places looked in.
  static func locate(name: String, project: String) -> (path: String?, searched: [String]) {
    let normalized = name.hasSuffix(".xctestplan") ? name : "\(name).xctestplan"
    let baseName = (normalized as NSString).lastPathComponent

    let projectDir: String
    if project.hasSuffix(".xcodeproj") || project.hasSuffix(".xcworkspace") {
      projectDir = (project as NSString).deletingLastPathComponent
    } else {
      projectDir = project
    }

    var searchedPaths: [String] = []

    // Shared plans live inside the .xcodeproj/.xcworkspace bundle; loose plans sit beside it.
    var planDirs = ["\(projectDir)/xcshareddata/xctestplans", projectDir]
    if project.hasSuffix(".xcodeproj") || project.hasSuffix(".xcworkspace") {
      planDirs.insert("\(project)/xcshareddata/xctestplans", at: 0)
    }
    for planDir in planDirs {
      searchedPaths.append("\(planDir)/\(baseName)")
      if let entries = try? FileManager.default.contentsOfDirectory(atPath: planDir),
        let match = entries.first(where: { $0.lowercased() == baseName.lowercased() })
      {
        return ("\(planDir)/\(match)", searchedPaths)
      }
    }

    // Recursive find under projectDir (case-insensitive)
    if let found = findTestPlan(named: baseName, under: projectDir) {
      return (found, searchedPaths)
    }
    searchedPaths.append("\(projectDir)/**/*.xctestplan (recursive, case-insensitive)")
    return (nil, searchedPaths)
  }

  /// Names of the test targets a plan runs (disabled targets left out), or nil when the plan
  /// can't be found or read.
  static func testTargetNames(plan: String, project: String) -> [String]? {
    guard let path = locate(name: plan, project: project).path else { return nil }
    return testTargetNames(atPath: path)
  }

  static func testTargetNames(atPath path: String) -> [String]? {
    guard let data = FileManager.default.contents(atPath: path),
      let decoded = try? JSONDecoder().decode(XCTestPlan.self, from: data)
    else { return nil }
    return decoded.testTargets.filter { $0.enabled != false }.map(\.target.name)
  }

  // MARK: - Private

  private static func findTestPlan(named fileName: String, under directory: String) -> String? {
    let lowerName = fileName.lowercased()
    guard
      let enumerator = FileManager.default.enumerator(
        at: URL(fileURLWithPath: directory),
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
      )
    else { return nil }

    for case let url as URL in enumerator {
      if url.lastPathComponent.lowercased() == lowerName {
        return url.path
      }
    }
    return nil
  }

  private static func parse(at path: String) throws -> String {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let plan = try JSONDecoder().decode(XCTestPlan.self, from: data)
    let raw = (try? JSONSerialization.jsonObject(with: data)) ?? [:]
    return format(plan, path: path, tagSettings: tagSettings(in: raw))
  }

  /// Every tag-related setting in the plan, as `path: value` lines. Swift Testing tag
  /// filters are stored under keys containing "tag"; the exact keys vary by Xcode version,
  /// so they are reported verbatim rather than modelled.
  static func tagSettings(in node: Any, path: String = "") -> [String] {
    var found: [String] = []
    if let dict = node as? [String: Any] {
      for key in dict.keys.sorted() {
        let value = dict[key] as Any
        let childPath = path.isEmpty ? key : "\(path).\(key)"
        if key.lowercased().contains("tag") {
          found.append("\(childPath): \(compactJSON(value))")
        } else {
          found += tagSettings(in: value, path: childPath)
        }
      }
    } else if let array = node as? [Any] {
      for (i, item) in array.enumerated() {
        found += tagSettings(in: item, path: "\(path)[\(i)]")
      }
    }
    return found
  }

  private static func compactJSON(_ value: Any) -> String {
    if JSONSerialization.isValidJSONObject(value),
      let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
      let text = String(data: data, encoding: .utf8)
    {
      return text
    }
    return "\(value)"
  }

  /// True when a tag setting lists more than one tag, which is when match-all versus
  /// match-any changes which tests run.
  static func hasMultiTagFilter(_ settings: [String]) -> Bool {
    settings.contains { line in
      guard let separator = line.range(of: ": ") else { return false }
      // An array literal with a comma directly inside it: two or more tags.
      let value = line[separator.upperBound...]
      return value.range(of: #"\[[^\[\]]*,[^\[\]]*\]"#, options: .regularExpression) != nil
    }
  }

  private static func format(_ plan: XCTestPlan, path: String, tagSettings: [String] = []) -> String {
    var lines: [String] = []
    lines.append("Test Plan: \(URL(fileURLWithPath: path).lastPathComponent)")
    lines.append("Version: \(plan.version)")
    lines.append("")

    lines.append("Default Options:")
    lines.append(formatOptions(plan.defaultOptions, indent: "  "))

    lines.append("")
    lines.append("Configurations (\(plan.configurations.count)):")
    for config in plan.configurations {
      lines.append("  \(config.name)")
      let opts = formatOptions(config.options, indent: "    ")
      if !opts.isEmpty { lines.append(opts) }
    }

    lines.append("")
    lines.append("Test Targets (\(plan.testTargets.count)):")
    for target in plan.testTargets {
      let skipped = target.skippedTests?.count ?? 0
      var targetLine = "  \(target.target.name)"
      if target.enabled == false { targetLine += " (disabled)" }
      if let parallel = target.parallelizable { targetLine += " (parallelizable: \(parallel))" }
      if skipped > 0 { targetLine += " [\(skipped) skipped]" }
      if let selected = target.selectedTests, !selected.isEmpty {
        targetLine += " [only \(selected.count) selected]"
      }
      lines.append(targetLine)
      for test in (target.skippedTests ?? []).prefix(10) {
        lines.append("    skip: \(test.identifier)")
      }
      if skipped > 10 { lines.append("    ... \(skipped - 10) more skipped") }
    }

    if !tagSettings.isEmpty {
      lines.append("")
      lines.append("Tag filters:")
      for setting in tagSettings { lines.append("  \(setting)") }
      if hasMultiTagFilter(tagSettings) {
        lines.append(
          "  Warning: with several included tags, a plan set to match all runs only tests that carry "
            + "every one of them. Compare `xcforge test list --testplan <plan>` with the scheme's count.")
      }
    }

    lines.append("")
    lines.append("Run `xcforge test list --testplan <plan>` to see exactly which tests this plan runs.")

    return lines.joined(separator: "\n")
  }

  private static func formatOptions(_ options: TestPlanOptions, indent: String) -> String {
    var parts: [String] = []
    if let v = options.codeCoverage { parts.append("codeCoverage: \(v)") }
    if let v = options.threadSanitizerEnabled { parts.append("threadSanitizer: \(v)") }
    if let v = options.addressSanitizerEnabled { parts.append("addressSanitizer: \(v)") }
    guard !parts.isEmpty else { return "\(indent)(no options set)" }
    return parts.map { "\(indent)\($0)" }.joined(separator: "\n")
  }
}

extension TestPlanInspector.InspectError: CustomStringConvertible, LocalizedError {
  public var errorDescription: String? { description }

  public var description: String {
    switch self {
    case .notFound(let name, let searched):
      let paths = searched.map { "  \($0)" }.joined(separator: "\n")
      return "Plan \"\(name)\" not found. Searched:\n\(paths)"
    }
  }
}

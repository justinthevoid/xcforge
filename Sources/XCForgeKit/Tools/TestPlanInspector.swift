import Foundation

// MARK: - Codable models for .xctestplan (version 1 JSON format)

public struct XCTestPlan: Codable {
  var version: Int
  var configurations: [TestPlanConfig]
  var defaultOptions: TestPlanOptions
  var testTargets: [TestPlanTarget]
}

public struct TestPlanConfig: Codable {
  public var name: String
  public var options: TestPlanOptions
}

public struct TestPlanOptions: Codable {
  public var codeCoverage: Bool?
  public var threadSanitizerEnabled: Bool?
  public var addressSanitizerEnabled: Bool?
}

public struct TestPlanTarget: Codable {
  public var target: TestTargetRef
  public var parallelizable: Bool?
  public var skippedTests: [SkippedTest]?
}

public struct TestTargetRef: Codable {
  public var name: String
  public var containerPath: String
  public var identifier: String
}

public struct SkippedTest: Codable {
  public var identifier: String
}

// MARK: - Inspector

public enum TestPlanInspector {
  public enum InspectError: Error {
    case notFound(name: String, searched: [String])
  }

  public static func inspectTestPlan(name: String, project: String, env: Environment) async throws
    -> String
  {
    let normalized = name.hasSuffix(".xctestplan") ? name : "\(name).xctestplan"
    let baseName = normalized

    let projectDir: String
    if project.hasSuffix(".xcodeproj") || project.hasSuffix(".xcworkspace") {
      projectDir = (project as NSString).deletingLastPathComponent
    } else {
      projectDir = project
    }

    var searchedPaths: [String] = []

    let planDir = "\(projectDir)/xcshareddata/xctestplans"
    searchedPaths.append("\(planDir)/\(baseName)")

    if let entries = try? FileManager.default.contentsOfDirectory(atPath: planDir),
      let match = entries.first(where: { $0.lowercased() == baseName.lowercased() })
    {
      return try parse(at: "\(planDir)/\(match)")
    }

    // Recursive find under projectDir (case-insensitive)
    let found = findTestPlan(named: baseName, under: projectDir)
    if let found {
      return try parse(at: found)
    }
    searchedPaths.append("\(projectDir)/**/*.xctestplan (recursive, case-insensitive)")

    throw InspectError.notFound(name: name, searched: searchedPaths)
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
    return format(plan, path: path)
  }

  private static func format(_ plan: XCTestPlan, path: String) -> String {
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
      if let parallel = target.parallelizable { targetLine += " (parallelizable: \(parallel))" }
      if skipped > 0 { targetLine += " [\(skipped) skipped]" }
      lines.append(targetLine)
    }

    lines.append("")
    lines.append(
      "Note: -enumerate-tests only discovers XCTest methods; Swift Testing @Test suites are not enumerated."
    )

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

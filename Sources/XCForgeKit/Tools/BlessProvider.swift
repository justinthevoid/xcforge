import Foundation
import MCP

public enum BlessTools: ToolProvider {
  public static let tools: [Tool] = [
    Tool(
      name: "bless",
      description: """
        Codify the baseline-write → test → diff → commit cycle in one call. \
        Saves a visual baseline, runs the specified tests, compares the result against \
        the saved baseline, and suggests a git commit message.
        """,
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "baseline": .object([
            "type": .string("string"),
            "description": .string("Name to use for the visual baseline."),
          ]),
          "tests": .object([
            "type": .string("string"),
            "description": .string("Test filter, e.g. 'MyTarget/MyTests'. Passed to build_and_test."),
          ]),
          "project": .object([
            "type": .string("string"),
            "description": .string("Path to .xcodeproj or .xcworkspace. Auto-detected if omitted."),
          ]),
          "scheme": .object([
            "type": .string("string"),
            "description": .string("Xcode scheme name. Auto-detected if omitted."),
          ]),
          "simulator": .object([
            "type": .string("string"),
            "description": .string("Simulator name or UDID. Auto-detected if omitted."),
          ]),
        ]),
        "required": .array([.string("baseline"), .string("tests")]),
      ])
    )
  ]

  public static func dispatch(_ name: String, _ args: [String: Value]?, env: Environment) async
    -> CallTool.Result?
  {
    guard name == "bless" else { return nil }
    return await blessImpl(args, env: env)
  }

  // MARK: - Input

  struct BlessInput: Codable {
    let baseline: String
    let tests: String
    let project: String?
    let scheme: String?
    let simulator: String?
  }

  // MARK: - Implementation

  public static func blessImpl(_ args: [String: Value]?, env: Environment) async -> CallTool.Result {
    switch ToolInput.decode(BlessInput.self, from: args) {
    case .failure(let err): return err
    case .success(let input):
      return await runBless(input, env: env)
    }
  }

  private static func runBless(_ input: BlessInput, env: Environment) async -> CallTool.Result {
    var lines: [String] = []

    // Step 1: Save visual baseline
    let baselineInput = VisualTools.SaveBaselineInput(
      name: input.baseline,
      simulator: input.simulator,
      baseline_dir: nil
    )
    let saveResult = await VisualTools.saveVisualBaselineImpl(baselineInput, env: env)
    let saveText = extractText(saveResult)
    lines.append("Baseline: \(saveText)")
    let baselinePath = extractBaselinePath(from: saveText)

    // Step 2: Run tests
    let testResult: TestTools.BuildAndTestResult
    do {
      testResult = try await TestTools.executeBuildAndTest(
        project: input.project,
        scheme: input.scheme,
        simulator: input.simulator,
        filter: input.tests,
        env: env
      )
    } catch {
      lines.append("Test run error: \(error)")
      return .fail(lines.joined(separator: "\n"))
    }

    let testPassed = testResult.buildSucceeded && (testResult.testResult?.succeeded ?? false)
    let testStatus = testPassed ? "PASS" : "FAIL"
    lines.append(
      "Tests [\(testStatus)]: \(input.tests) — \(testResult.testResult?.totalTestCount ?? 0) tests"
    )

    // Step 3: Compare visual (if baseline was written)
    if let path = baselinePath {
      let compareInput = VisualTools.CompareInput(
        name: path,
        simulator: input.simulator,
        threshold: nil,
        baseline_dir: nil
      )
      let compareResult = await VisualTools.compareVisualImpl(compareInput, env: env)
      lines.append("Visual diff: \(extractText(compareResult))")
    } else {
      lines.append("Visual diff: skipped (baseline path not captured from save output)")
    }

    // Step 4: Suggest commit message
    let slug = commitSlug(from: input.tests)
    lines.append("")
    lines.append("Suggested commit:")
    lines.append("  git commit -m \"[bless] \(slug)\"")

    return testPassed ? .ok(lines.joined(separator: "\n")) : .fail(lines.joined(separator: "\n"))
  }

  // MARK: - Helpers

  private static func extractText(_ result: CallTool.Result) -> String {
    guard let first = result.content.first else { return "" }
    if case .text(let text, _, _) = first { return text }
    return ""
  }

  private static func extractBaselinePath(from text: String) -> String? {
    for line in text.split(separator: "\n") {
      let s = String(line)
      if s.hasPrefix("Baseline saved: ") {
        return String(s.dropFirst("Baseline saved: ".count))
          .trimmingCharacters(in: .whitespaces)
      }
    }
    return nil
  }

  static func commitSlug(from filter: String) -> String {
    let slug =
      filter
      .lowercased()
      .replacingOccurrences(of: "/", with: "-")
      .replacingOccurrences(of: " ", with: "-")
    let trimmed = String(slug.prefix(40))
    return trimmed.trimmingCharacters(in: .init(charactersIn: "-"))
  }
}

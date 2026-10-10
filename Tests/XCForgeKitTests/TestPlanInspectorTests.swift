import Foundation
import Testing

@testable import XCForgeKit

private let fixtureJSON = """
  {
    "version": 1,
    "configurations": [
      {
        "name": "Debug Config",
        "options": {
          "codeCoverage": true
        }
      },
      {
        "name": "Sanitizer Config",
        "options": {
          "threadSanitizerEnabled": true,
          "addressSanitizerEnabled": false
        }
      }
    ],
    "defaultOptions": {
      "codeCoverage": false
    },
    "testTargets": [
      {
        "target": {
          "name": "MyAppTests",
          "containerPath": "container:MyApp.xcodeproj",
          "identifier": "MyAppTests"
        },
        "parallelizable": true,
        "skippedTests": [
          { "identifier": "MyAppTests/SlowTests/testSlow" }
        ]
      },
      {
        "target": {
          "name": "MyAppUITests",
          "containerPath": "container:MyApp.xcodeproj",
          "identifier": "MyAppUITests"
        }
      }
    ]
  }
  """

@Suite("TestPlanInspector")
struct TestPlanInspectorTests {
  @Test("successful parse returns configuration names")
  func parseConfigurationNames() throws {
    let data = try #require(fixtureJSON.data(using: .utf8))
    let plan = try JSONDecoder().decode(XCTestPlan.self, from: data)
    #expect(plan.version == 1)
    #expect(plan.configurations.count == 2)
    #expect(plan.configurations[0].name == "Debug Config")
    #expect(plan.configurations[1].name == "Sanitizer Config")
  }

  @Test("successful parse returns test targets")
  func parseTestTargets() throws {
    let data = try #require(fixtureJSON.data(using: .utf8))
    let plan = try JSONDecoder().decode(XCTestPlan.self, from: data)
    #expect(plan.testTargets.count == 2)
    #expect(plan.testTargets[0].target.name == "MyAppTests")
    #expect(plan.testTargets[0].skippedTests?.count == 1)
    #expect(plan.testTargets[1].target.name == "MyAppUITests")
    #expect(plan.testTargets[1].skippedTests == nil)
  }

  @Test("successful parse reflects defaultOptions")
  func parseDefaultOptions() throws {
    let data = try #require(fixtureJSON.data(using: .utf8))
    let plan = try JSONDecoder().decode(XCTestPlan.self, from: data)
    #expect(plan.defaultOptions.codeCoverage == false)
  }

  @Test("missing file error surfaces searched paths")
  func missingFileSurfacesPaths() async {
    let env = Environment.live
    do {
      _ = try await TestPlanInspector.inspectTestPlan(
        name: "NonExistentPlanXYZ",
        project: "/tmp",
        env: env
      )
      Issue.record("Expected error to be thrown")
    } catch let error as TestPlanInspector.InspectError {
      let desc = error.description
      #expect(desc.contains("NonExistentPlanXYZ"))
      #expect(desc.contains("not found"))
    } catch {
      Issue.record("Unexpected error type: \(error)")
    }
  }

  @Test("inspectTestPlan from temp file returns formatted summary")
  func formatSummary() async throws {
    let tmpDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("xcforge-testplan-\(UUID().uuidString)")
    let sharedDir = tmpDir.appendingPathComponent("xcshareddata/xctestplans", isDirectory: true)
    try FileManager.default.createDirectory(at: sharedDir, withIntermediateDirectories: true)
    let planFile = sharedDir.appendingPathComponent("MyPlan.xctestplan")
    try fixtureJSON.write(to: planFile, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    let env = Environment.live
    let summary = try await TestPlanInspector.inspectTestPlan(
      name: "MyPlan",
      project: tmpDir.path,
      env: env
    )
    #expect(summary.contains("Debug Config"))
    #expect(summary.contains("Sanitizer Config"))
    #expect(summary.contains("MyAppTests"))
    #expect(summary.contains("1 skipped"))
    #expect(summary.contains("Metadata only: no build"))
    #expect(summary.contains("can compile the app"))
    #expect(!summary.contains("Run `xcforge test list"))
  }

  @Test("Xcode skipped targets and legacy disabled targets are excluded from discovery")
  func excludesSkippedTargets() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("xcforge-targets-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("ci.xctestplan")
    try #"""
    {"testTargets":[
      {"target":{"name":"ActiveTests"}},
      {"target":{"name":"SkippedUITests"},"skipped":true},
      {"target":{"name":"LegacyDisabledTests"},"enabled":false},
      {"target":{"name":"ExplicitActiveTests"},"skipped":false}
    ]}
    """#.write(to: file, atomically: true, encoding: .utf8)
    #expect(TestPlanInspector.testTargetNames(atPath: file.path) == ["ActiveTests", "ExplicitActiveTests"])
  }

  @Test("metadata inspection reports execution budgets and declared selections")
  func reportsTimeoutsAndSelectionsWithoutEnumeration() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("xcforge-budgets-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("ci.xctestplan")
    try #"""
    {
      "configurations":[{"name":"Smoke", "options":{"maximumTestExecutionTimeAllowance":120}}],
      "defaultOptions":{"testTimeoutsEnabled":true,"defaultTestExecutionTimeAllowance":60},
      "testTargets":[
        {"target":{"name":"AppUITests"},"options":{"testExecutionOrdering":"alphabetical"},
         "selectedTests":["CritiqueFlowUITests/testCompletes()"]},
        {"target":{"name":"DisabledTests"},"skipped":true}
      ]
    }
    """#.write(to: file, atomically: true, encoding: .utf8)
    let summary = try await TestPlanInspector.inspectTestPlan(name: "ci", project: directory.path, env: .live)
    #expect(summary.contains("testTimeoutsEnabled: true"))
    #expect(summary.contains("defaultTestExecutionTimeAllowance: 60.0s"))
    #expect(summary.contains("maximumTestExecutionTimeAllowance: 120.0s"))
    #expect(summary.contains("testExecutionOrdering: alphabetical"))
    #expect(summary.contains("select: CritiqueFlowUITests/testCompletes()"))
    #expect(summary.contains("DisabledTests (disabled)"))
    #expect(!summary.contains("Run `xcforge test list"))
  }
}

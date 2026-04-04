import Foundation
import Testing

@testable import XCForgeCLI
@testable import XCForgeKit

@Suite("Workflow Repeatability")
struct WorkflowRepeatabilityTests {

  // MARK: - Shared Helpers

  private static let context = ResolvedWorkflowContext(
    project: "/tmp/App.xcodeproj",
    scheme: "App",
    simulator: "iPhone 16 Pro",
    configuration: "Debug",
    app: AppContext(bundleId: "com.test.app", appPath: "/tmp/App.app")
  )

  private static let failure = WorkflowFailure(
    field: .build,
    classification: .executionFailed,
    message: "Build failed with 1 error"
  )

  private static let statusSummary = DiagnosisStatusSummary(
    source: .build,
    headline: "Build failed",
    detail: "1 error in AppDelegate.swift"
  )

  private static func parseJSON(_ json: String) throws -> [String: Any] {
    let data = Data(json.utf8)
    let obj = try JSONSerialization.jsonObject(with: data)
    return try #require(obj as? [String: Any])
  }

  // MARK: - Factory helpers that produce deterministic instances

  private static func makeStartResult() -> DiagnosisStartResult {
    DiagnosisStartResult(
      status: .inProgress,
      runId: "run-1",
      attemptId: "attempt-1",
      resolvedContext: context,
      failure: nil,
      persistedRunPath: "/tmp/run-1.json"
    )
  }

  private static func makeBuildResult() -> DiagnosisBuildResult {
    DiagnosisBuildResult(
      status: .failed,
      runId: "run-1",
      attemptId: "attempt-1",
      resolvedContext: context,
      summary: nil,
      failure: failure,
      persistedRunPath: "/tmp/run-1.json"
    )
  }

  private static func makeTestResult() -> DiagnosisTestResult {
    DiagnosisTestResult(
      status: .succeeded,
      runId: "run-1",
      attemptId: "attempt-1",
      resolvedContext: context,
      summary: nil,
      failure: nil,
      persistedRunPath: "/tmp/run-1.json"
    )
  }

  private static func makeRuntimeResult() -> DiagnosisRuntimeResult {
    DiagnosisRuntimeResult(
      status: .succeeded,
      runId: "run-1",
      attemptId: "attempt-1",
      resolvedContext: context,
      summary: nil,
      failure: nil,
      persistedRunPath: "/tmp/run-1.json"
    )
  }

  private static func makeStatusResult() -> DiagnosisStatusResult {
    DiagnosisStatusResult(
      phase: .diagnosisBuild,
      status: .inProgress,
      runId: "run-1",
      attemptId: "attempt-1",
      resolvedContext: context,
      summary: statusSummary,
      failure: nil,
      persistedRunPath: "/tmp/run-1.json"
    )
  }

  private static func makeVerifyResult() -> DiagnosisVerifyResult {
    DiagnosisVerifyResult(
      phase: .diagnosisBuild,
      status: .succeeded,
      outcome: .verified,
      runId: "run-1",
      attemptId: "attempt-2",
      sourceAttemptId: "attempt-1",
      resolvedContext: context,
      summary: statusSummary,
      buildSummary: nil,
      testSummary: nil,
      evidence: [],
      failure: nil,
      persistedRunPath: "/tmp/run-1.json"
    )
  }

  private static func makeCompareResult() -> DiagnosisCompareResult {
    DiagnosisCompareResult(
      phase: .diagnosisBuild,
      status: .succeeded,
      outcome: .improved,
      runId: "run-1",
      attemptId: "attempt-2",
      sourceAttemptId: "attempt-1",
      priorAttempt: nil,
      currentAttempt: nil,
      changedEvidence: [],
      unchangedBlockers: [],
      failure: nil,
      persistedRunPath: "/tmp/run-1.json"
    )
  }

  private static func makeFinalResult() -> DiagnosisFinalResult {
    DiagnosisFinalResult(
      phase: .diagnosisBuild,
      status: .succeeded,
      runId: "run-1",
      attemptId: "attempt-2",
      sourceAttemptId: "attempt-1",
      summary: statusSummary,
      currentAttempt: nil,
      sourceAttempt: nil,
      comparison: nil,
      failure: nil,
      persistedRunPath: "/tmp/run-1.json"
    )
  }

  private static func makeEvidenceResult() -> DiagnosisEvidenceResult {
    DiagnosisEvidenceResult(
      phase: .diagnosisBuild,
      status: .succeeded,
      evidenceState: .complete,
      runId: "run-1",
      attemptId: "attempt-1",
      resolvedContext: context,
      buildSummary: nil,
      testSummary: nil,
      runtimeSummary: nil,
      evidence: [],
      failure: nil,
      persistedRunPath: "/tmp/run-1.json"
    )
  }

  private static func makeInspectResult() -> DiagnosisInspectResult {
    DiagnosisInspectResult(
      phase: .diagnosisBuild,
      status: .inProgress,
      runId: "run-1",
      attemptId: "attempt-1",
      resolvedContext: context,
      contextProvenance: nil,
      evidenceCompleteness: .partial,
      failure: nil,
      persistedRunPath: "/tmp/run-1.json"
    )
  }

  // MARK: - 1. Identical construction produces identical JSON

  @Test("DiagnosisStartResult identical construction produces identical JSON")
  func startResultRepeatability() throws {
    let jsonA = try WorkflowJSONRenderer.renderJSON(Self.makeStartResult())
    let jsonB = try WorkflowJSONRenderer.renderJSON(Self.makeStartResult())
    #expect(jsonA == jsonB)
  }

  @Test("DiagnosisBuildResult identical construction produces identical JSON")
  func buildResultRepeatability() throws {
    let jsonA = try WorkflowJSONRenderer.renderJSON(Self.makeBuildResult())
    let jsonB = try WorkflowJSONRenderer.renderJSON(Self.makeBuildResult())
    #expect(jsonA == jsonB)
  }

  @Test("DiagnosisTestResult identical construction produces identical JSON")
  func testResultRepeatability() throws {
    let jsonA = try WorkflowJSONRenderer.renderJSON(Self.makeTestResult())
    let jsonB = try WorkflowJSONRenderer.renderJSON(Self.makeTestResult())
    #expect(jsonA == jsonB)
  }

  @Test("DiagnosisRuntimeResult identical construction produces identical JSON")
  func runtimeResultRepeatability() throws {
    let jsonA = try WorkflowJSONRenderer.renderJSON(Self.makeRuntimeResult())
    let jsonB = try WorkflowJSONRenderer.renderJSON(Self.makeRuntimeResult())
    #expect(jsonA == jsonB)
  }

  @Test("DiagnosisStatusResult identical construction produces identical JSON")
  func statusResultRepeatability() throws {
    let jsonA = try WorkflowJSONRenderer.renderJSON(Self.makeStatusResult())
    let jsonB = try WorkflowJSONRenderer.renderJSON(Self.makeStatusResult())
    #expect(jsonA == jsonB)
  }

  @Test("DiagnosisVerifyResult identical construction produces identical JSON")
  func verifyResultRepeatability() throws {
    let jsonA = try WorkflowJSONRenderer.renderJSON(Self.makeVerifyResult())
    let jsonB = try WorkflowJSONRenderer.renderJSON(Self.makeVerifyResult())
    #expect(jsonA == jsonB)
  }

  @Test("DiagnosisCompareResult identical construction produces identical JSON")
  func compareResultRepeatability() throws {
    let jsonA = try WorkflowJSONRenderer.renderJSON(Self.makeCompareResult())
    let jsonB = try WorkflowJSONRenderer.renderJSON(Self.makeCompareResult())
    #expect(jsonA == jsonB)
  }

  @Test("DiagnosisFinalResult identical construction produces identical JSON")
  func finalResultRepeatability() throws {
    let jsonA = try WorkflowJSONRenderer.renderJSON(Self.makeFinalResult())
    let jsonB = try WorkflowJSONRenderer.renderJSON(Self.makeFinalResult())
    #expect(jsonA == jsonB)
  }

  @Test("DiagnosisEvidenceResult identical construction produces identical JSON")
  func evidenceResultRepeatability() throws {
    let jsonA = try WorkflowJSONRenderer.renderJSON(Self.makeEvidenceResult())
    let jsonB = try WorkflowJSONRenderer.renderJSON(Self.makeEvidenceResult())
    #expect(jsonA == jsonB)
  }

  @Test("DiagnosisInspectResult identical construction produces identical JSON")
  func inspectResultRepeatability() throws {
    let jsonA = try WorkflowJSONRenderer.renderJSON(Self.makeInspectResult())
    let jsonB = try WorkflowJSONRenderer.renderJSON(Self.makeInspectResult())
    #expect(jsonA == jsonB)
  }

  // MARK: - 2. Schema version consistency across all result types

  @Test("All result types embed the current schema version")
  func schemaVersionConsistency() throws {
    let expected = WorkflowRunRecord.currentSchemaVersion

    let startJSON = try Self.parseJSON(WorkflowJSONRenderer.renderJSON(Self.makeStartResult()))
    #expect(startJSON["schemaVersion"] as? String == expected)

    let buildJSON = try Self.parseJSON(WorkflowJSONRenderer.renderJSON(Self.makeBuildResult()))
    #expect(buildJSON["schemaVersion"] as? String == expected)

    let testJSON = try Self.parseJSON(WorkflowJSONRenderer.renderJSON(Self.makeTestResult()))
    #expect(testJSON["schemaVersion"] as? String == expected)

    let runtimeJSON = try Self.parseJSON(WorkflowJSONRenderer.renderJSON(Self.makeRuntimeResult()))
    #expect(runtimeJSON["schemaVersion"] as? String == expected)

    let statusJSON = try Self.parseJSON(WorkflowJSONRenderer.renderJSON(Self.makeStatusResult()))
    #expect(statusJSON["schemaVersion"] as? String == expected)

    let verifyJSON = try Self.parseJSON(WorkflowJSONRenderer.renderJSON(Self.makeVerifyResult()))
    #expect(verifyJSON["schemaVersion"] as? String == expected)

    let compareJSON = try Self.parseJSON(WorkflowJSONRenderer.renderJSON(Self.makeCompareResult()))
    #expect(compareJSON["schemaVersion"] as? String == expected)

    let finalJSON = try Self.parseJSON(WorkflowJSONRenderer.renderJSON(Self.makeFinalResult()))
    #expect(finalJSON["schemaVersion"] as? String == expected)

    let evidenceJSON = try Self.parseJSON(
      WorkflowJSONRenderer.renderJSON(Self.makeEvidenceResult()))
    #expect(evidenceJSON["schemaVersion"] as? String == expected)

    let inspectJSON = try Self.parseJSON(WorkflowJSONRenderer.renderJSON(Self.makeInspectResult()))
    #expect(inspectJSON["schemaVersion"] as? String == expected)
  }

  // MARK: - 3. Status enum string stability

  @Test(
    "WorkflowStatus raw values are stable in JSON output",
    arguments: [
      (WorkflowStatus.inProgress, "in_progress"),
      (WorkflowStatus.succeeded, "succeeded"),
      (WorkflowStatus.partial, "partial"),
      (WorkflowStatus.failed, "failed"),
      (WorkflowStatus.canceled, "canceled"),
      (WorkflowStatus.unsupported, "unsupported"),
    ])
  func statusEnumStringStability(status: WorkflowStatus, expectedRaw: String) throws {
    let result = DiagnosisStartResult(
      status: status,
      runId: "run-status",
      attemptId: "attempt-1",
      resolvedContext: Self.context,
      failure: nil,
      persistedRunPath: nil
    )
    let parsed = try Self.parseJSON(WorkflowJSONRenderer.renderJSON(result))
    #expect(parsed["status"] as? String == expectedRaw)
  }

  // MARK: - 4. Failure classification string stability

  @Test(
    "WorkflowFailureClassification raw values are stable in JSON output",
    arguments: [
      (WorkflowFailureClassification.resolutionFailed, "resolution_failed"),
      (WorkflowFailureClassification.unsupportedContext, "unsupported_context"),
      (WorkflowFailureClassification.notFound, "not_found"),
      (WorkflowFailureClassification.invalidRunState, "invalid_run_state"),
      (WorkflowFailureClassification.executionFailed, "execution_failed"),
    ])
  func failureClassificationStringStability(
    classification: WorkflowFailureClassification,
    expectedRaw: String
  ) throws {
    let result = DiagnosisStartResult(
      status: .failed,
      runId: nil,
      attemptId: nil,
      resolvedContext: nil,
      failure: WorkflowFailure(
        field: .workflow,
        classification: classification,
        message: "test classification"
      ),
      persistedRunPath: nil
    )
    let parsed = try Self.parseJSON(WorkflowJSONRenderer.renderJSON(result))
    let failureDict = try #require(parsed["failure"] as? [String: Any])
    #expect(failureDict["classification"] as? String == expectedRaw)
  }

  // MARK: - 5. WorkflowPhase raw value string stability

  @Test(
    "WorkflowPhase raw values are stable in JSON output",
    arguments: [
      (WorkflowPhase.diagnosisStart, "diagnosis_start"),
      (WorkflowPhase.diagnosisBuild, "diagnosis_build"),
      (WorkflowPhase.diagnosisTest, "diagnosis_test"),
      (WorkflowPhase.diagnosisRuntime, "diagnosis_runtime"),
    ])
  func phaseEnumStringStability(phase: WorkflowPhase, expectedRaw: String) throws {
    let result = DiagnosisStatusResult(
      phase: phase,
      status: .inProgress,
      runId: "run-phase",
      attemptId: "attempt-1",
      resolvedContext: Self.context,
      summary: nil,
      failure: nil,
      persistedRunPath: nil
    )
    let parsed = try Self.parseJSON(WorkflowJSONRenderer.renderJSON(result))
    #expect(parsed["phase"] as? String == expectedRaw)
  }

  // MARK: - 6. Workflow field and schema version present across all result types

  @Test("All result types embed the workflow field")
  func workflowFieldConsistency() throws {
    let startJSON = try Self.parseJSON(WorkflowJSONRenderer.renderJSON(Self.makeStartResult()))
    #expect(startJSON["workflow"] as? String == "diagnosis")

    let buildJSON = try Self.parseJSON(WorkflowJSONRenderer.renderJSON(Self.makeBuildResult()))
    #expect(buildJSON["workflow"] as? String == "diagnosis")

    let testJSON = try Self.parseJSON(WorkflowJSONRenderer.renderJSON(Self.makeTestResult()))
    #expect(testJSON["workflow"] as? String == "diagnosis")

    let runtimeJSON = try Self.parseJSON(WorkflowJSONRenderer.renderJSON(Self.makeRuntimeResult()))
    #expect(runtimeJSON["workflow"] as? String == "diagnosis")

    let statusJSON = try Self.parseJSON(WorkflowJSONRenderer.renderJSON(Self.makeStatusResult()))
    #expect(statusJSON["workflow"] as? String == "diagnosis")

    let verifyJSON = try Self.parseJSON(WorkflowJSONRenderer.renderJSON(Self.makeVerifyResult()))
    #expect(verifyJSON["workflow"] as? String == "diagnosis")

    let compareJSON = try Self.parseJSON(WorkflowJSONRenderer.renderJSON(Self.makeCompareResult()))
    #expect(compareJSON["workflow"] as? String == "diagnosis")

    let finalJSON = try Self.parseJSON(WorkflowJSONRenderer.renderJSON(Self.makeFinalResult()))
    #expect(finalJSON["workflow"] as? String == "diagnosis")

    let evidenceJSON = try Self.parseJSON(
      WorkflowJSONRenderer.renderJSON(Self.makeEvidenceResult()))
    #expect(evidenceJSON["workflow"] as? String == "diagnosis")

    let inspectJSON = try Self.parseJSON(WorkflowJSONRenderer.renderJSON(Self.makeInspectResult()))
    #expect(inspectJSON["workflow"] as? String == "diagnosis")
  }

  // MARK: - 7. Stability contract type count guard

  @Test("StableWorkflowContract covers all supported result types")
  func contractTypeCountGuard() {
    #expect(
      StableWorkflowContract.allSupportedResultTypes.count
        == StableWorkflowContract.supportedResultTypeCount)
  }
}

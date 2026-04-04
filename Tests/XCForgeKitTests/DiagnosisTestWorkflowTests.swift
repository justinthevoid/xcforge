import Foundation
import Testing

@testable import XCForgeKit

@Suite("DiagnosisTestWorkflow", .serialized)
struct DiagnosisTestWorkflowTests {

  @Test("failing tests persist a compact primary failure summary")
  func failingTestsPersistSummary() async throws {
    let tempDir = makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let store = RunStore(baseDirectory: tempDir)
    let fixedDate = Date(timeIntervalSince1970: 1_743_600_000)
    let run = makeRun()
    _ = try store.save(run)
    let xcresultURL = tempDir.appendingPathComponent("test-run.xcresult", isDirectory: true)
    try FileManager.default.createDirectory(
      at: xcresultURL, withIntermediateDirectories: true, attributes: nil)

    let workflow = DiagnosisTestWorkflow(
      loadRun: { runId in try store.load(runId: runId) },
      persistRun: { run in try store.update(run) },
      executeTest: { _ in
        TestTools.TestDiagnosisExecution(
          succeeded: false,
          elapsed: "10.2",
          xcresultPath: xcresultURL.path,
          failures: [
            TestTools.TestFailureObservation(
              testName: "testShowsErrorBanner()",
              testIdentifier: "AppTests/LoginTests/testShowsErrorBanner()",
              message: "XCTAssertEqual failed: (\"Welcome\") is not equal to (\"Error\")",
              source: "xcresult.test-details"
            ),
            TestTools.TestFailureObservation(
              testName: "testRetriesAfterFailure()",
              testIdentifier: "AppTests/LoginTests/testRetriesAfterFailure()",
              message: "XCTAssertTrue failed",
              source: "xcresult.test-details"
            ),
          ],
          totalTestCount: 14,
          failedTestCount: 2,
          passedTestCount: 12,
          skippedTestCount: 0,
          expectedFailureCount: 0,
          destinationDeviceName: "iPhone 16",
          destinationOSVersion: "18.0"
        )
      },
      now: { fixedDate }
    )

    let result = await workflow.diagnose(request: DiagnosisTestRequest(runId: run.runId))

    #expect(result.status == WorkflowStatus.failed)
    #expect(
      result.summary?.observedEvidence.primaryFailure?.testIdentifier
        == "AppTests/LoginTests/testShowsErrorBanner()")
    #expect(
      result.summary?.observedEvidence.primaryFailure?.message
        == "XCTAssertEqual failed: (\"Welcome\") is not equal to (\"Error\")")
    #expect(result.summary?.observedEvidence.additionalFailureCount == 1)
    #expect(
      result.summary?.supportingEvidence == [
        EvidenceReference(
          kind: "xcresult", path: xcresultURL.path, source: "xcodebuild.result_bundle")
      ])

    let persisted = try store.load(runId: run.runId)
    #expect(persisted.phase == WorkflowPhase.diagnosisTest)
    #expect(persisted.status == WorkflowStatus.failed)
    #expect(persisted.updatedAt == fixedDate)
    #expect(persisted.testDiagnosisSummary == result.summary)
    #expect(persisted.attemptHistory.count == 2)
    #expect(persisted.attemptHistory.first?.phase == .diagnosisStart)
    #expect(persisted.attemptHistory.last?.phase == .diagnosisTest)
    #expect(
      persisted.evidence == [
        WorkflowEvidenceRecord(
          kind: .testSummary,
          phase: .diagnosisTest,
          attemptId: "attempt-1",
          attemptNumber: 1,
          availability: .available,
          unavailableReason: nil,
          reference: "run_record.testDiagnosisSummary",
          source: "xcforge.diagnosis_test.summary"
        ),
        WorkflowEvidenceRecord(
          kind: .xcresult,
          phase: .diagnosisTest,
          attemptId: "attempt-1",
          attemptNumber: 1,
          availability: .available,
          unavailableReason: nil,
          reference: xcresultURL.path,
          source: "xcodebuild.result_bundle"
        ),
        WorkflowEvidenceRecord(
          kind: .stderr,
          phase: .diagnosisTest,
          attemptId: "attempt-1",
          attemptNumber: 1,
          availability: .unavailable,
          unavailableReason: .notCaptured,
          reference: nil,
          source: "xcodebuild.stderr",
          detail: "No stderr artifact was captured for this test diagnosis phase."
        ),
      ])
  }

  @Test("successful test diagnosis reports that no failure signal was found")
  func successfulTestsReportNoFailureSignal() async throws {
    let tempDir = makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let store = RunStore(baseDirectory: tempDir)
    let run = makeRun()
    _ = try store.save(run)
    let xcresultURL = tempDir.appendingPathComponent("test-success.xcresult", isDirectory: true)
    try FileManager.default.createDirectory(
      at: xcresultURL, withIntermediateDirectories: true, attributes: nil)

    let workflow = DiagnosisTestWorkflow(
      loadRun: { runId in try store.load(runId: runId) },
      persistRun: { run in try store.update(run) },
      executeTest: { _ in
        TestTools.TestDiagnosisExecution(
          succeeded: true,
          elapsed: "6.1",
          xcresultPath: xcresultURL.path,
          failures: [],
          totalTestCount: 8,
          failedTestCount: 0,
          passedTestCount: 8,
          skippedTestCount: 0,
          expectedFailureCount: 0,
          destinationDeviceName: "iPhone 16",
          destinationOSVersion: "18.0"
        )
      }
    )

    let result = await workflow.diagnose(request: DiagnosisTestRequest(runId: run.runId))

    #expect(result.isSuccessfulDiagnosis)
    #expect(result.summary?.observedEvidence.primaryFailure == nil)
    #expect(
      result.summary?.inferredConclusion?.summary
        == "No failing test signal was found for this run.")

    let persisted = try store.load(runId: run.runId)
    #expect(persisted.status == WorkflowStatus.succeeded)
    #expect(persisted.phase == WorkflowPhase.diagnosisTest)
  }

  @Test("environment blockers return unsupported without fabricating a test failure")
  func environmentBlockersReturnUnsupported() async throws {
    let tempDir = makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let store = RunStore(baseDirectory: tempDir)
    let run = makeRun(
      runId: "run-env-blocked",
      phase: .diagnosisBuild,
      status: .failed,
      evidence: [
        WorkflowEvidenceRecord(
          kind: .buildSummary,
          phase: .diagnosisBuild,
          attemptId: "attempt-1",
          attemptNumber: 1,
          availability: .available,
          unavailableReason: nil,
          reference: "run_record.diagnosisSummary",
          source: "xcforge.diagnosis_build.summary"
        )
      ]
    )
    _ = try store.save(run)
    let xcresultURL = tempDir.appendingPathComponent("test-blocked.xcresult", isDirectory: true)
    try FileManager.default.createDirectory(
      at: xcresultURL, withIntermediateDirectories: true, attributes: nil)
    let stderrURL = tempDir.appendingPathComponent(
      "test-blocked.xcresult.stderr.txt", isDirectory: false)
    try "stderr".write(to: stderrURL, atomically: true, encoding: .utf8)

    let workflow = DiagnosisTestWorkflow(
      loadRun: { runId in try store.load(runId: runId) },
      persistRun: { run in try store.update(run) },
      executeTest: { _ in
        TestTools.TestDiagnosisExecution(
          succeeded: false,
          elapsed: "2.3",
          xcresultPath: xcresultURL.path,
          stderrEvidencePath: stderrURL.path,
          failures: [],
          totalTestCount: 0,
          failedTestCount: 0,
          passedTestCount: 0,
          skippedTestCount: 0,
          expectedFailureCount: 0,
          destinationDeviceName: nil,
          destinationOSVersion: nil,
          executionFailureMessage:
            "Unable to find a destination matching the provided destination specifier"
        )
      }
    )

    let result = await workflow.diagnose(request: DiagnosisTestRequest(runId: run.runId))

    #expect(result.status == WorkflowStatus.unsupported)
    #expect(result.summary?.observedEvidence.primaryFailure == nil)
    #expect(
      result.summary?.supportingEvidence == [
        EvidenceReference(
          kind: "xcresult", path: xcresultURL.path, source: "xcodebuild.result_bundle"),
        EvidenceReference(kind: "stderr", path: stderrURL.path, source: "xcodebuild.stderr"),
      ])
    #expect(result.failure?.field == .simulator)
    #expect(result.failure?.classification == .unsupportedContext)
    #expect(result.persistedRunPath != nil)

    let persisted = try store.load(runId: run.runId)
    #expect(persisted.phase == WorkflowPhase.diagnosisTest)
    #expect(persisted.status == WorkflowStatus.unsupported)
    #expect(persisted.testDiagnosisSummary == result.summary)
    #expect(
      persisted.evidence == [
        WorkflowEvidenceRecord(
          kind: .buildSummary,
          phase: .diagnosisBuild,
          attemptId: "attempt-1",
          attemptNumber: 1,
          availability: .available,
          unavailableReason: nil,
          reference: "run_record.diagnosisSummary",
          source: "xcforge.diagnosis_build.summary"
        ),
        WorkflowEvidenceRecord(
          kind: .testSummary,
          phase: .diagnosisTest,
          attemptId: "attempt-1",
          attemptNumber: 1,
          availability: .available,
          unavailableReason: nil,
          reference: "run_record.testDiagnosisSummary",
          source: "xcforge.diagnosis_test.summary"
        ),
        WorkflowEvidenceRecord(
          kind: .xcresult,
          phase: .diagnosisTest,
          attemptId: "attempt-1",
          attemptNumber: 1,
          availability: .available,
          unavailableReason: nil,
          reference: xcresultURL.path,
          source: "xcodebuild.result_bundle"
        ),
        WorkflowEvidenceRecord(
          kind: .stderr,
          phase: .diagnosisTest,
          attemptId: "attempt-1",
          attemptNumber: 1,
          availability: .available,
          unavailableReason: nil,
          reference: stderrURL.path,
          source: "xcodebuild.stderr"
        ),
      ])
  }

  @Test("missing or invalid runs fail explicitly")
  func missingOrInvalidRunsFailExplicitly() async {
    let workflowMissing = DiagnosisTestWorkflow(
      loadRun: { _ in throw CocoaError(.fileNoSuchFile) },
      persistRun: { _ in URL(fileURLWithPath: "/tmp/unused") },
      executeTest: { _ in
        throw TestFailure.unusedResolver
      }
    )

    let missingResult = await workflowMissing.diagnose(
      request: DiagnosisTestRequest(runId: "missing-run")
    )

    #expect(missingResult.status == WorkflowStatus.failed)
    #expect(missingResult.failure?.field == .run)
    #expect(missingResult.failure?.classification == .notFound)

    let invalidRun = WorkflowRunRecord(
      runId: "invalid-run",
      workflow: .diagnosis,
      phase: .diagnosisTest,
      status: .failed,
      createdAt: Date(timeIntervalSince1970: 1_743_417_600),
      updatedAt: Date(timeIntervalSince1970: 1_743_417_600),
      attempt: WorkflowAttemptRecord(
        attemptId: "attempt-1",
        attemptNumber: 1,
        phase: .diagnosisTest,
        startedAt: Date(timeIntervalSince1970: 1_743_417_600),
        status: .failed
      ),
      resolvedContext: makeResolvedContext()
    )
    let workflowInvalid = DiagnosisTestWorkflow(
      loadRun: { _ in invalidRun },
      persistRun: { _ in URL(fileURLWithPath: "/tmp/unused") },
      executeTest: { _ in
        throw TestFailure.unusedResolver
      }
    )

    let invalidResult = await workflowInvalid.diagnose(
      request: DiagnosisTestRequest(runId: invalidRun.runId)
    )

    #expect(invalidResult.status == WorkflowStatus.failed)
    #expect(invalidResult.failure?.field == .run)
    #expect(invalidResult.failure?.classification == .invalidRunState)
  }

  @Test("test execution errors persist a failed run state")
  func testExecutionErrorsPersistFailedRunState() async throws {
    let tempDir = makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let store = RunStore(baseDirectory: tempDir)
    let run = makeRun(runId: "run-test-error")
    _ = try store.save(run)

    let workflow = DiagnosisTestWorkflow(
      loadRun: { runId in try store.load(runId: runId) },
      persistRun: { run in try store.update(run) },
      executeTest: { _ in
        throw ResolverError("xcodebuild test invocation crashed")
      }
    )

    let result = await workflow.diagnose(request: DiagnosisTestRequest(runId: run.runId))

    #expect(result.status == WorkflowStatus.failed)
    #expect(result.failure?.field == .test)
    #expect(result.failure?.classification == .executionFailed)

    let persisted = try store.load(runId: run.runId)
    #expect(persisted.phase == WorkflowPhase.diagnosisTest)
    #expect(persisted.status == WorkflowStatus.failed)
    #expect(persisted.testDiagnosisSummary == nil)
    #expect(
      persisted.evidence == [
        WorkflowEvidenceRecord(
          kind: .testSummary,
          phase: .diagnosisTest,
          attemptId: "attempt-1",
          attemptNumber: 1,
          availability: .unavailable,
          unavailableReason: .executionFailed,
          reference: nil,
          source: "xcforge.diagnosis_test.summary",
          detail:
            "Test execution failed before xcforge could persist a test summary. xcodebuild test invocation crashed"
        ),
        WorkflowEvidenceRecord(
          kind: .xcresult,
          phase: .diagnosisTest,
          attemptId: "attempt-1",
          attemptNumber: 1,
          availability: .unavailable,
          unavailableReason: .executionFailed,
          reference: nil,
          source: "xcodebuild.result_bundle",
          detail: "Test execution failed before an xcresult artifact was captured."
        ),
        WorkflowEvidenceRecord(
          kind: .stderr,
          phase: .diagnosisTest,
          attemptId: "attempt-1",
          attemptNumber: 1,
          availability: .unavailable,
          unavailableReason: .executionFailed,
          reference: nil,
          source: "xcodebuild.stderr",
          detail: "Test execution failed before a stderr artifact was captured."
        ),
      ])
  }

  private func makeRun(
    runId: String = "run-123",
    phase: WorkflowPhase = .diagnosisStart,
    status: WorkflowStatus = .inProgress,
    evidence: [WorkflowEvidenceRecord] = []
  ) -> WorkflowRunRecord {
    WorkflowRunRecord(
      runId: runId,
      workflow: .diagnosis,
      phase: phase,
      status: status,
      createdAt: Date(timeIntervalSince1970: 1_743_417_600),
      updatedAt: Date(timeIntervalSince1970: 1_743_417_600),
      attempt: WorkflowAttemptRecord(
        attemptId: "attempt-1",
        attemptNumber: 1,
        phase: phase,
        startedAt: Date(timeIntervalSince1970: 1_743_417_600),
        status: status
      ),
      resolvedContext: makeResolvedContext(),
      evidence: evidence
    )
  }

  private func makeResolvedContext() -> ResolvedWorkflowContext {
    ResolvedWorkflowContext(
      project: "/tmp/App.xcodeproj",
      scheme: "App",
      simulator: "SIM-123",
      configuration: "Debug",
      app: AppContext(bundleId: "com.example.app", appPath: "/tmp/Derived/App.app")
    )
  }

  private func makeTempDirectory() -> URL {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try? FileManager.default.createDirectory(
      at: dir,
      withIntermediateDirectories: true,
      attributes: nil
    )
    return dir
  }
}

private enum TestFailure: Error {
  case unusedResolver
}

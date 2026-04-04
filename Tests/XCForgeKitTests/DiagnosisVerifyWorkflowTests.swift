import Foundation
import Testing

@testable import XCForgeKit

@Suite("DiagnosisVerifyWorkflow", .serialized)
struct DiagnosisVerifyWorkflowTests {

  @Test("rerunning a failed test uses the same context and records a verified follow-up attempt")
  func rerunsFailedTestAndMarksVerified() async throws {
    let tempDir = makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let store = RunStore(baseDirectory: tempDir)
    let run = makeFailedTestRun()
    _ = try store.save(run)

    let rerunXCResultURL = tempDir.appendingPathComponent("rerun-tests.xcresult", isDirectory: true)
    try FileManager.default.createDirectory(
      at: rerunXCResultURL, withIntermediateDirectories: true, attributes: nil)

    let workflow = DiagnosisVerifyWorkflow(
      loadRun: { runId in try store.load(runId: runId) },
      persistRun: { run in try store.update(run) },
      executeBuild: { _ in throw VerifyTestFailure.unusedResolver },
      executeTest: { context in
        #expect(context == run.resolvedContext)
        return TestTools.TestDiagnosisExecution(
          succeeded: true,
          elapsed: "4.4",
          xcresultPath: rerunXCResultURL.path,
          failures: [],
          totalTestCount: 6,
          failedTestCount: 0,
          passedTestCount: 6,
          skippedTestCount: 0,
          expectedFailureCount: 0,
          destinationDeviceName: "iPhone 16",
          destinationOSVersion: "18.0"
        )
      },
      resolveAppContext: { _, _, _, _ in throw VerifyTestFailure.unusedResolver },
      now: { Date(timeIntervalSince1970: 1_743_800_000) },
      makeID: { "attempt-2" }
    )

    let result = await workflow.verify(request: DiagnosisVerifyRequest(runId: run.runId))

    #expect(result.isSuccessfulVerification)
    #expect(result.outcome == .verified)
    #expect(result.phase == .diagnosisTest)
    #expect(result.status == .succeeded)
    #expect(result.runId == run.runId)
    #expect(result.attemptId == "attempt-2")
    #expect(result.sourceAttemptId == "attempt-1")
    #expect(result.resolvedContext == run.resolvedContext)
    #expect(
      result.evidence.contains(where: {
        $0.kind == .xcresult && $0.reference == rerunXCResultURL.path
      }))

    let persisted = try store.load(runId: run.runId)
    #expect(persisted.attempt.attemptId == "attempt-2")
    #expect(persisted.attempt.attemptNumber == 2)
    #expect(persisted.attempt.rerunOfAttemptId == "attempt-1")
    #expect(persisted.status == .succeeded)
    #expect(persisted.testDiagnosisSummary?.observedEvidence.failedTestCount == 0)
    #expect(persisted.attemptHistory.count == 2)
    #expect(persisted.attemptHistory.first?.attempt.attemptId == "attempt-1")
    #expect(persisted.attemptHistory.last?.attempt.attemptId == "attempt-2")
  }

  @Test("rerun overrides resolve a new context and blocked reruns stay explicit")
  func rerunOverridesResolveNewContextAndBlockedRerunsStayExplicit() async throws {
    let tempDir = makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let store = RunStore(baseDirectory: tempDir)
    let run = makeFailedTestRun(runId: "run-override-test")
    _ = try store.save(run)

    let rerunXCResultURL = tempDir.appendingPathComponent(
      "blocked-rerun.xcresult", isDirectory: true)
    let rerunStderrURL = tempDir.appendingPathComponent(
      "blocked-rerun.stderr.txt", isDirectory: false)
    try FileManager.default.createDirectory(
      at: rerunXCResultURL, withIntermediateDirectories: true, attributes: nil)
    try "stderr".write(to: rerunStderrURL, atomically: true, encoding: .utf8)

    let workflow = DiagnosisVerifyWorkflow(
      loadRun: { runId in try store.load(runId: runId) },
      persistRun: { run in try store.update(run) },
      executeBuild: { _ in throw VerifyTestFailure.unusedResolver },
      executeTest: { context in
        #expect(context.simulator == "SIM-999")
        #expect(context.configuration == "Release")
        return TestTools.TestDiagnosisExecution(
          succeeded: false,
          elapsed: "1.7",
          xcresultPath: rerunXCResultURL.path,
          stderrEvidencePath: rerunStderrURL.path,
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
      },
      resolveAppContext: { project, scheme, simulator, configuration in
        #expect(project == run.resolvedContext.project)
        #expect(scheme == run.resolvedContext.scheme)
        #expect(simulator == "SIM-999")
        #expect(configuration == "Release")
        return AppContext(bundleId: "com.example.override", appPath: "/tmp/Derived/Override.app")
      },
      now: { Date(timeIntervalSince1970: 1_743_800_100) },
      makeID: { "attempt-override" }
    )

    let result = await workflow.verify(
      request: DiagnosisVerifyRequest(
        runId: run.runId,
        simulator: "SIM-999",
        configuration: "Release"
      )
    )

    #expect(result.outcome == .blocked)
    #expect(result.failure?.field == .simulator)
    #expect(result.failure?.classification == .unsupportedContext)
    #expect(result.resolvedContext?.simulator == "SIM-999")
    #expect(result.resolvedContext?.configuration == "Release")

    let persisted = try store.load(runId: run.runId)
    #expect(persisted.attempt.attemptId == "attempt-override")
    #expect(persisted.attempt.rerunOfAttemptId == "attempt-1")
    #expect(persisted.resolvedContext.simulator == "SIM-999")
    #expect(persisted.resolvedContext.configuration == "Release")
  }

  @Test("rerunning the same failing build classifies the result as unchanged")
  func rerunsSameFailingBuildAsUnchanged() async throws {
    let tempDir = makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let store = RunStore(baseDirectory: tempDir)
    let run = makeFailedBuildRun()
    _ = try store.save(run)

    let rerunXCResultURL = tempDir.appendingPathComponent("rerun-build.xcresult", isDirectory: true)
    try FileManager.default.createDirectory(
      at: rerunXCResultURL, withIntermediateDirectories: true, attributes: nil)

    let workflow = DiagnosisVerifyWorkflow(
      loadRun: { runId in try store.load(runId: runId) },
      persistRun: { run in try store.update(run) },
      executeBuild: { _ in
        TestTools.BuildDiagnosisExecution(
          succeeded: false,
          elapsed: "5.0",
          xcresultPath: rerunXCResultURL.path,
          issues: [
            TestTools.BuildIssueObservation(
              severity: .error,
              message: "Cannot find 'WidgetView' in scope",
              location: SourceLocation(filePath: "/tmp/App/Feature.swift", line: 42, column: 9),
              source: "xcresult.errors"
            )
          ],
          errorCount: 1,
          warningCount: 0,
          analyzerWarningCount: 0,
          destinationDeviceName: "iPhone 16",
          destinationOSVersion: "18.0"
        )
      },
      executeTest: { _ in throw VerifyTestFailure.unusedResolver },
      resolveAppContext: { _, _, _, _ in throw VerifyTestFailure.unusedResolver },
      now: { Date(timeIntervalSince1970: 1_743_800_200) },
      makeID: { "attempt-build-rerun" }
    )

    let result = await workflow.verify(request: DiagnosisVerifyRequest(runId: run.runId))

    #expect(result.outcome == .unchanged)
    #expect(result.status == .failed)
    #expect(result.phase == .diagnosisBuild)

    let persisted = try store.load(runId: run.runId)
    #expect(persisted.attempt.attemptId == "attempt-build-rerun")
    #expect(persisted.attempt.rerunOfAttemptId == "attempt-1")
    #expect(persisted.attemptHistory.count == 2)
  }

  @Test("non-rerunnable runs fail explicitly without mutation")
  func nonRerunnableRunsFailExplicitly() async throws {
    let tempDir = makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let store = RunStore(baseDirectory: tempDir)
    let run = WorkflowRunRecord(
      runId: "run-start-only",
      workflow: .diagnosis,
      phase: .diagnosisStart,
      status: .inProgress,
      createdAt: Date(timeIntervalSince1970: 1_743_700_000),
      updatedAt: Date(timeIntervalSince1970: 1_743_700_000),
      attempt: WorkflowAttemptRecord(
        attemptId: "attempt-1",
        attemptNumber: 1,
        phase: .diagnosisStart,
        startedAt: Date(timeIntervalSince1970: 1_743_700_000),
        status: .inProgress
      ),
      resolvedContext: makeResolvedContext()
    )
    _ = try store.save(run)

    let workflow = DiagnosisVerifyWorkflow(
      loadRun: { runId in try store.load(runId: runId) },
      persistRun: { run in try store.update(run) },
      executeBuild: { _ in throw VerifyTestFailure.unusedResolver },
      executeTest: { _ in throw VerifyTestFailure.unusedResolver },
      resolveAppContext: { _, _, _, _ in throw VerifyTestFailure.unusedResolver }
    )

    let result = await workflow.verify(request: DiagnosisVerifyRequest(runId: run.runId))

    #expect(result.isSuccessfulVerification == false)
    #expect(result.failure?.field == .run)
    #expect(result.failure?.classification == .invalidRunState)

    let persisted = try store.load(runId: run.runId)
    #expect(persisted == run)
  }

  @Test("whitespace-only overrides fail explicitly instead of falling back to the original context")
  func whitespaceOnlyOverridesFailExplicitly() async throws {
    let tempDir = makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let store = RunStore(baseDirectory: tempDir)
    let run = makeFailedTestRun(runId: "run-whitespace-override")
    _ = try store.save(run)

    let workflow = DiagnosisVerifyWorkflow(
      loadRun: { runId in try store.load(runId: runId) },
      persistRun: { run in try store.update(run) },
      executeBuild: { _ in throw VerifyTestFailure.unusedResolver },
      executeTest: { _ in throw VerifyTestFailure.unusedResolver },
      resolveAppContext: { _, _, _, _ in throw VerifyTestFailure.unusedResolver },
      now: { Date(timeIntervalSince1970: 1_743_800_300) },
      makeID: { "attempt-whitespace" }
    )

    let result = await workflow.verify(
      request: DiagnosisVerifyRequest(runId: run.runId, simulator: "   ")
    )

    #expect(result.isSuccessfulVerification == false)
    #expect(result.outcome == .failed)
    #expect(result.failure?.field == .simulator)
    #expect(result.failure?.classification == .resolutionFailed)

    let persisted = try store.load(runId: run.runId)
    #expect(persisted.attempt.attemptId == "attempt-whitespace")
    #expect(persisted.attempt.rerunOfAttemptId == "attempt-1")
    #expect(persisted.status == .failed)
    #expect(persisted.attemptHistory.count == 2)
  }

  private func makeFailedTestRun(runId: String = "run-test") -> WorkflowRunRecord {
    WorkflowRunRecord(
      runId: runId,
      workflow: .diagnosis,
      phase: .diagnosisTest,
      status: .failed,
      createdAt: Date(timeIntervalSince1970: 1_743_700_000),
      updatedAt: Date(timeIntervalSince1970: 1_743_700_010),
      attempt: WorkflowAttemptRecord(
        attemptId: "attempt-1",
        attemptNumber: 1,
        phase: .diagnosisTest,
        startedAt: Date(timeIntervalSince1970: 1_743_700_010),
        status: .failed
      ),
      resolvedContext: makeResolvedContext(),
      testDiagnosisSummary: TestDiagnosisSummary(
        observedEvidence: ObservedTestEvidence(
          summary:
            "Primary failing test selected from 1 failing test(s): AppTests/LoginTests/testShowsErrorBanner().",
          primaryFailure: TestFailureSummary(
            testName: "testShowsErrorBanner()",
            testIdentifier: "AppTests/LoginTests/testShowsErrorBanner()",
            message: "XCTAssertEqual failed",
            source: "xcresult.test-details"
          ),
          additionalFailureCount: 0,
          totalTestCount: 6,
          failedTestCount: 1,
          passedTestCount: 5,
          skippedTestCount: 0,
          expectedFailureCount: 0
        ),
        inferredConclusion: InferredTestConclusion(
          summary:
            "The run appears primarily blocked by failing test AppTests/LoginTests/testShowsErrorBanner(): XCTAssertEqual failed"
        ),
        supportingEvidence: [
          EvidenceReference(
            kind: "xcresult", path: "/tmp/original-test.xcresult",
            source: "xcodebuild.result_bundle")
        ]
      ),
      evidence: [
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
          reference: "/tmp/original-test.xcresult",
          source: "xcodebuild.result_bundle"
        ),
      ]
    )
  }

  private func makeFailedBuildRun(runId: String = "run-build") -> WorkflowRunRecord {
    WorkflowRunRecord(
      runId: runId,
      workflow: .diagnosis,
      phase: .diagnosisBuild,
      status: .failed,
      createdAt: Date(timeIntervalSince1970: 1_743_700_000),
      updatedAt: Date(timeIntervalSince1970: 1_743_700_020),
      attempt: WorkflowAttemptRecord(
        attemptId: "attempt-1",
        attemptNumber: 1,
        phase: .diagnosisBuild,
        startedAt: Date(timeIntervalSince1970: 1_743_700_020),
        status: .failed
      ),
      resolvedContext: makeResolvedContext(),
      diagnosisSummary: BuildDiagnosisSummary(
        observedEvidence: ObservedBuildEvidence(
          summary: "Build failed with a primary compiler error.",
          primarySignal: BuildIssueSummary(
            severity: .error,
            message: "Cannot find 'WidgetView' in scope",
            location: SourceLocation(filePath: "/tmp/App/Feature.swift", line: 42, column: 9),
            source: "xcresult.errors"
          ),
          additionalIssueCount: 0,
          errorCount: 1,
          warningCount: 0,
          analyzerWarningCount: 0
        ),
        inferredConclusion: InferredBuildConclusion(
          summary: "The run failed because WidgetView is unresolved."
        ),
        supportingEvidence: [
          EvidenceReference(
            kind: "xcresult", path: "/tmp/original-build.xcresult",
            source: "xcodebuild.result_bundle")
        ]
      ),
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
        ),
        WorkflowEvidenceRecord(
          kind: .xcresult,
          phase: .diagnosisBuild,
          attemptId: "attempt-1",
          attemptNumber: 1,
          availability: .available,
          unavailableReason: nil,
          reference: "/tmp/original-build.xcresult",
          source: "xcodebuild.result_bundle"
        ),
      ]
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

private enum VerifyTestFailure: Error {
  case unusedResolver
}

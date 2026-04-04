import Foundation
import Testing

@testable import XCForgeKit

@Suite("DiagnosisStatusWorkflow", .serialized)
struct DiagnosisStatusWorkflowTests {

  @Test("explicit run lookup returns persisted build status and summary")
  func explicitRunLookupReturnsPersistedBuildStatus() async throws {
    let tempDir = makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let store = RunStore(baseDirectory: tempDir)
    let run = makeRun(
      runId: "run-build",
      phase: .diagnosisBuild,
      status: .failed,
      updatedAt: Date(timeIntervalSince1970: 1_743_700_000),
      diagnosisSummary: BuildDiagnosisSummary(
        observedEvidence: ObservedBuildEvidence(
          summary: "Build failed with a primary compiler error.",
          primarySignal: BuildIssueSummary(
            severity: .error,
            message: "Cannot find 'WidgetView' in scope",
            location: SourceLocation(filePath: "/tmp/App/Feature.swift", line: 42, column: 9),
            source: "xcresult.errors"
          ),
          additionalIssueCount: 1,
          errorCount: 2,
          warningCount: 0,
          analyzerWarningCount: 0
        ),
        inferredConclusion: InferredBuildConclusion(
          summary: "The run failed because WidgetView is unresolved."
        ),
        supportingEvidence: [
          EvidenceReference(
            kind: "xcresult", path: "/tmp/build-run.xcresult", source: "xcodebuild.result_bundle")
        ]
      )
    )
    _ = try store.save(run)

    let workflow = makeWorkflow(store: store)
    let result = await workflow.inspect(request: DiagnosisStatusRequest(runId: run.runId))

    #expect(result.isSuccessfulInspection)
    #expect(result.runId == "run-build")
    #expect(result.phase == .diagnosisBuild)
    #expect(result.status == .failed)
    #expect(result.summary?.source == .build)
    #expect(result.summary?.headline == "Build failed with a primary compiler error.")
    #expect(result.summary?.detail == "Cannot find 'WidgetView' in scope")
    #expect(result.persistedRunPath == store.runFileURL(runId: run.runId).path)
  }

  @Test("status inspection keeps prepared simulator context visible")
  func statusInspectionKeepsPreparedSimulatorContextVisible() async throws {
    let tempDir = makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let store = RunStore(baseDirectory: tempDir)
    let run = makeRun(
      runId: "run-prepared-simulator",
      phase: .diagnosisStart,
      status: .inProgress,
      updatedAt: Date(timeIntervalSince1970: 1_743_700_050),
      resolvedContext: makePreparedResolvedContext()
    )
    _ = try store.save(run)

    let workflow = makeWorkflow(store: store)
    let result = await workflow.inspect(request: DiagnosisStatusRequest(runId: run.runId))

    #expect(result.isSuccessfulInspection)
    #expect(result.resolvedContext?.simulator == "SIM-123")
    #expect(
      result.resolvedContext?.simulatorPreparation
        == makePreparedSimulatorContext(requested: "iPhone 16 Pro", selected: "SIM-123"))
    #expect(result.resolvedContext?.simulatorPreparation?.initialState == "Booted")
    #expect(result.resolvedContext?.simulatorPreparation?.action == .reusedBooted)
  }

  @Test("evidence inspection returns grouped build evidence and explicit missing artifacts")
  func evidenceInspectionReturnsGroupedBuildEvidence() async throws {
    let tempDir = makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let store = RunStore(baseDirectory: tempDir)
    let run = makeRun(
      runId: "run-build-evidence",
      phase: .diagnosisBuild,
      status: .failed,
      updatedAt: Date(timeIntervalSince1970: 1_743_700_000),
      diagnosisSummary: makeBuildSummary(
        observedSummary: "Build failed with a primary compiler error.",
        inferredSummary: "The run failed because WidgetView is unresolved."
      ),
      evidence: [
        WorkflowEvidenceRecord(
          kind: .buildSummary,
          phase: .diagnosisBuild,
          attemptId: "attempt-run-build-evidence",
          attemptNumber: 1,
          availability: .available,
          unavailableReason: nil,
          reference: "run_record.diagnosisSummary",
          source: "xcforge.diagnosis_build.summary"
        ),
        WorkflowEvidenceRecord(
          kind: .xcresult,
          phase: .diagnosisBuild,
          attemptId: "attempt-run-build-evidence",
          attemptNumber: 1,
          availability: .available,
          unavailableReason: nil,
          reference: "/tmp/build-run.xcresult",
          source: "xcodebuild.result_bundle"
        ),
        WorkflowEvidenceRecord(
          kind: .stderr,
          phase: .diagnosisBuild,
          attemptId: "attempt-run-build-evidence",
          attemptNumber: 1,
          availability: .unavailable,
          unavailableReason: .notCaptured,
          reference: nil,
          source: "xcodebuild.stderr",
          detail: "No stderr artifact was captured for this build diagnosis phase."
        ),
      ]
    )
    _ = try store.save(run)

    let workflow = makeWorkflow(store: store)
    let result = await workflow.inspectEvidence(request: DiagnosisStatusRequest(runId: run.runId))

    #expect(result.isSuccessfulInspection)
    #expect(result.runId == "run-build-evidence")
    #expect(result.phase == .diagnosisBuild)
    #expect(result.status == .failed)
    #expect(result.evidenceState == .partial)
    #expect(
      result.buildSummary?.observedEvidence.summary == "Build failed with a primary compiler error."
    )
    #expect(
      result.buildSummary?.inferredConclusion?.summary
        == "The run failed because WidgetView is unresolved.")
    #expect(result.availableEvidence.count == 2)
    #expect(result.unavailableEvidence.count == 1)
    #expect(result.unavailableEvidence.first?.producingWorkflowStep == "build diagnosis")
    #expect(result.unavailableEvidence.first?.unavailableReasonLabel == "not captured")
    #expect(result.persistedRunPath == store.runFileURL(runId: run.runId).path)
  }

  @Test("evidence inspection keeps build and test evidence separate in one run")
  func evidenceInspectionKeepsBuildAndTestEvidenceSeparate() async throws {
    let tempDir = makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let store = RunStore(baseDirectory: tempDir)
    let run = makeRun(
      runId: "run-combined-evidence",
      phase: .diagnosisTest,
      status: .succeeded,
      updatedAt: Date(timeIntervalSince1970: 1_743_700_500),
      diagnosisSummary: makeBuildSummary(
        observedSummary: "Build succeeded without an error diagnostic.",
        inferredSummary: "No build failure signal was found for this run."
      ),
      testDiagnosisSummary: makeTestSummary(
        observedSummary: "Test run completed without a failing test signal.",
        inferredSummary: "No failing test signal was found for this run."
      ),
      evidence: [
        WorkflowEvidenceRecord(
          kind: .buildSummary,
          phase: .diagnosisBuild,
          attemptId: "attempt-run-combined-evidence",
          attemptNumber: 1,
          availability: .available,
          unavailableReason: nil,
          reference: "run_record.diagnosisSummary",
          source: "xcforge.diagnosis_build.summary"
        ),
        WorkflowEvidenceRecord(
          kind: .testSummary,
          phase: .diagnosisTest,
          attemptId: "attempt-run-combined-evidence",
          attemptNumber: 1,
          availability: .available,
          unavailableReason: nil,
          reference: "run_record.testDiagnosisSummary",
          source: "xcforge.diagnosis_test.summary"
        ),
        WorkflowEvidenceRecord(
          kind: .xcresult,
          phase: .diagnosisTest,
          attemptId: "attempt-run-combined-evidence",
          attemptNumber: 1,
          availability: .available,
          unavailableReason: nil,
          reference: "/tmp/test-run.xcresult",
          source: "xcodebuild.result_bundle"
        ),
      ]
    )
    _ = try store.save(run)

    let workflow = makeWorkflow(store: store)
    let result = await workflow.inspectEvidence(request: DiagnosisStatusRequest(runId: run.runId))

    #expect(result.isSuccessfulInspection)
    #expect(result.runId == "run-combined-evidence")
    #expect(result.evidenceState == .complete)
    #expect(
      result.buildSummary?.observedEvidence.summary
        == "Build succeeded without an error diagnostic.")
    #expect(
      result.buildSummary?.inferredConclusion?.summary
        == "No build failure signal was found for this run.")
    #expect(
      result.testSummary?.observedEvidence.summary
        == "Test run completed without a failing test signal.")
    #expect(
      result.testSummary?.inferredConclusion?.summary
        == "No failing test signal was found for this run.")
    #expect(result.availableEvidence.count == 3)
    #expect(result.unavailableEvidence.isEmpty)
  }

  @Test("status inspection prefers the newest active run over newer completed ones")
  func inspectionPrefersNewestActiveRun() async throws {
    let tempDir = makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let store = RunStore(baseDirectory: tempDir)
    _ = try store.save(
      makeRun(
        runId: "run-completed",
        phase: .diagnosisTest,
        status: .succeeded,
        updatedAt: Date(timeIntervalSince1970: 1_743_700_300),
        testDiagnosisSummary: TestDiagnosisSummary(
          observedEvidence: ObservedTestEvidence(
            summary: "All tests passed.",
            primaryFailure: nil,
            additionalFailureCount: 0,
            totalTestCount: 8,
            failedTestCount: 0,
            passedTestCount: 8,
            skippedTestCount: 0,
            expectedFailureCount: 0
          ),
          inferredConclusion: InferredTestConclusion(
            summary: "No failing test signal was found for this run."
          ),
          supportingEvidence: []
        )
      )
    )
    _ = try store.save(
      makeRun(
        runId: "run-active",
        phase: .diagnosisStart,
        status: .inProgress,
        updatedAt: Date(timeIntervalSince1970: 1_743_700_200)
      )
    )

    let workflow = makeWorkflow(store: store)
    let result = await workflow.inspect(request: DiagnosisStatusRequest())

    #expect(result.runId == "run-active")
    #expect(result.phase == .diagnosisStart)
    #expect(result.status == .inProgress)
    #expect(result.summary?.source == .start)
  }

  @Test("evidence inspection without an explicit run ID prefers the newest active run")
  func evidenceInspectionPrefersNewestActiveRun() async throws {
    let tempDir = makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let store = RunStore(baseDirectory: tempDir)
    _ = try store.save(
      makeRun(
        runId: "run-completed",
        phase: .diagnosisTest,
        status: .succeeded,
        updatedAt: Date(timeIntervalSince1970: 1_743_700_300),
        testDiagnosisSummary: makeTestSummary(
          observedSummary: "All tests passed.",
          inferredSummary: "No failing test signal was found for this run."
        ),
        evidence: [
          WorkflowEvidenceRecord(
            kind: .testSummary,
            phase: .diagnosisTest,
            attemptId: "attempt-run-completed",
            attemptNumber: 1,
            availability: .available,
            unavailableReason: nil,
            reference: "run_record.testDiagnosisSummary",
            source: "xcforge.diagnosis_test.summary"
          )
        ]
      )
    )
    _ = try store.save(
      makeRun(
        runId: "run-active",
        phase: .diagnosisStart,
        status: .inProgress,
        updatedAt: Date(timeIntervalSince1970: 1_743_700_200)
      )
    )

    let workflow = makeWorkflow(store: store)
    let result = await workflow.inspectEvidence(request: DiagnosisStatusRequest())

    #expect(result.isSuccessfulInspection)
    #expect(result.runId == "run-active")
    #expect(result.phase == .diagnosisStart)
    #expect(result.status == .inProgress)
    #expect(result.evidenceState == .empty)
    #expect(result.availableEvidence.isEmpty)
    #expect(result.unavailableEvidence.isEmpty)
  }

  @Test("status inspection falls back to the newest recent run when no active run exists")
  func inspectionFallsBackToNewestRecentRun() async throws {
    let tempDir = makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let store = RunStore(baseDirectory: tempDir)
    _ = try store.save(
      makeRun(
        runId: "run-older",
        phase: .diagnosisBuild,
        status: .failed,
        updatedAt: Date(timeIntervalSince1970: 1_743_700_000),
        diagnosisSummary: BuildDiagnosisSummary(
          observedEvidence: ObservedBuildEvidence(
            summary: "Older build failure.",
            primarySignal: nil,
            additionalIssueCount: 0,
            errorCount: 1,
            warningCount: 0,
            analyzerWarningCount: 0
          ),
          inferredConclusion: nil,
          supportingEvidence: []
        )
      )
    )
    _ = try store.save(
      makeRun(
        runId: "run-newest",
        phase: .diagnosisBuild,
        status: .partial,
        updatedAt: Date(timeIntervalSince1970: 1_743_700_400),
        diagnosisSummary: BuildDiagnosisSummary(
          observedEvidence: ObservedBuildEvidence(
            summary: "Validation completed with partial results.",
            primarySignal: nil,
            additionalIssueCount: 0,
            errorCount: 0,
            warningCount: 1,
            analyzerWarningCount: 0
          ),
          inferredConclusion: InferredBuildConclusion(
            summary: "Only part of the expected build evidence was available."
          ),
          supportingEvidence: []
        )
      )
    )

    let workflow = makeWorkflow(store: store)
    let result = await workflow.inspect(request: DiagnosisStatusRequest())

    #expect(result.runId == "run-newest")
    #expect(result.phase == .diagnosisBuild)
    #expect(result.status == .partial)
    #expect(result.summary?.source == .build)
    #expect(result.summary?.headline == "Validation completed with partial results.")
    #expect(result.summary?.detail == "Only part of the expected build evidence was available.")
  }

  @Test("start-phase runs report status without fabricating diagnosis summaries")
  func startPhaseRunsReportWithoutFabricatedSummary() async throws {
    let tempDir = makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let store = RunStore(baseDirectory: tempDir)
    let run = makeRun(
      runId: "run-start",
      phase: .diagnosisStart,
      status: .inProgress,
      updatedAt: Date(timeIntervalSince1970: 1_743_700_100)
    )
    _ = try store.save(run)

    let workflow = makeWorkflow(store: store)
    let result = await workflow.inspect(request: DiagnosisStatusRequest(runId: run.runId))

    #expect(result.summary?.source == .start)
    #expect(
      result.summary?.headline
        == "Diagnosis run is in phase diagnosis_start with status in_progress.")
    #expect(result.summary?.detail == "No build or test diagnosis summary has been recorded yet.")
  }

  @Test("terminal diagnosis test runs expose their persisted summary and status")
  func terminalDiagnosisTestRunsExposePersistedSummary() async throws {
    let tempDir = makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let store = RunStore(baseDirectory: tempDir)
    let run = makeRun(
      runId: "run-test-terminal",
      phase: .diagnosisTest,
      status: .unsupported,
      updatedAt: Date(timeIntervalSince1970: 1_743_700_500),
      testDiagnosisSummary: TestDiagnosisSummary(
        observedEvidence: ObservedTestEvidence(
          summary: "Unable to find a destination matching the provided destination specifier",
          primaryFailure: nil,
          additionalFailureCount: 0,
          totalTestCount: 0,
          failedTestCount: 0,
          passedTestCount: 0,
          skippedTestCount: 0,
          expectedFailureCount: 0
        ),
        inferredConclusion: InferredTestConclusion(
          summary: "Test execution was blocked before a failing test could be identified."
        ),
        supportingEvidence: [
          EvidenceReference(
            kind: "stderr", path: "/tmp/test-blocked.stderr.txt", source: "xcodebuild.stderr")
        ]
      )
    )
    _ = try store.save(run)

    let workflow = makeWorkflow(store: store)
    let result = await workflow.inspect(request: DiagnosisStatusRequest(runId: run.runId))

    #expect(result.isSuccessfulInspection)
    #expect(result.phase == .diagnosisTest)
    #expect(result.status == .unsupported)
    #expect(result.summary?.source == .test)
    #expect(
      result.summary?.headline
        == "Unable to find a destination matching the provided destination specifier")
    #expect(
      result.summary?.detail
        == "Test execution was blocked before a failing test could be identified.")
  }

  @Test("runtime-phase runs expose persisted runtime summary and evidence")
  func runtimePhaseRunsExposePersistedRuntimeSummary() async throws {
    let tempDir = makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let store = RunStore(baseDirectory: tempDir)
    let run = makeRun(
      runId: "run-runtime",
      phase: .diagnosisRuntime,
      status: .partial,
      updatedAt: Date(timeIntervalSince1970: 1_743_700_550),
      runtimeSummary: makeRuntimeSummary(
        observedSummary:
          "App com.example.app launched, but runtime inspection ended before the app stayed running.",
        inferredSummary:
          "The app reached launch, but the runtime state remained unstable or exited before the capture window completed."
      ),
      evidence: [
        WorkflowEvidenceRecord(
          kind: .runtimeSummary,
          phase: .diagnosisRuntime,
          attemptId: "attempt-run-runtime",
          attemptNumber: 1,
          availability: .available,
          unavailableReason: nil,
          reference: "run_record.runtimeSummary",
          source: "xcforge.diagnosis_runtime.summary"
        ),
        WorkflowEvidenceRecord(
          kind: .consoleLog,
          phase: .diagnosisRuntime,
          attemptId: "attempt-run-runtime",
          attemptNumber: 1,
          availability: .unavailable,
          unavailableReason: .notCaptured,
          reference: nil,
          source: "simctl.launch_console",
          detail: "Runtime inspection did not capture any console output for this attempt."
        ),
        WorkflowEvidenceRecord(
          kind: .screenshot,
          phase: .diagnosisRuntime,
          attemptId: "attempt-run-runtime",
          attemptNumber: 1,
          availability: .available,
          unavailableReason: nil,
          reference: "/tmp/runtime-screenshot.png",
          source: "simctl.io.screenshot"
        ),
      ]
    )
    _ = try store.save(run)

    let workflow = makeWorkflow(store: store)
    let statusResult = await workflow.inspect(request: DiagnosisStatusRequest(runId: run.runId))
    let evidenceResult = await workflow.inspectEvidence(
      request: DiagnosisStatusRequest(runId: run.runId))

    #expect(statusResult.isSuccessfulInspection)
    #expect(statusResult.summary?.source == .runtime)
    #expect(
      statusResult.summary?.headline
        == "App com.example.app launched, but runtime inspection ended before the app stayed running."
    )
    #expect(statusResult.summary?.detail == "launchctl print stalled")
    #expect(evidenceResult.isSuccessfulInspection)
    #expect(
      evidenceResult.runtimeSummary?.observedEvidence.summary
        == "App com.example.app launched, but runtime inspection ended before the app stayed running."
    )
    #expect(
      evidenceResult.runtimeSummary?.inferredConclusion?.summary
        == "The app reached launch, but the runtime state remained unstable or exited before the capture window completed."
    )
    #expect(evidenceResult.evidenceState == .partial)
    let screenshotEvidence = evidenceResult.availableEvidence.first(where: {
      $0.kind == .screenshot
    })
    #expect(screenshotEvidence?.reference == "/tmp/runtime-screenshot.png")
    #expect(evidenceResult.unavailableEvidence.first?.producingWorkflowStep == "runtime diagnosis")
  }

  @Test("runtime evidence inspection keeps unavailable screenshot gaps visible")
  func runtimeEvidenceInspectionKeepsUnavailableScreenshotGapsVisible() async throws {
    let tempDir = makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let store = RunStore(baseDirectory: tempDir)
    let run = makeRun(
      runId: "run-runtime-missing-screenshot",
      phase: .diagnosisRuntime,
      status: .partial,
      updatedAt: Date(timeIntervalSince1970: 1_743_700_551),
      runtimeSummary: makeRuntimeSummary(
        observedSummary: "App com.example.app launched and runtime signals were captured.",
        inferredSummary:
          "Runtime inspection reached a running app state with captured console output or a confirmed live console session."
      ),
      evidence: [
        WorkflowEvidenceRecord(
          kind: .runtimeSummary,
          phase: .diagnosisRuntime,
          attemptId: "attempt-run-runtime-missing-screenshot",
          attemptNumber: 1,
          availability: .available,
          unavailableReason: nil,
          reference: "run_record.runtimeSummary",
          source: "xcforge.diagnosis_runtime.summary"
        ),
        WorkflowEvidenceRecord(
          kind: .consoleLog,
          phase: .diagnosisRuntime,
          attemptId: "attempt-run-runtime-missing-screenshot",
          attemptNumber: 1,
          availability: .available,
          unavailableReason: nil,
          reference: "/tmp/runtime-console.log",
          source: "simctl.launch_console"
        ),
        WorkflowEvidenceRecord(
          kind: .screenshot,
          phase: .diagnosisRuntime,
          attemptId: "attempt-run-runtime-missing-screenshot",
          attemptNumber: 1,
          availability: .unavailable,
          unavailableReason: .executionFailed,
          reference: nil,
          source: "simctl.io.screenshot",
          detail: "simctl io screenshot exited before writing the artifact."
        ),
      ]
    )
    _ = try store.save(run)

    let workflow = makeWorkflow(store: store)
    let evidenceResult = await workflow.inspectEvidence(
      request: DiagnosisStatusRequest(runId: run.runId))

    #expect(evidenceResult.isSuccessfulInspection)
    #expect(evidenceResult.evidenceState == .partial)
    let unavailableScreenshot = evidenceResult.unavailableEvidence.first(where: {
      $0.kind == .screenshot
    })
    #expect(unavailableScreenshot?.producingWorkflowStep == "runtime diagnosis")
    #expect(
      unavailableScreenshot?.detail == "simctl io screenshot exited before writing the artifact.")
  }

  @Test("status and evidence inspection keep recovery narrative visible")
  func statusAndEvidenceInspectionKeepRecoveryNarrativeVisible() async throws {
    let tempDir = makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let store = RunStore(baseDirectory: tempDir)
    let recoveryRecord = WorkflowRecoveryRecord(
      recoveryId: "recovery-1",
      sourceAttemptId: "attempt-run-runtime-recovery",
      sourceAttemptNumber: 1,
      triggeringAttemptId: "attempt-runtime-2",
      triggeringAttemptNumber: 2,
      recoveryAttemptId: "attempt-runtime-3",
      recoveryAttemptNumber: 3,
      issue: .brokenLaunchContinuity,
      detectedIssue:
        "The app launched but did not remain running through the runtime capture window.",
      action: .resetLaunchContinuity,
      status: .succeeded,
      resumed: true,
      summary: "Recovered from broken launch continuity and resumed runtime diagnosis.",
      detail: "Reset state terminated a running app before retrying.",
      recordedAt: Date(timeIntervalSince1970: 1_743_700_552)
    )
    let run = makeRun(
      runId: "run-runtime-recovery",
      phase: .diagnosisRuntime,
      status: .succeeded,
      updatedAt: Date(timeIntervalSince1970: 1_743_700_553),
      runtimeSummary: makeRuntimeSummary(
        observedSummary: "App com.example.app was relaunched and runtime signals were captured.",
        inferredSummary:
          "Runtime inspection reached a running app state with captured console output or a confirmed live console session."
      ),
      evidence: [
        WorkflowEvidenceRecord(
          kind: .runtimeSummary,
          phase: .diagnosisRuntime,
          attemptId: "attempt-runtime-3",
          attemptNumber: 3,
          availability: .available,
          unavailableReason: nil,
          reference: "run_record.runtimeSummary",
          source: "xcforge.diagnosis_runtime.summary"
        )
      ],
      recoveryHistory: [recoveryRecord]
    )
    _ = try store.save(run)

    let workflow = makeWorkflow(store: store)
    let statusResult = await workflow.inspect(request: DiagnosisStatusRequest(runId: run.runId))
    let evidenceResult = await workflow.inspectEvidence(
      request: DiagnosisStatusRequest(runId: run.runId))

    #expect(statusResult.isSuccessfulInspection)
    #expect(statusResult.recoveryHistory.count == 1)
    #expect(
      statusResult.recoveryHistory.first?.summary
        == "Recovered from broken launch continuity and resumed runtime diagnosis.")
    #expect(evidenceResult.isSuccessfulInspection)
    #expect(evidenceResult.recoveryHistory.count == 1)
    #expect(evidenceResult.recoveryHistory.first?.resumed == true)
  }

  @Test("missing explicit run IDs fail explicitly")
  func missingExplicitRunIDsFailExplicitly() async {
    let workflow = DiagnosisStatusWorkflow(
      loadRun: { _ in throw CocoaError(.fileNoSuchFile) },
      loadLatestActiveRun: { nil },
      loadLatestRun: { nil },
      runPath: { runId in URL(fileURLWithPath: "/tmp/\(runId).json") }
    )

    let result = await workflow.inspect(request: DiagnosisStatusRequest(runId: "missing-run"))

    #expect(result.isSuccessfulInspection == false)
    #expect(result.runId == "missing-run")
    #expect(result.phase == nil)
    #expect(result.status == nil)
    #expect(result.failure?.field == .run)
    #expect(result.failure?.classification == .notFound)
  }

  @Test("empty explicit run IDs do not fall back to another run")
  func emptyExplicitRunIDsDoNotFallBack() async throws {
    let tempDir = makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let store = RunStore(baseDirectory: tempDir)
    _ = try store.save(
      makeRun(
        runId: "run-active",
        phase: .diagnosisStart,
        status: .inProgress,
        updatedAt: Date(timeIntervalSince1970: 1_743_700_200)
      )
    )

    let workflow = makeWorkflow(store: store)
    let result = await workflow.inspect(request: DiagnosisStatusRequest(runId: "   "))

    #expect(result.isSuccessfulInspection == false)
    #expect(result.runId == "   ")
    #expect(result.failure?.field == .run)
    #expect(result.failure?.classification == .notFound)
    #expect(result.failure?.message == "Run ID must not be empty.")
  }

  @Test("empty stores report that no diagnosis runs are available")
  func emptyStoresReportUnavailableRuns() async {
    let workflow = DiagnosisStatusWorkflow(
      loadRun: { _ in throw TestFailure.unusedResolver },
      loadLatestActiveRun: { nil },
      loadLatestRun: { nil },
      runPath: { runId in URL(fileURLWithPath: "/tmp/\(runId).json") }
    )

    let result = await workflow.inspect(request: DiagnosisStatusRequest())

    #expect(result.isSuccessfulInspection == false)
    #expect(result.runId == nil)
    #expect(result.failure?.field == .run)
    #expect(result.failure?.classification == .notFound)
    #expect(result.failure?.message == "No diagnosis runs are available to inspect.")
  }

  @Test("corrupt run files are skipped when selecting the latest diagnosis run")
  func corruptRunFilesAreSkippedForDefaultSelection() async throws {
    let tempDir = makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let store = RunStore(baseDirectory: tempDir)
    _ = try store.save(
      makeRun(
        runId: "run-valid",
        phase: .diagnosisStart,
        status: .inProgress,
        updatedAt: Date(timeIntervalSince1970: 1_743_700_600)
      )
    )
    try "{not-json}".write(
      to: tempDir.appendingPathComponent("corrupt-run.json"),
      atomically: true,
      encoding: .utf8
    )

    let workflow = makeWorkflow(store: store)
    let result = await workflow.inspect(request: DiagnosisStatusRequest())

    #expect(result.isSuccessfulInspection)
    #expect(result.runId == "run-valid")
    #expect(result.status == .inProgress)
  }

  @Test("terminal canceled runs preserve their canonical status")
  func canceledRunsPreserveCanonicalStatus() async {
    let canceledRun = WorkflowRunRecord(
      runId: "run-canceled",
      workflow: .diagnosis,
      phase: .diagnosisStart,
      status: .canceled,
      createdAt: Date(timeIntervalSince1970: 1_743_417_600),
      updatedAt: Date(timeIntervalSince1970: 1_743_417_700),
      attempt: WorkflowAttemptRecord(
        attemptId: "attempt-1",
        attemptNumber: 1,
        phase: .diagnosisStart,
        startedAt: Date(timeIntervalSince1970: 1_743_417_600),
        status: .canceled
      ),
      resolvedContext: makeResolvedContext()
    )

    let workflow = DiagnosisStatusWorkflow(
      loadRun: { _ in canceledRun },
      loadLatestActiveRun: { nil },
      loadLatestRun: { nil },
      runPath: { runId in URL(fileURLWithPath: "/tmp/\(runId).json") }
    )

    let result = await workflow.inspect(request: DiagnosisStatusRequest(runId: canceledRun.runId))

    #expect(result.isSuccessfulInspection)
    #expect(result.status == .canceled)
    #expect(result.summary?.source == .start)
  }

  private func makeWorkflow(store: RunStore) -> DiagnosisStatusWorkflow {
    DiagnosisStatusWorkflow(
      loadRun: { runId in try store.load(runId: runId) },
      loadLatestActiveRun: { try store.latestActiveDiagnosisRun() },
      loadLatestRun: { try store.latestDiagnosisRun() },
      runPath: { runId in store.runFileURL(runId: runId) }
    )
  }

  private func makeRun(
    runId: String,
    phase: WorkflowPhase,
    status: WorkflowStatus,
    updatedAt: Date,
    diagnosisSummary: BuildDiagnosisSummary? = nil,
    testDiagnosisSummary: TestDiagnosisSummary? = nil,
    runtimeSummary: RuntimeDiagnosisSummary? = nil,
    resolvedContext: ResolvedWorkflowContext? = nil,
    evidence: [WorkflowEvidenceRecord] = [],
    recoveryHistory: [WorkflowRecoveryRecord] = []
  ) -> WorkflowRunRecord {
    WorkflowRunRecord(
      runId: runId,
      workflow: .diagnosis,
      phase: phase,
      status: status,
      createdAt: Date(timeIntervalSince1970: 1_743_417_600),
      updatedAt: updatedAt,
      attempt: WorkflowAttemptRecord(
        attemptId: "attempt-\(runId)",
        attemptNumber: 1,
        phase: phase,
        startedAt: Date(timeIntervalSince1970: 1_743_417_600),
        status: status
      ),
      resolvedContext: resolvedContext ?? makeResolvedContext(),
      diagnosisSummary: diagnosisSummary,
      testDiagnosisSummary: testDiagnosisSummary,
      runtimeSummary: runtimeSummary,
      recoveryHistory: recoveryHistory,
      evidence: evidence
    )
  }

  private func makeBuildSummary(observedSummary: String, inferredSummary: String)
    -> BuildDiagnosisSummary
  {
    BuildDiagnosisSummary(
      observedEvidence: ObservedBuildEvidence(
        summary: observedSummary,
        primarySignal: nil,
        additionalIssueCount: 0,
        errorCount: 1,
        warningCount: 0,
        analyzerWarningCount: 0
      ),
      inferredConclusion: InferredBuildConclusion(summary: inferredSummary),
      supportingEvidence: [
        EvidenceReference(
          kind: "xcresult", path: "/tmp/build-run.xcresult", source: "xcodebuild.result_bundle")
      ]
    )
  }

  private func makeTestSummary(observedSummary: String, inferredSummary: String)
    -> TestDiagnosisSummary
  {
    TestDiagnosisSummary(
      observedEvidence: ObservedTestEvidence(
        summary: observedSummary,
        primaryFailure: nil,
        additionalFailureCount: 0,
        totalTestCount: 8,
        failedTestCount: 0,
        passedTestCount: 8,
        skippedTestCount: 0,
        expectedFailureCount: 0
      ),
      inferredConclusion: InferredTestConclusion(summary: inferredSummary),
      supportingEvidence: [
        EvidenceReference(
          kind: "xcresult", path: "/tmp/test-run.xcresult", source: "xcodebuild.result_bundle")
      ]
    )
  }

  private func makeRuntimeSummary(observedSummary: String, inferredSummary: String)
    -> RuntimeDiagnosisSummary
  {
    RuntimeDiagnosisSummary(
      observedEvidence: ObservedRuntimeEvidence(
        summary: observedSummary,
        launchedApp: true,
        appRunning: false,
        relaunchedApp: false,
        primarySignal: RuntimeSignalSummary(
          stream: .stderr,
          message: "launchctl print stalled",
          source: "simctl.launch_console.stderr"
        ),
        additionalSignalCount: 0,
        stdoutLineCount: 1,
        stderrLineCount: 1
      ),
      inferredConclusion: InferredRuntimeConclusion(summary: inferredSummary),
      supportingEvidence: [
        EvidenceReference(
          kind: "console_log", path: "/tmp/runtime-console.log", source: "simctl.launch_console")
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

  private func makePreparedResolvedContext() -> ResolvedWorkflowContext {
    ResolvedWorkflowContext(
      project: "/tmp/App.xcodeproj",
      scheme: "App",
      simulator: "SIM-123",
      configuration: "Debug",
      app: AppContext(bundleId: "com.example.app", appPath: "/tmp/Derived/App.app"),
      simulatorPreparation: makePreparedSimulatorContext(
        requested: "iPhone 16 Pro",
        selected: "SIM-123",
        displayName: "iPhone 16 Pro",
        runtime: "iOS 18.4",
        initialState: "Booted",
        state: "Booted",
        action: .reusedBooted
      )
    )
  }

  private func makePreparedSimulatorContext(
    requested: String,
    selected: String? = nil,
    displayName: String? = nil,
    runtime: String = "iOS 18.4",
    initialState: String = "Booted",
    state: String = "Booted",
    action: WorkflowSimulatorPreparation.Action? = nil
  ) -> WorkflowSimulatorPreparation {
    let resolvedAction = action ?? (initialState == "Booted" ? .reusedBooted : .bootedForWorkflow)
    return WorkflowSimulatorPreparation(
      requested: requested,
      selected: selected ?? requested,
      displayName: displayName ?? requested,
      runtime: runtime,
      initialState: initialState,
      state: state,
      action: resolvedAction,
      summary: resolvedAction == .reusedBooted
        ? "Reused the already booted simulator target for this workflow."
        : "Booted the selected simulator target for this workflow."
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

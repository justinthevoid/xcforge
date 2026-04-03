import Foundation
import Testing
@testable import xcforgeCore

@Suite("DiagnosisRuntimeWorkflow", .serialized)
struct DiagnosisRuntimeWorkflowTests {

    @Test("successful runtime capture persists a runtime summary and console artifact")
    func successfulRuntimeCapturePersistsSummary() async throws {
        let tempDir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = RunStore(baseDirectory: tempDir)
        let fixedDate = Date(timeIntervalSince1970: 1_743_800_000)
        let run = makeRun()
        _ = try store.save(run)
        let ids = TestIDGenerator(["attempt-runtime"])

        let workflow = DiagnosisRuntimeWorkflow(
            loadRun: { runId in try store.load(runId: runId) },
            persistRun: { run in try store.update(run) },
            resolveSimulator: { simulator in
                #expect(simulator == "SIM-123")
                return simulator
            },
            captureRuntime: { simulatorUDID, bundleId in
                #expect(simulatorUDID == "SIM-123")
                #expect(bundleId == "com.example.app")
                return ConsoleTools.RuntimeSignalCapture(
                    relaunchedApp: true,
                    stdout: ["com.example.app: 12345", "Application ready"],
                    stderr: [],
                    isRunning: true,
                    combinedText: "com.example.app: 12345\nApplication ready"
                )
            },
            captureScreenshot: { _, _ in
                ScreenshotTools.WorkflowCaptureResult(
                    availability: .available,
                    unavailableReason: nil,
                    reference: nil,
                    source: "test.unused",
                    detail: nil
                )
            },
            artifactURL: { runId, attemptId, name, ext in
                store.evidenceFileURL(runId: runId, attemptId: attemptId, name: name, ext: ext)
            },
            now: { fixedDate },
            makeID: { ids.next() }
        )

        let result = await workflow.diagnose(request: DiagnosisRuntimeRequest(runId: run.runId))

        #expect(result.isSuccessfulDiagnosis)
        #expect(result.summary?.observedEvidence.launchedApp == true)
        #expect(result.summary?.observedEvidence.appRunning == true)
        #expect(result.summary?.observedEvidence.relaunchedApp == true)
        #expect(result.summary?.observedEvidence.stdoutLineCount == 2)
        #expect(result.summary?.supportingEvidence.first?.source == "simctl.launch_console")

        let persisted = try store.load(runId: run.runId)
        #expect(persisted.phase == .diagnosisRuntime)
        #expect(persisted.status == .succeeded)
        #expect(persisted.updatedAt == fixedDate)
        #expect(persisted.attempt.attemptId == "attempt-runtime")
        #expect(persisted.attempt.attemptNumber == 2)
        #expect(persisted.runtimeSummary == result.summary)
        #expect(persisted.attemptHistory.count == 2)
        #expect(persisted.attemptHistory.last?.phase == .diagnosisRuntime)
        #expect(persisted.evidence.contains(where: { $0.kind == .runtimeSummary && $0.availability == .available }))
        let logRecord = try #require(persisted.evidence.first(where: { $0.kind == .consoleLog }))
        #expect(logRecord.availability == .available)
        let logPath = try #require(logRecord.reference)
        let savedLog = try String(contentsOfFile: logPath)
        #expect(savedLog.contains("Application ready"))
    }

    @Test("runtime launch failures persist failed state and unavailable runtime evidence")
    func runtimeLaunchFailuresPersistFailedState() async throws {
        let tempDir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = RunStore(baseDirectory: tempDir)
        let run = makeRun(runId: "run-runtime-failed")
        _ = try store.save(run)
        let ids = TestIDGenerator(["attempt-runtime-failed"])

        let workflow = DiagnosisRuntimeWorkflow(
            loadRun: { runId in try store.load(runId: runId) },
            persistRun: { run in try store.update(run) },
            resolveSimulator: { $0 },
            captureRuntime: { _, _ in
                throw ResolverError("Simulator runtime services are unavailable")
            },
            captureScreenshot: { _, _ in
                ScreenshotTools.WorkflowCaptureResult(
                    availability: .available,
                    unavailableReason: nil,
                    reference: nil,
                    source: "test.unused",
                    detail: nil
                )
            },
            artifactURL: { runId, attemptId, name, ext in
                store.evidenceFileURL(runId: runId, attemptId: attemptId, name: name, ext: ext)
            },
            makeID: { ids.next() }
        )

        let result = await workflow.diagnose(request: DiagnosisRuntimeRequest(runId: run.runId))

        #expect(result.status == WorkflowStatus.failed)
        #expect(result.failure?.field == .simulator)
        #expect(result.failure?.classification == .executionFailed)

        let persisted = try store.load(runId: run.runId)
        #expect(persisted.phase == .diagnosisRuntime)
        #expect(persisted.status == .failed)
        #expect(persisted.runtimeSummary == nil)
        #expect(persisted.attempt.attemptId == "attempt-runtime-failed")
        #expect(persisted.attempt.attemptNumber == 2)
        #expect(persisted.evidence == [
            WorkflowEvidenceRecord(
                kind: .runtimeSummary,
                phase: .diagnosisRuntime,
                attemptId: "attempt-runtime-failed",
                attemptNumber: 2,
                availability: .unavailable,
                unavailableReason: .executionFailed,
                reference: nil,
                source: "xcforge.diagnosis_runtime.summary",
                detail: "Runtime execution failed before xcforge could persist a runtime summary."
            ),
            WorkflowEvidenceRecord(
                kind: .consoleLog,
                phase: .diagnosisRuntime,
                attemptId: "attempt-runtime-failed",
                attemptNumber: 2,
                availability: .unavailable,
                unavailableReason: .executionFailed,
                reference: nil,
                source: "simctl.launch_console",
                detail: "Simulator runtime services are unavailable"
            ),
        ])
    }

    @Test("supported runtime interruptions retry under the same run and record recovery history")
    func supportedRuntimeInterruptionsRetryAndRecordRecoveryHistory() async throws {
        let tempDir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = RunStore(baseDirectory: tempDir)
        let run = makeRun(runId: "run-runtime-partial")
        _ = try store.save(run)
        let ids = TestIDGenerator(["attempt-runtime-partial", "attempt-runtime-recovery", "recovery-record"])
        let captureCount = RuntimeCaptureCounter()

        let workflow = DiagnosisRuntimeWorkflow(
            loadRun: { runId in try store.load(runId: runId) },
            persistRun: { run in try store.update(run) },
            resolveSimulator: { $0 },
            captureRuntime: { _, bundleId in
                if captureCount.increment() == 1 {
                    return ConsoleTools.RuntimeSignalCapture(
                        relaunchedApp: false,
                        stdout: ["\(bundleId): 9876"],
                        stderr: ["launchctl print stalled"],
                        isRunning: false,
                        combinedText: ""
                    )
                }
                return ConsoleTools.RuntimeSignalCapture(
                    relaunchedApp: true,
                    stdout: ["\(bundleId): 12345", "Application ready"],
                    stderr: [],
                    isRunning: true,
                    combinedText: "\(bundleId): 12345\nApplication ready"
                )
            },
            resetRuntimeContinuity: { simulatorUDID, bundleId, _ in
                #expect(simulatorUDID == "SIM-123")
                #expect(bundleId == "com.example.app")
                return SimTools.RuntimeContinuityReset(
                    simulatorUDID: simulatorUDID,
                    bundleId: bundleId,
                    wasRunning: true,
                    sessionCleared: true
                )
            },
            captureScreenshot: { _, _ in
                ScreenshotTools.WorkflowCaptureResult(
                    availability: .available,
                    unavailableReason: nil,
                    reference: nil,
                    source: "test.unused",
                    detail: nil
                )
            },
            artifactURL: { runId, attemptId, name, ext in
                store.evidenceFileURL(runId: runId, attemptId: attemptId, name: name, ext: ext)
            },
            makeID: { ids.next() }
        )

        let result = await workflow.diagnose(request: DiagnosisRuntimeRequest(runId: run.runId))

        #expect(result.status == .succeeded)
        #expect(result.failure == nil)
        #expect(result.summary?.observedEvidence.appRunning == true)
        #expect(result.recoveryHistory.count == 1)
        #expect(result.recoveryHistory.first?.issue == .brokenLaunchContinuity)
        #expect(result.recoveryHistory.first?.recoveryAttemptId == "attempt-runtime-recovery")

        let persisted = try store.load(runId: run.runId)
        #expect(persisted.phase == .diagnosisRuntime)
        #expect(persisted.status == .succeeded)
        #expect(persisted.attempt.attemptId == "attempt-runtime-recovery")
        #expect(persisted.attempt.attemptNumber == 3)
        #expect(persisted.recoveryHistory.count == 1)
        #expect(persisted.attemptHistory.count == 3)
        let hasInitialEvidence = persisted.evidence.contains(where: { $0.attemptId == "attempt-runtime-partial" })
        let hasRecoveredConsoleLog = persisted.evidence.contains(where: {
            $0.attemptId == "attempt-runtime-recovery"
                && $0.kind == .consoleLog
                && $0.availability == .available
        })
        #expect(hasInitialEvidence)
        #expect(hasRecoveredConsoleLog)
    }

    @Test("stale simulator continuity uses the narrow supported recovery catalog")
    func staleSimulatorContinuityRetriesAndRecordsRecoveryHistory() async throws {
        let tempDir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = RunStore(baseDirectory: tempDir)
        let run = makeRun(runId: "run-runtime-stale-session")
        _ = try store.save(run)
        let ids = TestIDGenerator(["attempt-runtime-stale", "attempt-runtime-stale-recovery", "recovery-record-stale"])
        let captureCount = RuntimeCaptureCounter()

        let workflow = DiagnosisRuntimeWorkflow(
            loadRun: { runId in try store.load(runId: runId) },
            persistRun: { run in try store.update(run) },
            resolveSimulator: { $0 },
            captureRuntime: { _, bundleId in
                if captureCount.increment() == 1 {
                    return ConsoleTools.RuntimeSignalCapture(
                        relaunchedApp: false,
                        stdout: ["\(bundleId): 9876"],
                        stderr: ["WDA session stale on this simulator"],
                        isRunning: false,
                        combinedText: ""
                    )
                }
                return ConsoleTools.RuntimeSignalCapture(
                    relaunchedApp: false,
                    stdout: ["\(bundleId): 12345", "Application ready"],
                    stderr: [],
                    isRunning: true,
                    combinedText: "\(bundleId): 12345\nApplication ready"
                )
            },
            resetRuntimeContinuity: { simulatorUDID, bundleId, _ in
                SimTools.RuntimeContinuityReset(
                    simulatorUDID: simulatorUDID,
                    bundleId: bundleId,
                    wasRunning: false,
                    sessionCleared: true
                )
            },
            captureScreenshot: { _, _ in
                ScreenshotTools.WorkflowCaptureResult(
                    availability: .available,
                    unavailableReason: nil,
                    reference: nil,
                    source: "test.unused",
                    detail: nil
                )
            },
            artifactURL: { runId, attemptId, name, ext in
                store.evidenceFileURL(runId: runId, attemptId: attemptId, name: name, ext: ext)
            },
            makeID: { ids.next() }
        )

        let result = await workflow.diagnose(request: DiagnosisRuntimeRequest(runId: run.runId))

        #expect(result.status == .succeeded)
        #expect(result.recoveryHistory.count == 1)
        #expect(result.recoveryHistory.first?.issue == .staleSimulatorState)
        #expect(result.recoveryHistory.first?.resumed == true)
    }

    @Test("failed recovery keeps initial partial evidence but records the recovery attempt as failed")
    func failedRecoveryRecordsFailedAttemptAndPreservesPartialEvidence() async throws {
        let tempDir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = RunStore(baseDirectory: tempDir)
        let run = makeRun(runId: "run-runtime-recovery-failed")
        _ = try store.save(run)
        let ids = TestIDGenerator(["attempt-runtime-partial", "attempt-runtime-recovery", "recovery-record"])
        let captureCount = RuntimeCaptureCounter()

        let workflow = DiagnosisRuntimeWorkflow(
            loadRun: { runId in try store.load(runId: runId) },
            persistRun: { run in try store.update(run) },
            resolveSimulator: { $0 },
            captureRuntime: { _, bundleId in
                if captureCount.increment() == 1 {
                    return ConsoleTools.RuntimeSignalCapture(
                        relaunchedApp: false,
                        stdout: ["\(bundleId): 9876"],
                        stderr: ["launchctl print stalled"],
                        isRunning: false,
                        combinedText: ""
                    )
                }
                throw ResolverError("launchctl continuity probe failed")
            },
            resetRuntimeContinuity: { simulatorUDID, bundleId, _ in
                SimTools.RuntimeContinuityReset(
                    simulatorUDID: simulatorUDID,
                    bundleId: bundleId,
                    wasRunning: true,
                    sessionCleared: false
                )
            },
            captureScreenshot: { _, _ in
                ScreenshotTools.WorkflowCaptureResult(
                    availability: .available,
                    unavailableReason: nil,
                    reference: nil,
                    source: "test.unused",
                    detail: nil
                )
            },
            artifactURL: { runId, attemptId, name, ext in
                store.evidenceFileURL(runId: runId, attemptId: attemptId, name: name, ext: ext)
            },
            makeID: { ids.next() }
        )

        let result = await workflow.diagnose(request: DiagnosisRuntimeRequest(runId: run.runId))

        #expect(result.status == .partial)
        #expect(result.summary?.observedEvidence.appRunning == false)
        #expect(result.failure?.message == "launchctl continuity probe failed")
        let recovery = try #require(result.recoveryHistory.first)
        #expect(recovery.status == .failed)
        #expect(recovery.resumed == false)
        #expect(recovery.detail?.contains("could not be confirmed cleared") == true)

        let persisted = try store.load(runId: run.runId)
        #expect(persisted.status == .partial)
        #expect(persisted.attempt.status == .failed)
        #expect(persisted.runtimeSummary?.observedEvidence.appRunning == false)
        let recoverySnapshot = try #require(persisted.attemptSnapshot(forAttemptId: "attempt-runtime-recovery", phase: .diagnosisRuntime))
        #expect(recoverySnapshot.status == .failed)
        #expect(recoverySnapshot.runtimeSummary == nil)
    }

    @Test("runtime persistence timestamps completion instead of attempt start")
    func runtimePersistenceUsesCompletionTimestamp() async throws {
        let tempDir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = RunStore(baseDirectory: tempDir)
        let run = makeRun(runId: "run-runtime-timestamp")
        _ = try store.save(run)
        let ids = TestIDGenerator(["attempt-runtime"])
        let dates = DateSequence([
            Date(timeIntervalSince1970: 1_743_800_000),
            Date(timeIntervalSince1970: 1_743_800_120),
        ])

        let workflow = DiagnosisRuntimeWorkflow(
            loadRun: { runId in try store.load(runId: runId) },
            persistRun: { run in try store.update(run) },
            resolveSimulator: { $0 },
            captureRuntime: { _, bundleId in
                ConsoleTools.RuntimeSignalCapture(
                    relaunchedApp: false,
                    stdout: ["\(bundleId): 12345", "Application ready"],
                    stderr: [],
                    isRunning: true,
                    combinedText: "\(bundleId): 12345\nApplication ready"
                )
            },
            captureScreenshot: { _, _ in
                ScreenshotTools.WorkflowCaptureResult(
                    availability: .available,
                    unavailableReason: nil,
                    reference: nil,
                    source: "test.unused",
                    detail: nil
                )
            },
            artifactURL: { runId, attemptId, name, ext in
                store.evidenceFileURL(runId: runId, attemptId: attemptId, name: name, ext: ext)
            },
            now: { dates.next() },
            makeID: { ids.next() }
        )

        let result = await workflow.diagnose(request: DiagnosisRuntimeRequest(runId: run.runId))

        #expect(result.status == .succeeded)
        let persisted = try store.load(runId: run.runId)
        #expect(persisted.attempt.startedAt == Date(timeIntervalSince1970: 1_743_800_000))
        #expect(persisted.updatedAt == Date(timeIntervalSince1970: 1_743_800_120))
    }

    @Test("requested screenshot capture persists a screenshot artifact for the runtime attempt")
    func requestedScreenshotCapturePersistsArtifact() async throws {
        let tempDir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = RunStore(baseDirectory: tempDir)
        let run = makeRun(runId: "run-runtime-screenshot")
        _ = try store.save(run)
        let runtimeAttemptId = "attempt-runtime-screenshot"

        let expectedScreenshot = store.evidenceFileURL(
            runId: run.runId,
            attemptId: runtimeAttemptId,
            name: "runtime-screenshot",
            ext: "png"
        ).path

        let workflow = DiagnosisRuntimeWorkflow(
            loadRun: { runId in try store.load(runId: runId) },
            persistRun: { run in try store.update(run) },
            resolveSimulator: { $0 },
            captureRuntime: { _, bundleId in
                ConsoleTools.RuntimeSignalCapture(
                    relaunchedApp: true,
                    stdout: ["\(bundleId): 1234", "Application ready"],
                    stderr: [],
                    isRunning: true,
                    combinedText: "\(bundleId): 1234\nApplication ready"
                )
            },
            captureScreenshot: { _, outputURL in
                try? Data("png".utf8).write(to: outputURL, options: .atomic)
                return ScreenshotTools.WorkflowCaptureResult(
                    availability: .available,
                    unavailableReason: nil,
                    reference: outputURL.path,
                    source: "simctl.io.screenshot",
                    detail: nil
                )
            },
            artifactURL: { runId, attemptId, name, ext in
                store.evidenceFileURL(runId: runId, attemptId: attemptId, name: name, ext: ext)
            },
            makeID: { runtimeAttemptId }
        )

        let result = await workflow.diagnose(
            request: DiagnosisRuntimeRequest(
                runId: run.runId,
                captureScreenshot: true
            )
        )

        let resultScreenshotEvidence = result.evidence.first(where: { $0.kind == .screenshot })
        let summaryContainsScreenshot = result.summary?.supportingEvidence.contains(where: {
            $0.kind == "screenshot" && $0.path == expectedScreenshot
        })
        #expect(result.status == WorkflowStatus.succeeded)
        #expect(summaryContainsScreenshot == true)
        #expect(resultScreenshotEvidence?.reference == expectedScreenshot)
        #expect(resultScreenshotEvidence?.availability == .available)

        let persisted = try store.load(runId: run.runId)
        let persistedScreenshotEvidence = persisted.evidence.first(where: { $0.kind == .screenshot })
        #expect(persistedScreenshotEvidence?.reference == expectedScreenshot)
        #expect(persistedScreenshotEvidence?.availability == .available)
        #expect(persisted.attempt.attemptId == runtimeAttemptId)
        #expect(FileManager.default.fileExists(atPath: expectedScreenshot))
    }

    @Test("unsupported requested screenshot capture downgrades runtime success to partial")
    func unsupportedRequestedScreenshotCaptureIsPartial() async throws {
        let tempDir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = RunStore(baseDirectory: tempDir)
        let run = makeRun(runId: "run-runtime-screenshot-unsupported")
        _ = try store.save(run)
        let ids = TestIDGenerator(["attempt-runtime-screenshot-unsupported"])

        let workflow = DiagnosisRuntimeWorkflow(
            loadRun: { runId in try store.load(runId: runId) },
            persistRun: { run in try store.update(run) },
            resolveSimulator: { $0 },
            captureRuntime: { _, bundleId in
                ConsoleTools.RuntimeSignalCapture(
                    relaunchedApp: false,
                    stdout: ["\(bundleId): 5555", "Application ready"],
                    stderr: [],
                    isRunning: true,
                    combinedText: "\(bundleId): 5555\nApplication ready"
                )
            },
            captureScreenshot: { _, _ in
                ScreenshotTools.WorkflowCaptureResult(
                    availability: .unavailable,
                    unavailableReason: .unsupported,
                    reference: nil,
                    source: "simctl.io.screenshot",
                    detail: "Screen recording permission is unavailable for this simulator screenshot."
                )
            },
            artifactURL: { runId, attemptId, name, ext in
                store.evidenceFileURL(runId: runId, attemptId: attemptId, name: name, ext: ext)
            },
            makeID: { ids.next() }
        )

        let result = await workflow.diagnose(
            request: DiagnosisRuntimeRequest(
                runId: run.runId,
                captureScreenshot: true
            )
        )

        #expect(result.status == .partial)
        #expect(result.failure?.classification == .unsupportedContext)
        #expect(result.failure?.message == "Screen recording permission is unavailable for this simulator screenshot.")
        let unavailableScreenshotEvidence = result.evidence.first(where: { $0.kind == .screenshot })
        #expect(unavailableScreenshotEvidence?.availability == .unavailable)
        #expect(unavailableScreenshotEvidence?.unavailableReason == .unsupported)

        let persisted = try store.load(runId: run.runId)
        let screenshotRecord = try #require(persisted.evidence.first(where: { $0.kind == .screenshot }))
        #expect(screenshotRecord.availability == .unavailable)
        #expect(screenshotRecord.unavailableReason == .unsupported)
    }

    @Test("requested screenshot execution failure keeps runtime result partial and records the gap")
    func requestedScreenshotExecutionFailureIsPartial() async throws {
        let tempDir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = RunStore(baseDirectory: tempDir)
        let run = makeRun(runId: "run-runtime-screenshot-partial")
        _ = try store.save(run)
        let ids = TestIDGenerator(["attempt-runtime-screenshot-partial"])

        let workflow = DiagnosisRuntimeWorkflow(
            loadRun: { runId in try store.load(runId: runId) },
            persistRun: { run in try store.update(run) },
            resolveSimulator: { $0 },
            captureRuntime: { _, bundleId in
                ConsoleTools.RuntimeSignalCapture(
                    relaunchedApp: false,
                    stdout: ["\(bundleId): 2222", "Application ready"],
                    stderr: [],
                    isRunning: true,
                    combinedText: "\(bundleId): 2222\nApplication ready"
                )
            },
            captureScreenshot: { _, _ in
                ScreenshotTools.WorkflowCaptureResult(
                    availability: .unavailable,
                    unavailableReason: .executionFailed,
                    reference: nil,
                    source: "simctl.io.screenshot",
                    detail: "simctl io screenshot exited before writing the artifact."
                )
            },
            artifactURL: { runId, attemptId, name, ext in
                store.evidenceFileURL(runId: runId, attemptId: attemptId, name: name, ext: ext)
            },
            makeID: { ids.next() }
        )

        let result = await workflow.diagnose(
            request: DiagnosisRuntimeRequest(
                runId: run.runId,
                captureScreenshot: true
            )
        )

        #expect(result.status == .partial)
        #expect(result.failure?.classification == .executionFailed)
        let screenshotEvidence = result.evidence.first(where: { $0.kind == .screenshot })
        #expect(screenshotEvidence?.availability == .unavailable)
        #expect(screenshotEvidence?.unavailableReason == .executionFailed)
    }

    @Test("unsupported screenshot capture without launch signal returns unsupported runtime state")
    func unsupportedScreenshotWithoutLaunchSignalReturnsUnsupported() async throws {
        let tempDir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = RunStore(baseDirectory: tempDir)
        let run = makeRun(runId: "run-runtime-screenshot-unsupported-no-launch")
        _ = try store.save(run)
        let ids = TestIDGenerator(["attempt-runtime-screenshot-unsupported-no-launch"])

        let workflow = DiagnosisRuntimeWorkflow(
            loadRun: { runId in try store.load(runId: runId) },
            persistRun: { run in try store.update(run) },
            resolveSimulator: { $0 },
            captureRuntime: { _, _ in
                ConsoleTools.RuntimeSignalCapture(
                    relaunchedApp: false,
                    stdout: [],
                    stderr: [],
                    isRunning: false,
                    combinedText: ""
                )
            },
            captureScreenshot: { _, _ in
                ScreenshotTools.WorkflowCaptureResult(
                    availability: .unavailable,
                    unavailableReason: .unsupported,
                    reference: nil,
                    source: "simctl.io.screenshot",
                    detail: "Screen recording permission is unavailable for this simulator screenshot."
                )
            },
            artifactURL: { runId, attemptId, name, ext in
                store.evidenceFileURL(runId: runId, attemptId: attemptId, name: name, ext: ext)
            },
            makeID: { ids.next() }
        )

        let result = await workflow.diagnose(
            request: DiagnosisRuntimeRequest(
                runId: run.runId,
                captureScreenshot: true
            )
        )

        #expect(result.status == .unsupported)
        #expect(result.failure?.classification == .unsupportedContext)
    }

    @Test("simulator resolution failures persist runtime failure state")
    func simulatorResolutionFailuresPersistRuntimeFailureState() async throws {
        let tempDir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = RunStore(baseDirectory: tempDir)
        let run = makeRun(runId: "run-runtime-sim-resolution")
        _ = try store.save(run)
        let ids = TestIDGenerator(["attempt-runtime-sim-resolution"])

        let workflow = DiagnosisRuntimeWorkflow(
            loadRun: { runId in try store.load(runId: runId) },
            persistRun: { run in try store.update(run) },
            resolveSimulator: { _ in
                throw ResolverError("Simulator device is unavailable")
            },
            captureRuntime: { _, _ in
                throw LocalTestFailure.unusedResolver
            },
            captureScreenshot: { _, _ in
                ScreenshotTools.WorkflowCaptureResult(
                    availability: .available,
                    unavailableReason: nil,
                    reference: nil,
                    source: "test.unused",
                    detail: nil
                )
            },
            artifactURL: { runId, attemptId, name, ext in
                store.evidenceFileURL(runId: runId, attemptId: attemptId, name: name, ext: ext)
            },
            makeID: { ids.next() }
        )

        let result = await workflow.diagnose(request: DiagnosisRuntimeRequest(runId: run.runId))

        #expect(result.status == WorkflowStatus.failed)
        #expect(result.failure?.field == .simulator)
        #expect(result.failure?.classification == .executionFailed)

        let persisted = try store.load(runId: run.runId)
        #expect(persisted.phase == .diagnosisRuntime)
        #expect(persisted.status == .failed)
        #expect(persisted.runtimeSummary == nil)
    }

    @Test("runtime cannot be rerun once diagnosis_runtime is already persisted")
    func repeatedRuntimeRunsFailExplicitly() async throws {
        let tempDir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = RunStore(baseDirectory: tempDir)
        let runtimeRun = WorkflowRunRecord(
            runId: "run-runtime-repeat",
            workflow: .diagnosis,
            phase: .diagnosisRuntime,
            status: .partial,
            createdAt: Date(timeIntervalSince1970: 1_743_417_600),
            updatedAt: Date(timeIntervalSince1970: 1_743_417_700),
            attempt: WorkflowAttemptRecord(
                attemptId: "attempt-1",
                attemptNumber: 1,
                phase: .diagnosisRuntime,
                startedAt: Date(timeIntervalSince1970: 1_743_417_700),
                status: .partial
            ),
            resolvedContext: ResolvedWorkflowContext(
                project: "/tmp/App.xcodeproj",
                scheme: "App",
                simulator: "SIM-123",
                configuration: "Debug",
                app: AppContext(bundleId: "com.example.app", appPath: "/tmp/Derived/App.app")
            )
        )
        _ = try store.save(runtimeRun)

        let workflow = DiagnosisRuntimeWorkflow(
            loadRun: { runId in try store.load(runId: runId) },
            persistRun: { run in try store.update(run) },
            resolveSimulator: { _ in throw LocalTestFailure.unusedResolver },
            captureRuntime: { _, _ in throw LocalTestFailure.unusedResolver },
            captureScreenshot: { _, _ in
                ScreenshotTools.WorkflowCaptureResult(
                    availability: .available,
                    unavailableReason: nil,
                    reference: nil,
                    source: "test.unused",
                    detail: nil
                )
            },
            artifactURL: { runId, attemptId, name, ext in
                store.evidenceFileURL(runId: runId, attemptId: attemptId, name: name, ext: ext)
            }
        )

        let result = await workflow.diagnose(request: DiagnosisRuntimeRequest(runId: runtimeRun.runId))

        #expect(result.status == WorkflowStatus.failed)
        #expect(result.failure?.field == .run)
        #expect(result.failure?.classification == .invalidRunState)

        let persisted = try store.load(runId: runtimeRun.runId)
        #expect(persisted.phase == .diagnosisRuntime)
        #expect(persisted.status == .partial)
        #expect(persisted.attempt.attemptId == "attempt-1")
    }

    private func makeRun(runId: String = "run-runtime") -> WorkflowRunRecord {
        WorkflowRunRecord(
            runId: runId,
            workflow: .diagnosis,
            phase: .diagnosisStart,
            status: .inProgress,
            createdAt: Date(timeIntervalSince1970: 1_743_417_600),
            updatedAt: Date(timeIntervalSince1970: 1_743_417_600),
            attempt: WorkflowAttemptRecord(
                attemptId: "attempt-1",
                attemptNumber: 1,
                phase: .diagnosisStart,
                startedAt: Date(timeIntervalSince1970: 1_743_417_600),
                status: .inProgress
            ),
            resolvedContext: ResolvedWorkflowContext(
                project: "/tmp/App.xcodeproj",
                scheme: "App",
                simulator: "SIM-123",
                configuration: "Debug",
                app: AppContext(bundleId: "com.example.app", appPath: "/tmp/Derived/App.app")
            )
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

private enum LocalTestFailure: Error {
    case unusedResolver
}

private final class TestIDGenerator: @unchecked Sendable {
    private let ids: [String]
    private var index = 0
    private let lock = NSLock()

    init(_ ids: [String]) {
        self.ids = ids
    }

    func next() -> String {
        lock.lock()
        defer { lock.unlock() }
        defer { index += 1 }
        guard index < ids.count else {
            return ids.last ?? "unused-id"
        }
        return ids[index]
    }
}

private final class RuntimeCaptureCounter: @unchecked Sendable {
    private var count = 0
    private let lock = NSLock()

    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return count
    }
}

private final class DateSequence: @unchecked Sendable {
    private let dates: [Date]
    private var index = 0
    private let lock = NSLock()

    init(_ dates: [Date]) {
        self.dates = dates
    }

    func next() -> Date {
        lock.lock()
        defer { lock.unlock() }
        defer { index += 1 }
        guard index < dates.count else {
            return dates.last ?? Date(timeIntervalSince1970: 0)
        }
        return dates[index]
    }
}

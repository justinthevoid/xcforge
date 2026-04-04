import Foundation
import Testing
@testable import XCForgeKit

@Suite("DiagnosisBuildWorkflow", .serialized)
struct DiagnosisBuildWorkflowTests {

    @Test("failing build persists a compact primary failure summary")
    func failingBuildPersistsSummary() async throws {
        let tempDir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = RunStore(baseDirectory: tempDir)
        let fixedDate = Date(timeIntervalSince1970: 1_743_500_000)
        let run = makeRun()
        _ = try store.save(run)
        let xcresultURL = tempDir.appendingPathComponent("build-run.xcresult", isDirectory: true)
        try FileManager.default.createDirectory(at: xcresultURL, withIntermediateDirectories: true, attributes: nil)

        let workflow = DiagnosisBuildWorkflow(
            loadRun: { runId in try store.load(runId: runId) },
            persistRun: { run in try store.update(run) },
            executeBuild: { _ in
                TestTools.BuildDiagnosisExecution(
                    succeeded: false,
                    elapsed: "8.4",
                    xcresultPath: xcresultURL.path,
                    issues: [
                        TestTools.BuildIssueObservation(
                            severity: .error,
                            message: "Cannot find 'WidgetView' in scope",
                            location: SourceLocation(filePath: "/tmp/App/Feature.swift", line: 42, column: 9),
                            source: "xcresult.errors"
                        ),
                        TestTools.BuildIssueObservation(
                            severity: .error,
                            message: "Cannot find 'WidgetView' in scope",
                            location: SourceLocation(filePath: "/tmp/App/Feature.swift", line: 42, column: 9),
                            source: "xcresult.errors"
                        ),
                        TestTools.BuildIssueObservation(
                            severity: .error,
                            message: "Type-checking failed after previous error",
                            location: SourceLocation(filePath: "/tmp/App/Feature.swift", line: 43, column: 1),
                            source: "xcresult.errors"
                        ),
                    ],
                    errorCount: 3,
                    warningCount: 0,
                    analyzerWarningCount: 0,
                    destinationDeviceName: "iPhone 16",
                    destinationOSVersion: "18.0"
                )
            },
            now: { fixedDate }
        )

        let result = await workflow.diagnose(request: DiagnosisBuildRequest(runId: run.runId))

        #expect(result.status == .failed)
        #expect(result.summary?.observedEvidence.primarySignal?.message == "Cannot find 'WidgetView' in scope")
        #expect(result.summary?.observedEvidence.primarySignal?.location == SourceLocation(
            filePath: "/tmp/App/Feature.swift",
            line: 42,
            column: 9
        ))
        #expect(result.summary?.observedEvidence.additionalIssueCount == 1)
        #expect(result.summary?.supportingEvidence == [
            EvidenceReference(kind: "xcresult", path: xcresultURL.path, source: "xcodebuild.result_bundle")
        ])
        #expect(result.summary?.inferredConclusion?.summary.contains("Cannot find 'WidgetView' in scope") == true)

        let persisted = try store.load(runId: run.runId)
        #expect(persisted.phase == .diagnosisBuild)
        #expect(persisted.status == .failed)
        #expect(persisted.updatedAt == fixedDate)
        #expect(persisted.diagnosisSummary == result.summary)
        #expect(persisted.environmentPreflight?.status == .passed)
        #expect(persisted.attemptHistory.count == 2)
        #expect(persisted.attemptHistory.first?.phase == .diagnosisStart)
        #expect(persisted.attemptHistory.last?.phase == .diagnosisBuild)
        #expect(persisted.evidence == [
            WorkflowEvidenceRecord(
                kind: .buildSummary,
                phase: .diagnosisBuild,
                attemptId: "attempt-1",
                attemptNumber: 1,
                availability: .available,
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
                reference: xcresultURL.path,
                source: "xcodebuild.result_bundle"
            ),
            WorkflowEvidenceRecord(
                kind: .stderr,
                phase: .diagnosisBuild,
                attemptId: "attempt-1",
                attemptNumber: 1,
                availability: .unavailable,
                unavailableReason: .notCaptured,
                reference: nil,
                source: "xcodebuild.stderr",
                detail: "No stderr artifact was captured for this build diagnosis phase."
            ),
        ])
    }

    @Test("successful build reports that no failure signal was found")
    func successfulBuildReportsNoFailureSignal() async throws {
        let tempDir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = RunStore(baseDirectory: tempDir)
        let run = makeRun()
        _ = try store.save(run)
        let xcresultURL = tempDir.appendingPathComponent("success.xcresult", isDirectory: true)
        try FileManager.default.createDirectory(at: xcresultURL, withIntermediateDirectories: true, attributes: nil)

        let workflow = DiagnosisBuildWorkflow(
            loadRun: { runId in try store.load(runId: runId) },
            persistRun: { run in try store.update(run) },
            executeBuild: { _ in
                TestTools.BuildDiagnosisExecution(
                    succeeded: true,
                    elapsed: "5.1",
                    xcresultPath: xcresultURL.path,
                    issues: [],
                    errorCount: 0,
                    warningCount: 0,
                    analyzerWarningCount: 0,
                    destinationDeviceName: "iPhone 16",
                    destinationOSVersion: "18.0"
                )
            }
        )

        let result = await workflow.diagnose(request: DiagnosisBuildRequest(runId: run.runId))

        #expect(result.isSuccessfulDiagnosis)
        #expect(result.summary?.observedEvidence.primarySignal == nil)
        #expect(result.summary?.inferredConclusion?.summary == "No build failure signal was found for this run.")

        let persisted = try store.load(runId: run.runId)
        #expect(persisted.status == .succeeded)
        #expect(persisted.phase == .diagnosisBuild)
        #expect(persisted.environmentPreflight?.status == .passed)
        let hasBuildSummaryEvidence = persisted.evidence.contains(where: { record in
            record.kind == .buildSummary && record.availability == .available
        })
        let hasXCResultEvidence = persisted.evidence.contains(where: { record in
            record.kind == .xcresult
                && record.availability == .available
                && record.reference == xcresultURL.path
        })
        let hasUnavailableStderrEvidence = persisted.evidence.contains(where: { record in
            record.kind == .stderr
                && record.availability == .unavailable
                && record.unavailableReason == .notCaptured
        })
        #expect(hasBuildSummaryEvidence)
        #expect(hasXCResultEvidence)
        #expect(hasUnavailableStderrEvidence)
    }

    @Test("missing or invalid runs fail explicitly")
    func missingOrInvalidRunsFailExplicitly() async {
        let workflowMissing = DiagnosisBuildWorkflow(
            loadRun: { _ in throw CocoaError(.fileNoSuchFile) },
            persistRun: { _ in URL(fileURLWithPath: "/tmp/unused") },
            executeBuild: { _ in
                throw TestFailure.unusedResolver
            }
        )

        let missingResult = await workflowMissing.diagnose(
            request: DiagnosisBuildRequest(runId: "missing-run")
        )

        #expect(missingResult.status == .failed)
        #expect(missingResult.failure?.field == .run)
        #expect(missingResult.failure?.classification == .notFound)

        let invalidRun = WorkflowRunRecord(
            runId: "invalid-run",
            workflow: .diagnosis,
            phase: .diagnosisBuild,
            status: .failed,
            createdAt: Date(timeIntervalSince1970: 1_743_417_600),
            updatedAt: Date(timeIntervalSince1970: 1_743_417_600),
            attempt: WorkflowAttemptRecord(
                attemptId: "attempt-1",
                attemptNumber: 1,
                phase: .diagnosisBuild,
                startedAt: Date(timeIntervalSince1970: 1_743_417_600),
                status: .failed
            ),
            resolvedContext: makeResolvedContext()
        )
        let workflowInvalid = DiagnosisBuildWorkflow(
            loadRun: { _ in invalidRun },
            persistRun: { _ in URL(fileURLWithPath: "/tmp/unused") },
            executeBuild: { _ in
                throw TestFailure.unusedResolver
            }
        )

        let invalidResult = await workflowInvalid.diagnose(
            request: DiagnosisBuildRequest(runId: invalidRun.runId)
        )

        #expect(invalidResult.status == .failed)
        #expect(invalidResult.failure?.field == .run)
        #expect(invalidResult.failure?.classification == .invalidRunState)
    }

    @Test("older run records without configuration rewrite to the current schema when updated")
    func olderRunRecordsRewriteToCurrentSchemaWhenUpdated() async throws {
        let tempDir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let legacyJSON = """
        {
          "schemaVersion" : "1.0.0",
          "runId" : "legacy-run",
          "workflow" : "diagnosis",
          "phase" : "diagnosis_start",
          "status" : "in_progress",
          "createdAt" : "2025-03-31T12:00:00Z",
          "updatedAt" : "2025-03-31T12:00:00Z",
          "attempt" : {
            "attemptId" : "attempt-1",
            "attemptNumber" : 1,
            "phase" : "diagnosis_start",
            "startedAt" : "2025-03-31T12:00:00Z",
            "status" : "in_progress"
          },
          "resolvedContext" : {
            "project" : "/tmp/App.xcodeproj",
            "scheme" : "App",
            "simulator" : "SIM-123",
            "app" : {
              "bundleId" : "com.example.app",
              "appPath" : "/tmp/Derived/App.app"
            }
          }
        }
        """
        let url = tempDir.appendingPathComponent("legacy-run.json")
        try legacyJSON.write(to: url, atomically: true, encoding: .utf8)

        let store = RunStore(baseDirectory: tempDir)
        let loaded = try store.load(runId: "legacy-run")

        #expect(loaded.resolvedContext.configuration == "Debug")
        #expect(loaded.evidence.isEmpty)

        let xcresultURL = tempDir.appendingPathComponent("legacy-build.xcresult", isDirectory: true)
        try FileManager.default.createDirectory(at: xcresultURL, withIntermediateDirectories: true, attributes: nil)

        let workflow = DiagnosisBuildWorkflow(
            loadRun: { runId in try store.load(runId: runId) },
            persistRun: { run in try store.update(run) },
            executeBuild: { _ in
                TestTools.BuildDiagnosisExecution(
                    succeeded: true,
                    elapsed: "1.0",
                    xcresultPath: xcresultURL.path,
                    issues: [],
                    errorCount: 0,
                    warningCount: 0,
                    analyzerWarningCount: 0,
                    destinationDeviceName: "iPhone 16",
                    destinationOSVersion: "18.0"
                )
            }
        )

        let result = await workflow.diagnose(request: DiagnosisBuildRequest(runId: "legacy-run"))

        #expect(result.status == .succeeded)

        let persisted = try store.load(runId: "legacy-run")
        #expect(persisted.schemaVersion == WorkflowRunRecord.currentSchemaVersion)
        let hasLegacyXCResultEvidence = persisted.evidence.contains(where: { record in
            record.kind == .xcresult
                && record.availability == .available
                && record.reference == xcresultURL.path
        })
        #expect(hasLegacyXCResultEvidence)
    }

    @Test("build execution errors persist a failed run state")
    func buildExecutionErrorsPersistFailedRunState() async throws {
        let tempDir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = RunStore(baseDirectory: tempDir)
        let run = makeRun(runId: "run-build-error")
        _ = try store.save(run)

        let workflow = DiagnosisBuildWorkflow(
            loadRun: { runId in try store.load(runId: runId) },
            persistRun: { run in try store.update(run) },
            executeBuild: { _ in
                throw ResolverError("xcodebuild invocation crashed")
            }
        )

        let result = await workflow.diagnose(request: DiagnosisBuildRequest(runId: run.runId))

        #expect(result.status == .failed)
        #expect(result.failure?.field == .build)
        #expect(result.failure?.classification == .executionFailed)

        let persisted = try store.load(runId: run.runId)
        #expect(persisted.phase == .diagnosisBuild)
        #expect(persisted.status == .failed)
        #expect(persisted.diagnosisSummary == nil)
        #expect(persisted.evidence == [
            WorkflowEvidenceRecord(
                kind: .buildSummary,
                phase: .diagnosisBuild,
                attemptId: "attempt-1",
                attemptNumber: 1,
                availability: .unavailable,
                unavailableReason: .executionFailed,
                reference: nil,
                source: "xcforge.diagnosis_build.summary",
                detail: "Build execution failed before xcforge could persist a build summary."
            ),
            WorkflowEvidenceRecord(
                kind: .xcresult,
                phase: .diagnosisBuild,
                attemptId: "attempt-1",
                attemptNumber: 1,
                availability: .unavailable,
                unavailableReason: .executionFailed,
                reference: nil,
                source: "xcodebuild.result_bundle",
                detail: "Build execution failed before an xcresult artifact was captured."
            ),
            WorkflowEvidenceRecord(
                kind: .stderr,
                phase: .diagnosisBuild,
                attemptId: "attempt-1",
                attemptNumber: 1,
                availability: .unavailable,
                unavailableReason: .executionFailed,
                reference: nil,
                source: "xcodebuild.stderr",
                detail: "Build execution failed before a stderr artifact was captured."
            ),
        ])
    }

    private func makeRun(runId: String = "run-123") -> WorkflowRunRecord {
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
            resolvedContext: makeResolvedContext(),
            environmentPreflight: WorkflowEnvironmentPreflight(
                status: .passed,
                summary: "Environment preflight passed for the resolved diagnosis context.",
                checks: [
                    WorkflowEnvironmentCheck(
                        kind: .tooling,
                        field: .tooling,
                        status: .passed,
                        message: "Required local Apple developer tooling is available."
                    )
                ],
                validatedAt: Date(timeIntervalSince1970: 1_743_417_600)
            )
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

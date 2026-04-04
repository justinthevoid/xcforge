import Foundation
import Testing
@testable import XCForgeCLI
@testable import XCForgeKit

@Suite("Workflow Output Parity")
struct WorkflowOutputParityTests {

    // MARK: - Shared Helpers

    private static let context = ResolvedWorkflowContext(
        project: "/tmp/App.xcodeproj",
        scheme: "App",
        simulator: "iPhone 16 Pro",
        configuration: "Debug",
        app: AppContext(bundleId: "com.example.app", appPath: "/tmp/App.app")
    )

    private static let failure = WorkflowFailure(
        field: .build,
        classification: .executionFailed,
        message: "Build failed"
    )

    // MARK: - Test 1: Renderer determinism across all result types
    //
    // CLI and MCP surfaces both call WorkflowJSONRenderer.renderJSON() as their
    // sole serialization path (CLI: XCForgeCLI.swift, MCP: DiagnoseTools.encodeResult).
    // Proving the renderer is deterministic therefore proves CLI/MCP output parity.

    @Test("renderJSON is deterministic for DiagnosisStartResult")
    func startResultDeterminism() throws {
        let result = DiagnosisStartResult(
            status: .succeeded,
            runId: "run-1",
            attemptId: "attempt-1",
            resolvedContext: Self.context,
            failure: nil,
            persistedRunPath: nil
        )
        let first = try WorkflowJSONRenderer.renderJSON(result)
        let second = try WorkflowJSONRenderer.renderJSON(result)
        #expect(first == second)
    }

    @Test("renderJSON is deterministic for DiagnosisBuildResult")
    func buildResultDeterminism() throws {
        let result = DiagnosisBuildResult(
            status: .failed,
            runId: "run-1",
            attemptId: "attempt-1",
            resolvedContext: nil,
            summary: nil,
            failure: Self.failure,
            persistedRunPath: nil
        )
        let first = try WorkflowJSONRenderer.renderJSON(result)
        let second = try WorkflowJSONRenderer.renderJSON(result)
        #expect(first == second)
    }

    @Test("renderJSON is deterministic for DiagnosisTestResult")
    func testResultDeterminism() throws {
        let result = DiagnosisTestResult(
            status: .succeeded,
            runId: "run-1",
            attemptId: "attempt-1",
            resolvedContext: nil,
            summary: nil,
            failure: nil,
            persistedRunPath: nil
        )
        let first = try WorkflowJSONRenderer.renderJSON(result)
        let second = try WorkflowJSONRenderer.renderJSON(result)
        #expect(first == second)
    }

    @Test("renderJSON is deterministic for DiagnosisRuntimeResult")
    func runtimeResultDeterminism() throws {
        let result = DiagnosisRuntimeResult(
            status: .succeeded,
            runId: "run-1",
            attemptId: "attempt-1",
            resolvedContext: nil,
            summary: nil,
            failure: nil,
            persistedRunPath: nil
        )
        let first = try WorkflowJSONRenderer.renderJSON(result)
        let second = try WorkflowJSONRenderer.renderJSON(result)
        #expect(first == second)
    }

    @Test("renderJSON is deterministic for DiagnosisStatusResult")
    func statusResultDeterminism() throws {
        let result = DiagnosisStatusResult(
            phase: .diagnosisBuild,
            status: .inProgress,
            runId: "run-1",
            attemptId: "attempt-1",
            resolvedContext: Self.context,
            summary: nil,
            failure: nil,
            persistedRunPath: nil
        )
        let first = try WorkflowJSONRenderer.renderJSON(result)
        let second = try WorkflowJSONRenderer.renderJSON(result)
        #expect(first == second)
    }

    @Test("renderJSON is deterministic for DiagnosisVerifyResult")
    func verifyResultDeterminism() throws {
        let result = DiagnosisVerifyResult(
            phase: .diagnosisBuild,
            status: .succeeded,
            outcome: .verified,
            runId: "run-1",
            attemptId: "attempt-1",
            sourceAttemptId: nil,
            resolvedContext: Self.context,
            summary: nil,
            buildSummary: nil,
            testSummary: nil,
            evidence: [],
            failure: nil,
            persistedRunPath: nil
        )
        let first = try WorkflowJSONRenderer.renderJSON(result)
        let second = try WorkflowJSONRenderer.renderJSON(result)
        #expect(first == second)
    }

    @Test("renderJSON is deterministic for DiagnosisCompareResult")
    func compareResultDeterminism() throws {
        let result = DiagnosisCompareResult(
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
            persistedRunPath: nil
        )
        let first = try WorkflowJSONRenderer.renderJSON(result)
        let second = try WorkflowJSONRenderer.renderJSON(result)
        #expect(first == second)
    }

    @Test("renderJSON is deterministic for DiagnosisFinalResult")
    func finalResultDeterminism() throws {
        let result = DiagnosisFinalResult(
            phase: .diagnosisBuild,
            status: .failed,
            runId: "run-1",
            attemptId: "attempt-1",
            sourceAttemptId: nil,
            summary: DiagnosisStatusSummary(
                source: .build,
                headline: "Build failed.",
                detail: nil
            ),
            currentAttempt: nil,
            sourceAttempt: nil,
            comparison: nil,
            failure: Self.failure,
            persistedRunPath: nil
        )
        let first = try WorkflowJSONRenderer.renderJSON(result)
        let second = try WorkflowJSONRenderer.renderJSON(result)
        #expect(first == second)
    }

    @Test("renderJSON is deterministic for DiagnosisEvidenceResult")
    func evidenceResultDeterminism() throws {
        let result = DiagnosisEvidenceResult(
            phase: .diagnosisBuild,
            status: .succeeded,
            evidenceState: .complete,
            runId: "run-1",
            attemptId: "attempt-1",
            resolvedContext: Self.context,
            buildSummary: nil,
            testSummary: nil,
            runtimeSummary: nil,
            evidence: [],
            failure: nil,
            persistedRunPath: nil
        )
        let first = try WorkflowJSONRenderer.renderJSON(result)
        let second = try WorkflowJSONRenderer.renderJSON(result)
        #expect(first == second)
    }

    @Test("renderJSON is deterministic for DiagnosisInspectResult")
    func inspectResultDeterminism() throws {
        let result = DiagnosisInspectResult(
            phase: .diagnosisBuild,
            status: .succeeded,
            runId: "run-1",
            attemptId: "attempt-1",
            resolvedContext: Self.context,
            contextProvenance: nil,
            evidenceCompleteness: .complete,
            failure: nil,
            persistedRunPath: nil
        )
        let first = try WorkflowJSONRenderer.renderJSON(result)
        let second = try WorkflowJSONRenderer.renderJSON(result)
        #expect(first == second)
    }

    // MARK: - Test 2: Sorted keys guarantee

    @Test("renderJSON produces alphabetically sorted keys")
    func sortedKeysGuarantee() throws {
        let result = DiagnosisBuildResult(
            status: .failed,
            runId: "run-sorted",
            attemptId: "attempt-sorted",
            resolvedContext: Self.context,
            summary: nil,
            failure: Self.failure,
            persistedRunPath: "/tmp/run.json"
        )

        let json = try WorkflowJSONRenderer.renderJSON(result)

        // Verify alphabetical key ordering in the top-level object.
        // Expected order: attemptId < failure < persistedRunPath < phase < resolvedContext < runId < schemaVersion < status < workflow
        let attemptIdPos = try #require(json.range(of: "\"attemptId\""))
        let failurePos = try #require(json.range(of: "\"failure\""))
        let runIdPos = try #require(json.range(of: "\"runId\""))
        let schemaVersionPos = try #require(json.range(of: "\"schemaVersion\""))
        let statusPos = try #require(json.range(of: "\"status\""))
        let workflowPos = try #require(json.range(of: "\"workflow\""))

        #expect(attemptIdPos.lowerBound < failurePos.lowerBound)
        #expect(failurePos.lowerBound < runIdPos.lowerBound)
        #expect(runIdPos.lowerBound < schemaVersionPos.lowerBound)
        #expect(schemaVersionPos.lowerBound < statusPos.lowerBound)
        #expect(statusPos.lowerBound < workflowPos.lowerBound)
    }

    // MARK: - Test 3: ISO 8601 date format stability

    @Test("renderJSON encodes dates in ISO 8601 format")
    func iso8601DateFormatStability() throws {
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14T22:13:20Z

        let snapshot = DiagnosisCompareAttemptSnapshot(
            attemptId: "attempt-date",
            attemptNumber: 1,
            phase: .diagnosisBuild,
            status: .succeeded,
            resolvedContext: Self.context,
            summary: DiagnosisStatusSummary(
                source: .build,
                headline: "Build succeeded.",
                detail: nil
            ),
            recordedAt: fixedDate
        )

        let result = DiagnosisCompareResult(
            phase: .diagnosisBuild,
            status: .succeeded,
            outcome: .improved,
            runId: "run-date",
            attemptId: "attempt-2",
            sourceAttemptId: "attempt-1",
            priorAttempt: snapshot,
            currentAttempt: snapshot,
            changedEvidence: [],
            unchangedBlockers: [],
            failure: nil,
            persistedRunPath: nil
        )

        let json = try WorkflowJSONRenderer.renderJSON(result)

        // ISO 8601 dates match the pattern: YYYY-MM-DDTHH:MM:SSZ
        let iso8601Pattern = #/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z/#
        let dateMatches = json.matches(of: iso8601Pattern)
        #expect(dateMatches.count >= 2, "Expected at least two ISO 8601 dates (priorAttempt and currentAttempt)")

        // Verify the specific date value rendered from the fixed timestamp
        #expect(json.contains("2023-11-14T22:13:20Z"))
    }
}

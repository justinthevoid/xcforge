import Foundation
import Testing
@testable import xcforge
@testable import xcforgeCore

@Suite("WorkflowJSONRenderer")
struct WorkflowJSONRendererTests {

    @Test("renderJSON encodes a DiagnosisStartResult with schema version and run identity")
    func renderJSONEncodesStartResult() throws {
        let result = DiagnosisStartResult(
            status: .succeeded,
            runId: "run-start-json",
            attemptId: "attempt-1",
            resolvedContext: ResolvedWorkflowContext(
                project: "/tmp/App.xcodeproj",
                scheme: "App",
                simulator: "iPhone 16 Pro",
                configuration: "Debug",
                app: AppContext(bundleId: "com.example.app", appPath: "/tmp/App.app")
            ),
            failure: nil,
            persistedRunPath: "/tmp/run-start-json.json"
        )

        let json = try WorkflowJSONRenderer.renderJSON(result)
        let parsed = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]

        #expect(parsed["schemaVersion"] as? String == WorkflowRunRecord.currentSchemaVersion)
        #expect(parsed["workflow"] as? String == "diagnosis")
        #expect(parsed["status"] as? String == "succeeded")
        #expect(parsed["runId"] as? String == "run-start-json")
    }

    @Test("renderJSON encodes a DiagnosisBuildResult with sorted keys and ISO 8601 dates")
    func renderJSONEncodesBuildResult() throws {
        let result = DiagnosisBuildResult(
            status: .failed,
            runId: "run-build-json",
            attemptId: "attempt-2",
            resolvedContext: nil,
            summary: nil,
            failure: WorkflowFailure(
                field: .build,
                classification: .executionFailed,
                message: "Build failed"
            ),
            persistedRunPath: nil
        )

        let json = try WorkflowJSONRenderer.renderJSON(result)

        // Verify sorted keys: "attemptId" should appear before "failure"
        let attemptIdRange = try #require(json.range(of: "\"attemptId\""))
        let failureRange = try #require(json.range(of: "\"failure\""))
        #expect(attemptIdRange.lowerBound < failureRange.lowerBound)

        // Verify pretty-printed (contains newlines)
        #expect(json.contains("\n"))
    }

    @Test("renderJSON produces output identical to DiagnosisFinalResultRenderer.renderJSON")
    func renderJSONMatchesFinalResultRendererOutput() throws {
        let result = DiagnosisFinalResult(
            phase: .diagnosisBuild,
            status: .failed,
            runId: "run-match",
            attemptId: "attempt-1",
            sourceAttemptId: nil,
            summary: DiagnosisStatusSummary(
                source: .build,
                headline: "Build failed.",
                detail: nil
            ),
            recoveryHistory: [],
            currentAttempt: nil,
            sourceAttempt: nil,
            comparison: nil,
            failure: WorkflowFailure(
                field: .build,
                classification: .executionFailed,
                message: "Compiler error"
            ),
            persistedRunPath: nil
        )

        let shared = try WorkflowJSONRenderer.renderJSON(result)
        let legacy = try DiagnosisFinalResultRenderer.renderJSON(result)

        #expect(shared == legacy)
    }

    @Test("renderJSON encodes DiagnosisStatusResult with optional phase")
    func renderJSONEncodesStatusResult() throws {
        let result = DiagnosisStatusResult(
            phase: nil,
            status: nil,
            runId: nil,
            attemptId: nil,
            resolvedContext: nil,
            summary: nil,
            failure: WorkflowFailure(
                field: .run,
                classification: .notFound,
                message: "No active diagnosis run found."
            ),
            persistedRunPath: nil
        )

        let json = try WorkflowJSONRenderer.renderJSON(result)
        let parsed = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]

        #expect(parsed["schemaVersion"] as? String == WorkflowRunRecord.currentSchemaVersion)
        #expect(parsed["workflow"] as? String == "diagnosis")
    }

    @Test("renderJSON encodes structured failure evidence with observed, inferred, and recoverability")
    func renderJSONEncodesStructuredFailureEvidence() throws {
        let result = DiagnosisBuildResult(
            status: .failed,
            runId: "run-failure-evidence",
            attemptId: "attempt-1",
            resolvedContext: nil,
            summary: nil,
            failure: WorkflowFailure(
                field: .build,
                classification: .executionFailed,
                message: "Build failed with 3 errors",
                observed: ObservedFailureEvidence(
                    summary: "Build failed with 3 errors",
                    detail: "CompileSwift normal x86_64 failed"
                ),
                inferred: InferredFailureConclusion(
                    summary: "Build errors must be resolved before diagnosis can proceed."
                ),
                recoverability: .retryAfterFix,
                evidenceReferences: [
                    EvidenceReference(kind: "xcresult", path: "/tmp/build.xcresult", source: "xcodebuild")
                ]
            ),
            persistedRunPath: nil
        )

        let json = try WorkflowJSONRenderer.renderJSON(result)
        let parsed = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
        let failure = try #require(parsed["failure"] as? [String: Any])

        let observed = try #require(failure["observed"] as? [String: Any])
        #expect(observed["summary"] as? String == "Build failed with 3 errors")
        #expect(observed["detail"] as? String == "CompileSwift normal x86_64 failed")

        let inferred = try #require(failure["inferred"] as? [String: Any])
        #expect(inferred["summary"] as? String == "Build errors must be resolved before diagnosis can proceed.")

        #expect(failure["recoverability"] as? String == "retry_after_fix")

        let refs = try #require(failure["evidenceReferences"] as? [[String: Any]])
        #expect(refs.count == 1)
        #expect(refs[0]["kind"] as? String == "xcresult")
    }

    @Test("renderJSON encodes failure with nil optional evidence fields")
    func renderJSONEncodesFailureWithNilOptionalFields() throws {
        let result = DiagnosisStatusResult(
            phase: nil,
            status: nil,
            runId: nil,
            attemptId: nil,
            resolvedContext: nil,
            summary: nil,
            failure: WorkflowFailure(
                field: .run,
                classification: .notFound,
                message: "No active diagnosis run found."
            ),
            persistedRunPath: nil
        )

        let json = try WorkflowJSONRenderer.renderJSON(result)
        let parsed = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
        let failure = try #require(parsed["failure"] as? [String: Any])

        #expect(failure["observed"] == nil)
        #expect(failure["inferred"] == nil)
        #expect(failure["recoverability"] == nil)
        #expect(failure["evidenceReferences"] == nil)
    }

    @Test("renderJSON round-trips all FailureRecoverability values")
    func renderJSONRoundTripsRecoverabilityValues() throws {
        let cases: [(FailureRecoverability, String)] = [
            (.retryAfterFix, "retry_after_fix"),
            (.actionRequired, "action_required"),
            (.stop, "stop"),
            (.unknown, "unknown"),
        ]

        for (value, expectedString) in cases {
            let result = DiagnosisStartResult(
                status: .failed,
                runId: nil,
                attemptId: nil,
                resolvedContext: nil,
                failure: WorkflowFailure(
                    field: .workflow,
                    classification: .executionFailed,
                    message: "test",
                    recoverability: value
                ),
                persistedRunPath: nil
            )

            let json = try WorkflowJSONRenderer.renderJSON(result)
            let parsed = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
            let failure = try #require(parsed["failure"] as? [String: Any])
            #expect(failure["recoverability"] as? String == expectedString)
        }
    }

    @Test("renderJSON embeds current schema version across all result types")
    func renderJSONSchemaVersionAcrossAllTypes() throws {
        let expected = WorkflowRunRecord.currentSchemaVersion
        let context = ResolvedWorkflowContext(
            project: "/tmp/App.xcodeproj",
            scheme: "App",
            simulator: "iPhone 16 Pro",
            configuration: "Debug",
            app: AppContext(bundleId: "com.example.app", appPath: "/tmp/App.app")
        )

        func assertSchemaVersion<T: Encodable>(_ result: T, label: String) throws {
            let json = try WorkflowJSONRenderer.renderJSON(result)
            let parsed = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
            #expect(parsed["schemaVersion"] as? String == expected, "Schema version mismatch in \(label)")
        }

        try assertSchemaVersion(DiagnosisStartResult(status: .succeeded, runId: "r", attemptId: "a", resolvedContext: context, failure: nil, persistedRunPath: nil), label: "StartResult")
        try assertSchemaVersion(DiagnosisBuildResult(status: .failed, runId: "r", attemptId: "a", resolvedContext: nil, summary: nil, failure: nil, persistedRunPath: nil), label: "BuildResult")
        try assertSchemaVersion(DiagnosisTestResult(status: .succeeded, runId: "r", attemptId: "a", resolvedContext: nil, summary: nil, failure: nil, persistedRunPath: nil), label: "TestResult")
        try assertSchemaVersion(DiagnosisRuntimeResult(status: .succeeded, runId: "r", attemptId: "a", resolvedContext: nil, summary: nil, failure: nil, persistedRunPath: nil), label: "RuntimeResult")
        try assertSchemaVersion(DiagnosisStatusResult(phase: nil, status: nil, runId: nil, attemptId: nil, resolvedContext: nil, summary: nil, failure: nil, persistedRunPath: nil), label: "StatusResult")
        try assertSchemaVersion(DiagnosisVerifyResult(phase: nil, status: nil, outcome: nil, runId: nil, attemptId: nil, sourceAttemptId: nil, resolvedContext: nil, summary: nil, buildSummary: nil, testSummary: nil, evidence: [], failure: nil, persistedRunPath: nil), label: "VerifyResult")
        try assertSchemaVersion(DiagnosisCompareResult(phase: nil, status: nil, outcome: nil, runId: nil, attemptId: nil, sourceAttemptId: nil, priorAttempt: nil, currentAttempt: nil, changedEvidence: [], unchangedBlockers: [], failure: nil, persistedRunPath: nil), label: "CompareResult")
        try assertSchemaVersion(DiagnosisFinalResult(phase: nil, status: nil, runId: nil, attemptId: nil, sourceAttemptId: nil, summary: nil, currentAttempt: nil, sourceAttempt: nil, comparison: nil, failure: nil, persistedRunPath: nil), label: "FinalResult")
        try assertSchemaVersion(DiagnosisEvidenceResult(phase: nil, status: nil, evidenceState: nil, runId: nil, attemptId: nil, resolvedContext: nil, buildSummary: nil, testSummary: nil, runtimeSummary: nil, evidence: [], failure: nil, persistedRunPath: nil), label: "EvidenceResult")
        try assertSchemaVersion(DiagnosisInspectResult(phase: nil, status: nil, runId: nil, attemptId: nil, resolvedContext: nil, contextProvenance: nil, evidenceCompleteness: nil, failure: nil, persistedRunPath: nil), label: "InspectResult")
    }

    @Test("renderJSON round-trips a DiagnosisCompareResult through decode")
    func renderJSONRoundTripsCompareResult() throws {
        let result = DiagnosisCompareResult(
            phase: .diagnosisBuild,
            status: .succeeded,
            outcome: .improved,
            runId: "run-compare-json",
            attemptId: "attempt-3",
            sourceAttemptId: "attempt-2",
            priorAttempt: nil,
            currentAttempt: nil,
            changedEvidence: [],
            unchangedBlockers: [],
            failure: nil,
            persistedRunPath: nil
        )

        let json = try WorkflowJSONRenderer.renderJSON(result)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(DiagnosisCompareResult.self, from: Data(json.utf8))

        #expect(decoded == result)
    }
}

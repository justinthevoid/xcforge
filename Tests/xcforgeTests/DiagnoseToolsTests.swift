import Foundation
import Testing
import MCP
@testable import xcforgeCore

@Suite("DiagnoseTools")
struct DiagnoseToolsTests {

    @Test("tool registry includes all 10 diagnosis workflow tools")
    func toolRegistryIncludesAllDiagnoseTools() {
        let toolNames = DiagnoseTools.tools.map(\.name)
        #expect(toolNames.contains("diagnose_start"))
        #expect(toolNames.contains("diagnose_build"))
        #expect(toolNames.contains("diagnose_test"))
        #expect(toolNames.contains("diagnose_runtime"))
        #expect(toolNames.contains("diagnose_status"))
        #expect(toolNames.contains("diagnose_evidence"))
        #expect(toolNames.contains("diagnose_inspect"))
        #expect(toolNames.contains("diagnose_verify"))
        #expect(toolNames.contains("diagnose_compare"))
        #expect(toolNames.contains("diagnose_result"))
        #expect(toolNames.count == 10)
    }

    @Test("diagnose_build requires run_id")
    func diagnoseBuildRequiresRunId() async {
        let result = await DiagnoseTools.diagnoseBuild(nil)
        #expect(result.isError == true)
        let text = extractText(result)
        #expect(text?.contains("Missing required: run_id") == true)
    }

    @Test("diagnose_test requires run_id")
    func diagnoseTestRequiresRunId() async {
        let result = await DiagnoseTools.diagnoseTest(nil)
        #expect(result.isError == true)
        let text = extractText(result)
        #expect(text?.contains("Missing required: run_id") == true)
    }

    @Test("diagnose_runtime requires run_id")
    func diagnoseRuntimeRequiresRunId() async {
        let result = await DiagnoseTools.diagnoseRuntime(nil, env: .live)
        #expect(result.isError == true)
        let text = extractText(result)
        #expect(text?.contains("Missing required: run_id") == true)
    }

    @Test("diagnose_verify requires run_id")
    func diagnoseVerifyRequiresRunId() async {
        let result = await DiagnoseTools.diagnoseVerify(nil)
        #expect(result.isError == true)
        let text = extractText(result)
        #expect(text?.contains("Missing required: run_id") == true)
    }

    @Test("diagnose_start with no args returns structured JSON result")
    func diagnoseStartReturnsJSON() async {
        let result = await DiagnoseTools.diagnoseStart(nil, session: SessionState(defaultsStore: DefaultsStore(baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))))
        let text = extractText(result)
        let json = text.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
        #expect(json?["schemaVersion"] as? String == WorkflowRunRecord.currentSchemaVersion)
        #expect(json?["workflow"] as? String == "diagnosis")
        #expect(json?["phase"] as? String == "diagnosis_start")
    }

    @Test("diagnose_status with no args returns structured JSON result")
    func diagnoseStatusReturnsJSON() async {
        let result = await DiagnoseTools.diagnoseStatus(nil)
        let text = extractText(result)
        let json = text.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
        #expect(json?["schemaVersion"] as? String == WorkflowRunRecord.currentSchemaVersion)
        #expect(json?["workflow"] as? String == "diagnosis")
    }

    @Test("diagnose_result with no args returns structured JSON result")
    func diagnoseResultReturnsJSON() async {
        let result = await DiagnoseTools.diagnoseResult(nil)
        let text = extractText(result)
        let json = text.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
        #expect(json?["schemaVersion"] as? String == WorkflowRunRecord.currentSchemaVersion)
        #expect(json?["workflow"] as? String == "diagnosis")
    }

    @Test("diagnose_compare with no args returns structured JSON result")
    func diagnoseCompareReturnsJSON() async {
        let result = await DiagnoseTools.diagnoseCompare(nil)
        let text = extractText(result)
        let json = text.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
        #expect(json?["schemaVersion"] as? String == WorkflowRunRecord.currentSchemaVersion)
        #expect(json?["workflow"] as? String == "diagnosis")
    }

    @Test("diagnose_evidence with no args returns structured JSON result")
    func diagnoseEvidenceReturnsJSON() async {
        let result = await DiagnoseTools.diagnoseEvidence(nil)
        let text = extractText(result)
        let json = text.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
        #expect(json?["schemaVersion"] as? String == WorkflowRunRecord.currentSchemaVersion)
        #expect(json?["workflow"] as? String == "diagnosis")
    }

    @Test("all diagnose tools are reachable through ToolRegistry dispatch")
    func allToolsDispatchable() async {
        let diagnoseNames = ["diagnose_start", "diagnose_build", "diagnose_test",
                             "diagnose_runtime", "diagnose_status", "diagnose_evidence",
                             "diagnose_inspect", "diagnose_verify", "diagnose_compare",
                             "diagnose_result"]
        let allRegisteredNames = ToolRegistry.allTools.map(\.name)
        for name in diagnoseNames {
            #expect(allRegisteredNames.contains(name), "ToolRegistry.allTools missing \(name)")
        }
    }

    @Test("MCP diagnose_start JSON matches CLI WorkflowJSONRenderer encoding")
    func mcpStartMatchesCLIEncoding() async {
        // Both paths must share the same session so resolved context is identical.
        // JSON still differs in runId/attemptId (unique per call), so compare structure not exact strings.
        let session = SessionState(defaultsStore: DefaultsStore(baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))

        let request = DiagnosisStartRequest()
        let workflow = DiagnosisStartWorkflow(session: session)
        let cliResult = await workflow.start(request: request)
        let cliJSON = try? WorkflowJSONRenderer.renderJSON(cliResult)

        let mcpResult = await DiagnoseTools.diagnoseStart(nil, session: session)
        let mcpJSON = extractText(mcpResult)

        #expect(cliJSON != nil)
        // Both produce valid JSON with matching schema, workflow, and phase.
        // Exact equality is not possible since each call generates unique runId/attemptId.
        let cliDict = cliJSON.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
        let mcpDict = mcpJSON.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
        #expect(cliDict?["schemaVersion"] as? String == mcpDict?["schemaVersion"] as? String)
        #expect(cliDict?["workflow"] as? String == mcpDict?["workflow"] as? String)
        #expect(cliDict?["phase"] as? String == mcpDict?["phase"] as? String)
        #expect(cliDict?["status"] as? String == mcpDict?["status"] as? String)
    }

    @Test("MCP diagnose_status JSON matches CLI WorkflowJSONRenderer encoding")
    func mcpStatusMatchesCLIEncoding() async {
        let request = DiagnosisStatusRequest(runId: nil)
        let workflow = DiagnosisStatusWorkflow()
        let cliResult = await workflow.inspect(request: request)
        let cliJSON = try? WorkflowJSONRenderer.renderJSON(cliResult)

        let mcpResult = await DiagnoseTools.diagnoseStatus(nil)
        let mcpJSON = extractText(mcpResult)

        #expect(cliJSON != nil)
        #expect(mcpJSON == cliJSON)
    }

    @Test("MCP diagnose_result JSON matches CLI WorkflowJSONRenderer encoding")
    func mcpResultMatchesCLIEncoding() async {
        let request = DiagnosisFinalResultRequest(runId: nil)
        let workflow = DiagnosisFinalResultWorkflow()
        let cliResult = await workflow.assemble(request: request)
        let cliJSON = try? WorkflowJSONRenderer.renderJSON(cliResult)

        let mcpResult = await DiagnoseTools.diagnoseResult(nil)
        let mcpJSON = extractText(mcpResult)

        #expect(cliJSON != nil)
        #expect(mcpJSON == cliJSON)
    }

    // MARK: - Helpers

    private func extractText(_ result: CallTool.Result) -> String? {
        result.content.compactMap {
            if case let .text(text, _, _) = $0 { return text }
            return nil
        }.first
    }
}

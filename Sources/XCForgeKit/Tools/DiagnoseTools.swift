import Foundation
import MCP

/// MCP adapter for diagnosis workflows.
/// Each tool mirrors a CLI `xcforge diagnose <phase>` subcommand, accepting the same
/// parameters and returning the same JSON contract produced by `--json`.
enum DiagnoseTools {

  // MARK: - Tool Definitions

  public static let tools: [Tool] = [
    Tool(
      name: "diagnose_start",
      description: """
        Create a diagnosis run with resolved context. Equivalent to \
        `xcforge diagnose start --json`. Returns a JSON object with \
        schemaVersion, workflow, phase, status, runId, and resolvedContext.
        """,
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "project": .object([
            "type": .string("string"),
            "description": .string("Path to .xcodeproj or .xcworkspace. Auto-detected if omitted."),
          ]),
          "scheme": .object([
            "type": .string("string"),
            "description": .string("Scheme name. Auto-detected if omitted."),
          ]),
          "simulator": .object([
            "type": .string("string"),
            "description": .string("Simulator UDID or display name. Auto-detected if omitted."),
          ]),
          "reuse_run_id": .object([
            "type": .string("string"), "description": .string("Run ID to reuse context from."),
          ]),
          "configuration": .object([
            "type": .string("string"),
            "description": .string(
              "Build configuration (e.g. Debug). Used when resolving app context."),
          ]),
        ]),
      ])
    ),
    Tool(
      name: "diagnose_build",
      description: """
        Diagnose a build for an existing diagnosis run. Equivalent to \
        `xcforge diagnose build --json`. Returns a JSON object with build \
        diagnosis summary, evidence, and failure details. If run_id is omitted, \
        uses the newest active or recent run.
        """,
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "run_id": .object([
            "type": .string("string"),
            "description": .string(
              "Run ID returned by diagnose_start. If omitted, uses the newest active or recent run."
            ),
          ])
        ]),
      ])
    ),
    Tool(
      name: "diagnose_test",
      description: """
        Diagnose a test run for an existing diagnosis run. Equivalent to \
        `xcforge diagnose test --json`. Returns a JSON object with test \
        diagnosis summary and failure details. If run_id is omitted, uses \
        the newest active or recent run.
        """,
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "run_id": .object([
            "type": .string("string"),
            "description": .string(
              "Run ID returned by diagnose_start. If omitted, uses the newest active or recent run."
            ),
          ])
        ]),
      ])
    ),
    Tool(
      name: "diagnose_runtime",
      description: """
        Launch the app for an existing diagnosis run and capture runtime signals. \
        Equivalent to `xcforge diagnose runtime --json`. Returns a JSON object with \
        runtime diagnosis results. If run_id is omitted, uses the newest active or \
        recent run.
        """,
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "run_id": .object([
            "type": .string("string"),
            "description": .string(
              "Run ID returned by diagnose_start. If omitted, uses the newest active or recent run."
            ),
          ]),
          "capture_screenshot": .object([
            "type": .string("boolean"),
            "description": .string(
              "Capture a simulator screenshot as part of runtime diagnosis. Default: false"),
          ]),
        ]),
      ])
    ),
    Tool(
      name: "diagnose_status",
      description: """
        Inspect the status of an active or recent diagnosis run. Equivalent to \
        `xcforge diagnose status --json`. If run_id is omitted, uses the newest \
        active or recent run.
        """,
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "run_id": .object([
            "type": .string("string"),
            "description": .string(
              "Run ID to inspect. If omitted, uses the newest active or recent run."),
          ])
        ]),
      ])
    ),
    Tool(
      name: "diagnose_evidence",
      description: """
        Inspect all available evidence for an active or recent diagnosis run. \
        Equivalent to `xcforge diagnose evidence --json`. If run_id is omitted, \
        uses the newest active or recent run.
        """,
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "run_id": .object([
            "type": .string("string"),
            "description": .string(
              "Run ID to inspect. If omitted, uses the newest active or recent run."),
          ])
        ]),
      ])
    ),
    Tool(
      name: "diagnose_verify",
      description: """
        Rerun validation for a prior diagnosis run. Equivalent to \
        `xcforge diagnose verify --json`. Accepts optional overrides for \
        project, scheme, simulator, and configuration. If run_id is omitted, \
        uses the newest active or recent run.
        """,
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "run_id": .object([
            "type": .string("string"),
            "description": .string(
              "Run ID to rerun validation for. If omitted, uses the newest active or recent run."),
          ]),
          "project": .object([
            "type": .string("string"),
            "description": .string("Override the project path for this rerun."),
          ]),
          "scheme": .object([
            "type": .string("string"),
            "description": .string("Override the scheme for this rerun."),
          ]),
          "simulator": .object([
            "type": .string("string"),
            "description": .string("Override the simulator for this rerun."),
          ]),
          "configuration": .object([
            "type": .string("string"),
            "description": .string("Override the build configuration for this rerun."),
          ]),
        ]),
      ])
    ),
    Tool(
      name: "diagnose_compare",
      description: """
        Compare an original diagnosis result against the latest rerun. Equivalent \
        to `xcforge diagnose compare --json`. If run_id is omitted, uses the newest \
        active or recent run.
        """,
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "run_id": .object([
            "type": .string("string"),
            "description": .string(
              "Run ID to compare. If omitted, uses the newest active or recent run."),
          ])
        ]),
      ])
    ),
    Tool(
      name: "diagnose_inspect",
      description: """
        Consolidated troubleshooting view for investigating workflow outcomes. \
        Equivalent to `xcforge diagnose inspect --json`. Correlates the action \
        timeline, evidence availability, terminal classification with observed-vs-inferred \
        separation, and context provenance in one result. If run_id is omitted, uses \
        the newest active or recent run.
        """,
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "run_id": .object([
            "type": .string("string"),
            "description": .string(
              "Run ID to inspect. If omitted, uses the newest active or recent run."),
          ])
        ]),
      ])
    ),
    Tool(
      name: "diagnose_result",
      description: """
        Return the final proof-oriented result for a diagnosis run. Equivalent to \
        `xcforge diagnose result --json`. If run_id is omitted, uses the newest \
        terminal run.
        """,
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "run_id": .object([
            "type": .string("string"),
            "description": .string(
              "Run ID to inspect. If omitted, uses the newest terminal diagnosis run."),
          ])
        ]),
      ])
    ),
  ]

  // MARK: - Input Types

  struct StartInput: Decodable {
    var project: String?
    var scheme: String?
    var simulator: String?
    var reuse_run_id: String?
    var configuration: String?
  }

  struct OptionalRunIdInput: Decodable {
    var run_id: String?
  }

  struct OptionalRuntimeInput: Decodable {
    var run_id: String?
    var capture_screenshot: Bool?
  }

  struct OptionalVerifyInput: Decodable {
    var run_id: String?
    var project: String?
    var scheme: String?
    var simulator: String?
    var configuration: String?
  }

  /// Resolves an optional run_id to a concrete value by auto-detecting the newest active or recent run.
  /// Returns the resolved run ID, or a `.fail` CallTool.Result if resolution fails.
  private static func resolveOptionalRunId(_ runId: String?) -> (String?, CallTool.Result?) {
    let resolver = RunResolver(
      strategy: .activeOrRecent,
      loadRun: { runId in try RunStore().load(runId: runId) },
      loadLatestActiveRun: { try RunStore().latestActiveDiagnosisRun() },
      loadLatestRun: { try RunStore().latestDiagnosisRun() }
    )
    switch resolver.resolve(runId) {
    case .success(let run):
      return (run.runId, nil)
    case .failure(let failure):
      return (nil, .fail(Self.resolverFailureMessage(failure)))
    }
  }

  private static func resolverFailureMessage(_ failure: RunResolutionFailure) -> String {
    switch failure {
    case .emptyRunId:
      return "run_id must not be empty."
    case .notFound(let runId):
      return "No diagnosis run was found for run ID \(runId)."
    case .noRunsAvailable:
      return "No active or recent diagnosis runs found. Start one with diagnose_start first."
    case .runStillInProgress(let runId):
      return "Run \(runId) is still in progress."
    case .loadFailed(let error):
      return "Failed to resolve diagnosis run: \(error)"
    }
  }

  // MARK: - Handlers

  static func diagnoseStart(_ args: [String: Value]?, session: SessionState) async
    -> CallTool.Result
  {
    switch ToolInput.decode(StartInput.self, from: args) {
    case .failure(let err): return err
    case .success(let input):
      let workflow = DiagnosisStartWorkflow(session: session)
      let result = await workflow.start(
        request: DiagnosisStartRequest(
          project: input.project,
          scheme: input.scheme,
          simulator: input.simulator,
          reuseRunId: input.reuse_run_id,
          configuration: input.configuration
        )
      )
      return encodeResult(result, isError: !result.isSuccessfulStart)
    }
  }

  static func diagnoseBuild(_ args: [String: Value]?) async -> CallTool.Result {
    switch ToolInput.decode(OptionalRunIdInput.self, from: args) {
    case .failure(let err): return err
    case .success(let input):
      let (runId, resolveErr) = resolveOptionalRunId(input.run_id)
      guard let runId else { return resolveErr! }
      let workflow = DiagnosisBuildWorkflow()
      let result = await workflow.diagnose(
        request: DiagnosisBuildRequest(runId: runId)
      )
      return encodeResult(result, isError: result.status == .failed)
    }
  }

  static func diagnoseTest(_ args: [String: Value]?) async -> CallTool.Result {
    switch ToolInput.decode(OptionalRunIdInput.self, from: args) {
    case .failure(let err): return err
    case .success(let input):
      let (runId, resolveErr) = resolveOptionalRunId(input.run_id)
      guard let runId else { return resolveErr! }
      let workflow = DiagnosisTestWorkflow()
      let result = await workflow.diagnose(
        request: DiagnosisTestRequest(runId: runId)
      )
      return encodeResult(result, isError: result.status != .succeeded)
    }
  }

  static func diagnoseRuntime(_ args: [String: Value]?, env: Environment) async -> CallTool.Result {
    switch ToolInput.decode(OptionalRuntimeInput.self, from: args) {
    case .failure(let err): return err
    case .success(let input):
      let (runId, resolveErr) = resolveOptionalRunId(input.run_id)
      guard let runId else { return resolveErr! }
      let workflow = DiagnosisRuntimeWorkflow(wdaClient: env.wdaClient)
      let result = await workflow.diagnose(
        request: DiagnosisRuntimeRequest(
          runId: runId,
          captureScreenshot: input.capture_screenshot ?? false
        )
      )
      return encodeResult(result, isError: result.status != .succeeded)
    }
  }

  static func diagnoseStatus(_ args: [String: Value]?) async -> CallTool.Result {
    switch ToolInput.decode(OptionalRunIdInput.self, from: args) {
    case .failure(let err): return err
    case .success(let input):
      let workflow = DiagnosisStatusWorkflow()
      let result = await workflow.inspect(
        request: DiagnosisStatusRequest(runId: input.run_id)
      )
      return encodeResult(result, isError: !result.isSuccessfulInspection)
    }
  }

  static func diagnoseEvidence(_ args: [String: Value]?) async -> CallTool.Result {
    switch ToolInput.decode(OptionalRunIdInput.self, from: args) {
    case .failure(let err): return err
    case .success(let input):
      let workflow = DiagnosisStatusWorkflow()
      let result = await workflow.inspectEvidence(
        request: DiagnosisStatusRequest(runId: input.run_id)
      )
      return encodeResult(result, isError: !result.isSuccessfulInspection)
    }
  }

  static func diagnoseVerify(_ args: [String: Value]?) async -> CallTool.Result {
    switch ToolInput.decode(OptionalVerifyInput.self, from: args) {
    case .failure(let err): return err
    case .success(let input):
      let (runId, resolveErr) = resolveOptionalRunId(input.run_id)
      guard let runId else { return resolveErr! }
      let workflow = DiagnosisVerifyWorkflow()
      let result = await workflow.verify(
        request: DiagnosisVerifyRequest(
          runId: runId,
          project: input.project,
          scheme: input.scheme,
          simulator: input.simulator,
          configuration: input.configuration
        )
      )
      return encodeResult(result, isError: !result.isSuccessfulVerification)
    }
  }

  static func diagnoseCompare(_ args: [String: Value]?) async -> CallTool.Result {
    switch ToolInput.decode(OptionalRunIdInput.self, from: args) {
    case .failure(let err): return err
    case .success(let input):
      let workflow = DiagnosisCompareWorkflow()
      let result = await workflow.compare(
        request: DiagnosisCompareRequest(runId: input.run_id)
      )
      return encodeResult(result, isError: !result.isSuccessfulComparison)
    }
  }

  static func diagnoseInspect(_ args: [String: Value]?) async -> CallTool.Result {
    switch ToolInput.decode(OptionalRunIdInput.self, from: args) {
    case .failure(let err): return err
    case .success(let input):
      let workflow = DiagnosisInspectWorkflow()
      let result = await workflow.inspect(
        request: DiagnosisInspectRequest(runId: input.run_id)
      )
      return encodeResult(result, isError: !result.isSuccessfulInspection)
    }
  }

  static func diagnoseResult(_ args: [String: Value]?) async -> CallTool.Result {
    switch ToolInput.decode(OptionalRunIdInput.self, from: args) {
    case .failure(let err): return err
    case .success(let input):
      let workflow = DiagnosisFinalResultWorkflow()
      let result = await workflow.assemble(
        request: DiagnosisFinalResultRequest(runId: input.run_id)
      )
      return encodeResult(result, isError: !result.isSuccessfulFinalResult)
    }
  }

  // MARK: - Shared Encoding

  private static func encodeResult<T: Encodable>(_ value: T, isError: Bool) -> CallTool.Result {
    do {
      let json = try WorkflowJSONRenderer.renderJSON(value)
      return .init(content: [.text(text: json, annotations: nil, _meta: nil)], isError: isError)
    } catch {
      return .fail("JSON encoding error: \(error)")
    }
  }
}

extension DiagnoseTools: ToolProvider {
  public static func dispatch(_ name: String, _ args: [String: Value]?, env: Environment) async
    -> CallTool.Result?
  {
    switch name {
    case "diagnose_start": return await diagnoseStart(args, session: env.session)
    case "diagnose_build": return await diagnoseBuild(args)
    case "diagnose_test": return await diagnoseTest(args)
    case "diagnose_runtime": return await diagnoseRuntime(args, env: env)
    case "diagnose_status": return await diagnoseStatus(args)
    case "diagnose_evidence": return await diagnoseEvidence(args)
    case "diagnose_inspect": return await diagnoseInspect(args)
    case "diagnose_verify": return await diagnoseVerify(args)
    case "diagnose_compare": return await diagnoseCompare(args)
    case "diagnose_result": return await diagnoseResult(args)
    default: return nil
    }
  }
}

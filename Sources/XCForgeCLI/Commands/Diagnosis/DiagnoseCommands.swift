import ArgumentParser
import XCForgeKit

// MARK: - diagnose (group)

struct Diagnose: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "diagnose",
    abstract: "Start diagnosis workflows and inspect or summarize their results.",
    subcommands: [
      DiagnoseStart.self, DiagnoseBuild.self, DiagnoseTest.self, DiagnoseRuntime.self,
      DiagnoseStatus.self, DiagnoseEvidence.self, DiagnoseInspect.self, DiagnoseVerify.self,
      DiagnoseCompare.self, DiagnoseResult.self,
    ]
  )
}

// MARK: - diagnose start

struct DiagnoseStart: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "start",
    abstract: "Create a diagnosis run with explicit resolved context."
  )

  @Option(help: "Path to the .xcodeproj or .xcworkspace to use for this run.")
  var project: String?

  @Option(help: "Scheme name to use for this run.")
  var scheme: String?

  @Option(help: "Simulator UDID or display name to use for this run.")
  var simulator: String?

  @Option(
    help:
      "Run ID to reuse context from. If omitted, xcforge prefers the newest active diagnosis run, otherwise the newest recent one when context reuse is needed."
  )
  var reuseRunId: String?

  @Option(help: "Build configuration used when resolving app context.")
  var configuration: String?

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    do {
      let workflow = DiagnosisStartWorkflow(session: Environment.live.session)
      let result = await workflow.start(
        request: DiagnosisStartRequest(
          project: project,
          scheme: scheme,
          simulator: simulator,
          reuseRunId: reuseRunId,
          configuration: configuration
        )
      )

      if json {
        print(try WorkflowJSONRenderer.renderJSON(result))
      } else {
        print(DiagnosisStartRenderer.render(result))
      }

      if !result.isSuccessfulStart {
        throw ExitCode.failure
      }
    } catch {
      try rethrowOrJSONError(error, json: json)
    }
  }
}

// MARK: - diagnose build

struct DiagnoseBuild: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "build",
    abstract: "Diagnose a build for an existing diagnosis run."
  )

  @Option(help: "Run ID returned by `xcforge diagnose start`.")
  var runId: String

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    do {
      let workflow = DiagnosisBuildWorkflow()
      let result = await workflow.diagnose(
        request: DiagnosisBuildRequest(runId: runId)
      )

      if json {
        print(try WorkflowJSONRenderer.renderJSON(result))
      } else {
        print(DiagnosisBuildRenderer.render(result))
      }

      if result.status == .failed {
        throw ExitCode.failure
      }
    } catch {
      try rethrowOrJSONError(error, json: json)
    }
  }
}

// MARK: - diagnose test

struct DiagnoseTest: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "test",
    abstract: "Diagnose a test run for an existing diagnosis run."
  )

  @Option(help: "Run ID returned by `xcforge diagnose start`.")
  var runId: String

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    do {
      let workflow = DiagnosisTestWorkflow()
      let result = await workflow.diagnose(
        request: DiagnosisTestRequest(runId: runId)
      )

      if json {
        print(try WorkflowJSONRenderer.renderJSON(result))
      } else {
        print(DiagnosisTestRenderer.render(result))
      }

      if result.status != .succeeded {
        throw ExitCode.failure
      }
    } catch {
      try rethrowOrJSONError(error, json: json)
    }
  }
}

// MARK: - diagnose runtime

struct DiagnoseRuntime: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "runtime",
    abstract: "Launch the app for an existing diagnosis run and capture supported runtime signals."
  )

  @Option(help: "Run ID returned by `xcforge diagnose start`.")
  var runId: String

  @Flag(help: "Capture a simulator screenshot as part of runtime diagnosis.")
  var captureScreenshot = false

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    do {
      let env = Environment.live
      let workflow = DiagnosisRuntimeWorkflow(wdaClient: env.wdaClient)
      let result = await workflow.diagnose(
        request: DiagnosisRuntimeRequest(
          runId: runId,
          captureScreenshot: captureScreenshot
        )
      )

      if json {
        print(try WorkflowJSONRenderer.renderJSON(result))
      } else {
        print(DiagnosisRuntimeRenderer.render(result))
      }

      if result.status != .succeeded {
        throw ExitCode.failure
      }
    } catch {
      try rethrowOrJSONError(error, json: json)
    }
  }
}

// MARK: - diagnose status

struct DiagnoseStatus: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "status",
    abstract: "Inspect the status of an active or recent diagnosis run."
  )

  @Option(
    help:
      "Run ID to inspect. If omitted, xcforge prefers the newest active diagnosis run, otherwise the newest recent one."
  )
  var runId: String?

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    do {
      let workflow = DiagnosisStatusWorkflow()
      let result = await workflow.inspect(
        request: DiagnosisStatusRequest(runId: runId)
      )

      if json {
        print(try WorkflowJSONRenderer.renderJSON(result))
      } else {
        print(DiagnosisStatusRenderer.render(result))
      }

      if !result.isSuccessfulInspection {
        throw ExitCode.failure
      }
    } catch {
      try rethrowOrJSONError(error, json: json)
    }
  }
}

// MARK: - diagnose evidence

struct DiagnoseEvidence: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "evidence",
    abstract: "Inspect all available evidence for an active or recent diagnosis run."
  )

  @Option(
    help:
      "Run ID to inspect. If omitted, xcforge prefers the newest active diagnosis run, otherwise the newest recent one."
  )
  var runId: String?

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    do {
      let workflow = DiagnosisStatusWorkflow()
      let result = await workflow.inspectEvidence(
        request: DiagnosisStatusRequest(runId: runId)
      )

      if json {
        print(try WorkflowJSONRenderer.renderJSON(result))
      } else {
        print(DiagnosisEvidenceRenderer.render(result))
      }

      if !result.isSuccessfulInspection {
        throw ExitCode.failure
      }
    } catch {
      try rethrowOrJSONError(error, json: json)
    }
  }
}

// MARK: - diagnose inspect

struct DiagnoseInspect: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "inspect",
    abstract: "Consolidated troubleshooting view for investigating workflow outcomes."
  )

  @Option(
    help:
      "Run ID to inspect. If omitted, xcforge prefers the newest active diagnosis run, otherwise the newest recent one."
  )
  var runId: String?

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    do {
      let workflow = DiagnosisInspectWorkflow()
      let result = await workflow.inspect(
        request: DiagnosisInspectRequest(runId: runId)
      )

      if json {
        print(try WorkflowJSONRenderer.renderJSON(result))
      } else {
        print(DiagnosisInspectRenderer.render(result))
      }

      if !result.isSuccessfulInspection {
        throw ExitCode.failure
      }
    } catch {
      try rethrowOrJSONError(error, json: json)
    }
  }
}

// MARK: - diagnose verify

struct DiagnoseVerify: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "verify",
    abstract: "Rerun validation for a prior diagnosis run."
  )

  @Option(help: "Run ID to rerun validation for.")
  var runId: String

  @Option(help: "Override the project path for this rerun.")
  var project: String?

  @Option(help: "Override the scheme for this rerun.")
  var scheme: String?

  @Option(help: "Override the simulator for this rerun.")
  var simulator: String?

  @Option(help: "Override the build configuration for this rerun.")
  var configuration: String?

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    do {
      let workflow = DiagnosisVerifyWorkflow()
      let result = await workflow.verify(
        request: DiagnosisVerifyRequest(
          runId: runId,
          project: project,
          scheme: scheme,
          simulator: simulator,
          configuration: configuration
        )
      )

      if json {
        print(try WorkflowJSONRenderer.renderJSON(result))
      } else {
        print(DiagnosisVerifyRenderer.render(result))
      }

      if !result.isSuccessfulVerification {
        throw ExitCode.failure
      }
    } catch {
      try rethrowOrJSONError(error, json: json)
    }
  }
}

// MARK: - diagnose compare

struct DiagnoseCompare: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "compare",
    abstract: "Compare an original diagnosis result against the latest rerun."
  )

  @Option(
    help:
      "Run ID to compare. If omitted, xcforge prefers the newest active diagnosis run, otherwise the newest recent one."
  )
  var runId: String?

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    do {
      let workflow = DiagnosisCompareWorkflow()
      let result = await workflow.compare(
        request: DiagnosisCompareRequest(runId: runId)
      )

      if json {
        print(try WorkflowJSONRenderer.renderJSON(result))
      } else {
        print(DiagnosisCompareRenderer.render(result))
      }

      if !result.isSuccessfulComparison {
        throw ExitCode.failure
      }
    } catch {
      try rethrowOrJSONError(error, json: json)
    }
  }
}

// MARK: - diagnose result

struct DiagnoseResult: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "result",
    abstract: "Return the final proof-oriented result for a diagnosis run."
  )

  @Option(help: "Run ID to inspect. If omitted, xcforge uses the newest terminal diagnosis run.")
  var runId: String?

  @Flag(help: "Emit the final result as machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    do {
      let workflow = DiagnosisFinalResultWorkflow()
      let result = await workflow.assemble(
        request: DiagnosisFinalResultRequest(runId: runId)
      )

      if json {
        print(try WorkflowJSONRenderer.renderJSON(result))
      } else {
        print(DiagnosisFinalResultRenderer.render(result))
      }

      if !result.isSuccessfulFinalResult {
        throw ExitCode.failure
      }
    } catch {
      try rethrowOrJSONError(error, json: json)
    }
  }
}

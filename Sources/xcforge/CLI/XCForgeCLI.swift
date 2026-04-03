import ArgumentParser
import Foundation
import xcforgeCore

struct XCForgeCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "xcforge",
        abstract: "CLI-first workflow entrypoints for xcforge.",
        subcommands: [Build.self, Test.self, BuildTest.self, Sim.self, Diagnose.self, Defaults.self, Console.self, Git.self, Logs.self, Screenshot.self, UI.self, Accessibility.self, Plan.self]
    )
}

struct Defaults: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "defaults",
        abstract: "Show, set, or clear persisted workflow defaults.",
        subcommands: [DefaultsShow.self, DefaultsSet.self, DefaultsClear.self],
        defaultSubcommand: DefaultsShow.self
    )
}

struct DefaultsShow: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Display current persisted workflow defaults."
    )

    mutating func run() throws {
        try runAsync {
            let env = Environment.live
            print(await env.session.showDefaults())
        }
    }
}

struct DefaultsSet: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "set",
        abstract: "Set one or more persisted workflow defaults."
    )

    @Option(help: "Default project path (.xcodeproj or .xcworkspace).")
    var project: String?

    @Option(help: "Default scheme name.")
    var scheme: String?

    @Option(help: "Default simulator name or UDID.")
    var simulator: String?

    mutating func run() throws {
        let project = self.project
        let scheme = self.scheme
        let simulator = self.simulator

        guard project != nil || scheme != nil || simulator != nil else {
            print("No defaults specified. Use --project, --scheme, or --simulator.")
            throw ExitCode.validationFailure
        }

        try runAsync {
            let env = Environment.live
            await env.session.setDefaults(
                project: project, scheme: scheme, simulator: simulator
            )
            print(await env.session.showDefaults())
        }
    }
}

struct DefaultsClear: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "clear",
        abstract: "Clear all persisted workflow defaults."
    )

    mutating func run() throws {
        try runAsync {
            let env = Environment.live
            await env.session.clearDefaults()
            print("Defaults cleared. Auto-detection will be used for all parameters.")
        }
    }
}

struct Diagnose: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "diagnose",
        abstract: "Start diagnosis workflows and inspect or summarize their results.",
        subcommands: [DiagnoseStart.self, DiagnoseBuild.self, DiagnoseTest.self, DiagnoseRuntime.self, DiagnoseStatus.self, DiagnoseEvidence.self, DiagnoseInspect.self, DiagnoseVerify.self, DiagnoseCompare.self, DiagnoseResult.self]
    )
}

struct DiagnoseStart: ParsableCommand {
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

    @Option(help: "Run ID to reuse context from. If omitted, xcforge prefers the newest active diagnosis run, otherwise the newest recent one when context reuse is needed.")
    var reuseRunId: String?

    @Option(help: "Build configuration used when resolving app context.")
    var configuration: String?

    @Flag(help: "Emit the result as machine-readable JSON.")
    var json = false

    mutating func run() throws {
        let project = self.project
        let scheme = self.scheme
        let simulator = self.simulator
        let reuseRunId = self.reuseRunId
        let configuration = self.configuration
        let json = self.json

        try runAsyncJSON(json: json) {
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
        }
    }
}

struct DiagnoseBuild: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "build",
        abstract: "Diagnose a build for an existing diagnosis run."
    )

    @Option(help: "Run ID returned by `xcforge diagnose start`.")
    var runId: String

    @Flag(help: "Emit the result as machine-readable JSON.")
    var json = false

    mutating func run() throws {
        let runId = self.runId
        let json = self.json

        try runAsyncJSON(json: json) {
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
        }
    }
}

struct DiagnoseTest: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "test",
        abstract: "Diagnose a test run for an existing diagnosis run."
    )

    @Option(help: "Run ID returned by `xcforge diagnose start`.")
    var runId: String

    @Flag(help: "Emit the result as machine-readable JSON.")
    var json = false

    mutating func run() throws {
        let runId = self.runId
        let json = self.json

        try runAsyncJSON(json: json) {
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
        }
    }
}

struct DiagnoseRuntime: ParsableCommand {
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

    mutating func run() throws {
        let runId = self.runId
        let captureScreenshot = self.captureScreenshot
        let json = self.json

        try runAsyncJSON(json: json) {
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
        }
    }
}

struct DiagnoseStatus: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Inspect the status of an active or recent diagnosis run."
    )

    @Option(help: "Run ID to inspect. If omitted, xcforge prefers the newest active diagnosis run, otherwise the newest recent one.")
    var runId: String?

    @Flag(help: "Emit the result as machine-readable JSON.")
    var json = false

    mutating func run() throws {
        let runId = self.runId
        let json = self.json

        try runAsyncJSON(json: json) {
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
        }
    }
}

struct DiagnoseEvidence: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "evidence",
        abstract: "Inspect all available evidence for an active or recent diagnosis run."
    )

    @Option(help: "Run ID to inspect. If omitted, xcforge prefers the newest active diagnosis run, otherwise the newest recent one.")
    var runId: String?

    @Flag(help: "Emit the result as machine-readable JSON.")
    var json = false

    mutating func run() throws {
        let runId = self.runId
        let json = self.json

        try runAsyncJSON(json: json) {
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
        }
    }
}

struct DiagnoseInspect: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "inspect",
        abstract: "Consolidated troubleshooting view for investigating workflow outcomes."
    )

    @Option(help: "Run ID to inspect. If omitted, xcforge prefers the newest active diagnosis run, otherwise the newest recent one.")
    var runId: String?

    @Flag(help: "Emit the result as machine-readable JSON.")
    var json = false

    mutating func run() throws {
        let runId = self.runId
        let json = self.json

        try runAsyncJSON(json: json) {
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
        }
    }
}

struct DiagnoseVerify: ParsableCommand {
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

    mutating func run() throws {
        let runId = self.runId
        let project = self.project
        let scheme = self.scheme
        let simulator = self.simulator
        let configuration = self.configuration
        let json = self.json

        try runAsyncJSON(json: json) {
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
        }
    }
}

struct DiagnoseCompare: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "compare",
        abstract: "Compare an original diagnosis result against the latest rerun."
    )

    @Option(help: "Run ID to compare. If omitted, xcforge prefers the newest active diagnosis run, otherwise the newest recent one.")
    var runId: String?

    @Flag(help: "Emit the result as machine-readable JSON.")
    var json = false

    mutating func run() throws {
        let runId = self.runId
        let json = self.json

        try runAsyncJSON(json: json) {
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
        }
    }
}

struct DiagnoseResult: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "result",
        abstract: "Return the final proof-oriented result for a diagnosis run."
    )

    @Option(help: "Run ID to inspect. If omitted, xcforge uses the newest terminal diagnosis run.")
    var runId: String?

    @Flag(help: "Emit the final result as machine-readable JSON.")
    var json = false

    mutating func run() throws {
        let runId = self.runId
        let json = self.json

        try runAsyncJSON(json: json) {
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
        }
    }
}

/// Returns true when output should be JSON: either `--json` was passed or stdout is not a terminal.
func shouldOutputJSON(flag: Bool) -> Bool {
    flag || !isatty(STDOUT_FILENO).asBool
}

private extension Int32 {
    var asBool: Bool { self != 0 }
}

func runAsync(_ operation: @escaping @Sendable () async throws -> Void) throws {
    let semaphore = DispatchSemaphore(value: 0)
    let box = AsyncResultBox<Void>()

    Task {
        defer { semaphore.signal() }
        do {
            try await operation()
            box.result = .success(())
        } catch {
            box.result = .failure(error)
        }
    }

    let timeoutSeconds = 120
    let waitResult = semaphore.wait(timeout: .now() + .seconds(timeoutSeconds))
    if waitResult == .timedOut {
        throw ValidationError("Async operation timed out after \(timeoutSeconds) seconds")
    }

    if case let .failure(error) = box.result {
        throw error
    }
}

/// Variant of `runAsync` that catches errors and emits a JSON error envelope on stdout
/// when the `--json` flag is active, instead of letting ArgumentParser render plain text.
func runAsyncJSON(json: Bool, _ operation: @escaping @Sendable () async throws -> Void) throws {
    do {
        try runAsync(operation)
    } catch let error as ExitCode {
        throw error  // ExitCode is already handled — don't wrap it
    } catch {
        guard json else { throw error }
        let envelope = CLIErrorEnvelope(error: "\(error)", code: errorCode(for: error))
        if let data = try? JSONEncoder().encode(envelope),
           let jsonString = String(data: data, encoding: .utf8)
        {
            print(jsonString)
        }
        throw ExitCode.failure
    }
}

struct CLIErrorEnvelope: Encodable {
    let error: String
    let code: String
}

private func errorCode(for error: Error) -> String {
    let typeName = String(describing: type(of: error))
    if typeName.contains("ResolverError") ||
       typeName.contains("CoverageError") ||
       typeName.contains("TestDiscoveryError") ||
       typeName.contains("BuildSettingsError") ||
       typeName.contains("ToolValidationError") { return "resolution_failed" }
    if typeName.contains("ValidationError") { return "validation_error" }
    if error is EncodingError { return "encoding_failed" }
    if error is DecodingError { return "decoding_failed" }
    return "execution_failed"
}

final class AsyncResultBox<T>: @unchecked Sendable {
    var result: Result<T, Error>?
}

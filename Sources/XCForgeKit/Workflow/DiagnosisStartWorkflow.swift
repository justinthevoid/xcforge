import Foundation

/// Error for developer tool availability failures (xcrun, simctl, xcodebuild).
struct ToolValidationError: Error, CustomStringConvertible {
  let description: String
  init(_ message: String) { self.description = message }
}

public struct DiagnosisStartWorkflow: Sendable {
  typealias ProjectResolver = @Sendable () async throws -> String
  typealias SchemeResolver = @Sendable (String) async throws -> String
  typealias SchemeValidator = @Sendable (String, String) async throws -> Bool
  typealias SimulatorResolver = @Sendable () async throws -> String
  typealias ReusableRunResolver = @Sendable (String?) async throws -> WorkflowRunRecord?
  typealias ToolingValidator = @Sendable () async throws -> Void
  typealias ProjectPreflightValidator = @Sendable (String) async throws -> Void
  typealias SchemePreflightValidator = @Sendable (String, String) async throws -> Void
  typealias SimulatorPreflightValidator = @Sendable (String) async throws -> Void
  typealias SimulatorPreparationResolver =
    @Sendable (String) async throws -> WorkflowSimulatorPreparation
  typealias AppResolver = @Sendable (String, String, String, String) async throws -> AppContext
  typealias PersistRun = @Sendable (WorkflowRunRecord) throws -> URL
  typealias NowProvider = @Sendable () -> Date
  typealias IDProvider = @Sendable () -> String

  private let session: SessionState
  private let projectResolver: ProjectResolver
  private let schemeResolver: SchemeResolver
  private let schemeValidator: SchemeValidator
  private let simulatorResolver: SimulatorResolver
  private let reusableRunResolver: ReusableRunResolver
  private let toolingValidator: ToolingValidator
  private let projectPreflightValidator: ProjectPreflightValidator
  private let schemePreflightValidator: SchemePreflightValidator
  private let simulatorPreflightValidator: SimulatorPreflightValidator
  private let simulatorPreparationResolver: SimulatorPreparationResolver
  private let appContextResolver: AppResolver
  private let persistRun: PersistRun
  private let now: NowProvider
  private let makeID: IDProvider

  public init(session: SessionState) {
    self.init(
      session: session,
      resolveProject: AutoDetect.project,
      resolveScheme: AutoDetect.scheme(project:),
      validateScheme: { scheme, project in
        try await AutoDetect.availableSchemes(project: project).contains(scheme)
      },
      resolveSimulator: AutoDetect.simulator,
      resolveReusableRun: { runId in
        let store = RunStore()
        if let runId {
          let trimmed = runId.trimmingCharacters(in: .whitespacesAndNewlines)
          guard !trimmed.isEmpty else {
            throw WorkflowContextResolutionError(
              field: .run,
              classification: .resolutionFailed,
              message: "Reuse run ID must not be empty.",
              options: []
            )
          }
          do {
            return try store.reusableDiagnosisRun(runId: trimmed)
          } catch let error as CocoaError
            where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile
          {
            throw WorkflowContextResolutionError(
              field: .run,
              classification: .notFound,
              message: "No diagnosis run was found for run ID \(trimmed).",
              options: []
            )
          } catch {
            throw WorkflowContextResolutionError(
              field: .run,
              classification: .resolutionFailed,
              message: "\(error)",
              options: Self.extractOptions(from: error)
            )
          }
        }
        return try store.reusableDiagnosisRun()
      },
      validateTooling: Self.validateToolingAvailability,
      validateProject: { project in
        try AutoDetect.validateProject(project)
      },
      validateResolvedScheme: AutoDetect.validateScheme(_:project:),
      validateResolvedSimulator: AutoDetect.validateSimulator(_:),
      prepareSimulatorContext: AutoDetect.prepareSimulatorContext,
      resolveAppContext: { project, scheme, simulator, configuration in
        let buildInfo = try await BuildTools.resolveBuildProductInfo(
          project: project,
          scheme: scheme,
          simulator: simulator,
          configuration: configuration,
          env: .live
        )
        return AppContext(bundleId: buildInfo.bundleId, appPath: buildInfo.appPath)
      },
      persistRun: { run in try RunStore().save(run) },
      now: Date.init,
      makeID: { UUID().uuidString.lowercased() }
    )
  }

  init(
    session: SessionState = SessionState(),
    resolveProject: @escaping ProjectResolver = AutoDetect.project,
    resolveScheme: @escaping SchemeResolver = AutoDetect.scheme(project:),
    validateScheme: @escaping SchemeValidator = { scheme, project in
      try await AutoDetect.availableSchemes(project: project).contains(scheme)
    },
    resolveSimulator: @escaping SimulatorResolver = AutoDetect.simulator,
    resolveReusableRun: @escaping ReusableRunResolver = { _ in nil },
    validateTooling: @escaping ToolingValidator = Self.validateToolingAvailability,
    validateProject: @escaping ProjectPreflightValidator = { project in
      try AutoDetect.validateProject(project)
    },
    validateResolvedScheme: @escaping SchemePreflightValidator = AutoDetect.validateScheme(
      _:project:),
    validateResolvedSimulator: @escaping SimulatorPreflightValidator = AutoDetect.validateSimulator(
      _:),
    prepareSimulatorContext: @escaping SimulatorPreparationResolver = AutoDetect
      .prepareSimulatorContext,
    resolveAppContext: @escaping AppResolver = { project, scheme, simulator, configuration in
      let buildInfo = try await BuildTools.resolveBuildProductInfo(
        project: project,
        scheme: scheme,
        simulator: simulator,
        configuration: configuration,
        env: .live
      )
      return AppContext(bundleId: buildInfo.bundleId, appPath: buildInfo.appPath)
    },
    persistRun: @escaping PersistRun = { run in try RunStore().save(run) },
    now: @escaping NowProvider = Date.init,
    makeID: @escaping IDProvider = { UUID().uuidString.lowercased() }
  ) {
    self.session = session
    self.projectResolver = resolveProject
    self.schemeResolver = resolveScheme
    self.schemeValidator = validateScheme
    self.simulatorResolver = resolveSimulator
    self.reusableRunResolver = resolveReusableRun
    self.toolingValidator = validateTooling
    self.projectPreflightValidator = validateProject
    self.schemePreflightValidator = validateResolvedScheme
    self.simulatorPreflightValidator = validateResolvedSimulator
    self.simulatorPreparationResolver = prepareSimulatorContext
    self.appContextResolver = resolveAppContext
    self.persistRun = persistRun
    self.now = now
    self.makeID = makeID
  }

  public func start(request: DiagnosisStartRequest) async -> DiagnosisStartResult {
    let defaults = await session.workflowDefaultsSnapshot()

    do {
      let timestamp = now()
      let shouldReuseContext = Self.shouldReuseContext(request)
      let reusableRun = try await reusableRunResolver(
        shouldReuseContext ? request.reuseRunId : nil
      )
      let contextResolution = try await resolveContext(
        request: request,
        defaults: defaults,
        reusableRun: reusableRun,
        validatedAt: timestamp
      )
      let (appResolution, simulatorPreparation, environmentPreflight) =
        try await runEnvironmentPreflight(
          project: contextResolution.project,
          scheme: contextResolution.scheme,
          simulator: contextResolution.simulator,
          configuration: contextResolution.configuration,
          reusedAppContext: contextResolution.reuseAppContext
            ? reusableRun?.resolvedContext.app : nil,
          contextProvenance: contextResolution.contextProvenance,
          reusableRun: reusableRun,
          validatedAt: timestamp
        )
      let resolvedContext = ResolvedWorkflowContext(
        project: contextResolution.project,
        scheme: contextResolution.scheme,
        simulator: simulatorPreparation.selected,
        configuration: contextResolution.configuration,
        app: appResolution.value,
        simulatorPreparation: simulatorPreparation
      )
      let contextProvenance = WorkflowContextProvenance(
        sourceRunId: contextResolution.contextProvenance.sourceRunId,
        sourceAttemptId: contextResolution.contextProvenance.sourceAttemptId,
        fields: contextResolution.contextProvenance.fields + [appResolution.provenance]
      )

      let runId = makeID()
      let attemptId = makeID()
      let attempt = WorkflowAttemptRecord(
        attemptId: attemptId,
        attemptNumber: 1,
        phase: .diagnosisStart,
        startedAt: timestamp,
        status: .inProgress
      )
      let run = WorkflowRunRecord(
        runId: runId,
        workflow: .diagnosis,
        phase: .diagnosisStart,
        status: .inProgress,
        createdAt: timestamp,
        updatedAt: timestamp,
        attempt: attempt,
        resolvedContext: resolvedContext,
        environmentPreflight: environmentPreflight,
        contextProvenance: contextProvenance,
        attemptHistory: [
          WorkflowAttemptSnapshot(
            attempt: attempt,
            phase: .diagnosisStart,
            status: .inProgress,
            resolvedContext: resolvedContext,
            recordedAt: timestamp
          )
        ],
        actionHistory: [
          WorkflowActionRecord(
            kind: .runCreated,
            phase: .diagnosisStart,
            attemptId: attemptId,
            timestamp: timestamp
          ),
          WorkflowActionRecord(
            kind: .contextResolved,
            phase: .diagnosisStart,
            attemptId: attemptId,
            timestamp: timestamp,
            detail:
              "Resolved project: \(resolvedContext.project), scheme: \(resolvedContext.scheme)"
          ),
        ]
      )
      let persistedURL: URL
      do {
        persistedURL = try persistRun(run)
      } catch {
        return DiagnosisStartResult(
          status: .failed,
          runId: runId,
          attemptId: attemptId,
          resolvedContext: resolvedContext,
          environmentPreflight: environmentPreflight,
          failure: WorkflowFailure(
            field: .workflow,
            classification: .executionFailed,
            message:
              "xcforge validated the local environment but could not persist the run record: \(error)",
            observed: ObservedFailureEvidence(
              summary:
                "xcforge validated the local environment but could not persist the run record: \(error)",
              detail: String(describing: error)
            ),
            inferred: InferredFailureConclusion(
              summary:
                "The run record could not be written to disk. A file-system or permissions issue may be preventing persistence."
            ),
            recoverability: .retryAfterFix
          ),
          persistedRunPath: nil
        )
      }

      return DiagnosisStartResult(
        status: .inProgress,
        runId: runId,
        attemptId: attemptId,
        resolvedContext: resolvedContext,
        contextProvenance: contextProvenance,
        environmentPreflight: environmentPreflight,
        failure: nil,
        persistedRunPath: persistedURL.path
      )
    } catch let error as WorkflowContextResolutionError {
      return DiagnosisStartResult(
        status: error.status,
        runId: nil,
        attemptId: nil,
        resolvedContext: nil,
        contextProvenance: error.contextProvenance,
        environmentPreflight: error.preflight,
        failure: WorkflowFailure(
          field: error.field,
          classification: error.classification,
          message: error.message,
          options: error.options,
          observed: ObservedFailureEvidence(summary: error.message),
          inferred: nil,
          recoverability: error.classification.recoverability
        ),
        persistedRunPath: nil
      )
    } catch {
      return DiagnosisStartResult(
        status: .failed,
        runId: nil,
        attemptId: nil,
        resolvedContext: nil,
        contextProvenance: nil,
        environmentPreflight: nil,
        failure: WorkflowFailure(
          field: .workflow,
          classification: .resolutionFailed,
          message: "\(error)",
          observed: ObservedFailureEvidence(
            summary: "\(error)"
          ),
          inferred: InferredFailureConclusion(
            summary:
              "An unexpected error occurred during workflow context resolution. The underlying cause may require investigation."
          ),
          recoverability: .actionRequired
        ),
        persistedRunPath: nil
      )
    }
  }

  private func runEnvironmentPreflight(
    project: String,
    scheme: String,
    simulator: String,
    configuration: String,
    reusedAppContext: AppContext?,
    contextProvenance: WorkflowContextProvenance?,
    reusableRun: WorkflowRunRecord?,
    validatedAt: Date
  ) async throws -> (
    ResolvedContextValue<AppContext>, WorkflowSimulatorPreparation, WorkflowEnvironmentPreflight
  ) {
    var checks: [WorkflowEnvironmentCheck] = []

    do {
      try await toolingValidator()
      checks.append(
        WorkflowEnvironmentCheck(
          kind: .tooling,
          field: .tooling,
          status: .passed,
          message: "Required local Apple developer tooling is available."
        )
      )
    } catch {
      throw Self.preflightFailure(
        kind: .tooling,
        field: .tooling,
        classification: Self.classifyToolingError(error),
        error: error,
        contextProvenance: contextProvenance,
        validatedAt: validatedAt,
        priorChecks: checks
      )
    }

    do {
      try await projectPreflightValidator(project)
      checks.append(
        WorkflowEnvironmentCheck(
          kind: .project,
          field: .project,
          status: .passed,
          message: "Project path is available: \(project)"
        )
      )
    } catch {
      throw Self.preflightFailure(
        kind: .project,
        field: .project,
        classification: Self.classifyProjectValidationError(error),
        error: error,
        contextProvenance: contextProvenance,
        validatedAt: validatedAt,
        priorChecks: checks
      )
    }

    do {
      try await schemePreflightValidator(scheme, project)
      checks.append(
        WorkflowEnvironmentCheck(
          kind: .scheme,
          field: .scheme,
          status: .passed,
          message: "Scheme '\(scheme)' is available for the requested project."
        )
      )
    } catch {
      throw Self.preflightFailure(
        kind: .scheme,
        field: .scheme,
        classification: Self.classifySchemeValidationError(error),
        error: error,
        contextProvenance: contextProvenance,
        validatedAt: validatedAt,
        priorChecks: checks
      )
    }

    do {
      try await simulatorPreflightValidator(simulator)
    } catch {
      throw Self.preflightFailure(
        kind: .simulator,
        field: .simulator,
        classification: Self.classifySimulatorValidationError(error),
        error: error,
        contextProvenance: contextProvenance,
        validatedAt: validatedAt,
        priorChecks: checks
      )
    }

    let simulatorPreparation: WorkflowSimulatorPreparation
    do {
      simulatorPreparation = try await simulatorPreparationResolver(simulator)
      checks.append(
        WorkflowEnvironmentCheck(
          kind: .simulator,
          field: .simulator,
          status: .passed,
          message:
            "Simulator target prepared for workflow use: \(simulatorPreparation.displayName) (\(simulatorPreparation.selected))."
        )
      )
    } catch {
      throw Self.preflightFailure(
        kind: .simulator,
        field: .simulator,
        classification: Self.classifySimulatorPreparationError(error),
        error: error,
        contextProvenance: contextProvenance,
        validatedAt: validatedAt,
        priorChecks: checks
      )
    }

    let attemptedAppProvenance: WorkflowContextFieldProvenance =
      if reusedAppContext != nil {
        Self.fieldProvenance(
          field: .app,
          source: .reusedRun,
          sourceRun: reusableRun
        )
      } else {
        Self.fieldProvenance(
          field: .app,
          source: .derived,
          detail: "Resolved from project, scheme, simulator, and configuration."
        )
      }

    let app: AppContext
    do {
      if let reusedAppContext {
        app = reusedAppContext
      } else {
        app = try await appContextResolver(
          project, scheme, simulatorPreparation.selected, configuration)
      }
      checks.append(
        WorkflowEnvironmentCheck(
          kind: .appContext,
          field: .app,
          status: .passed,
          message:
            "App context resolved for scheme '\(scheme)' and configuration '\(configuration)'."
        )
      )
    } catch {
      let classification = Self.classifyAppContextError(error)
      let status: WorkflowEnvironmentPreflightStatus =
        classification == .unsupportedContext ? .unsupported : .failed
      let failedCheck = WorkflowEnvironmentCheck(
        kind: .appContext,
        field: .app,
        status: status,
        message: "\(error)"
      )
      throw WorkflowContextResolutionError(
        field: .app,
        classification: classification,
        message: "\(error)",
        options: Self.extractOptions(from: error),
        preflight: WorkflowEnvironmentPreflight(
          status: status,
          summary: Self.preflightSummary(for: .app, status: status),
          checks: checks + [failedCheck],
          validatedAt: validatedAt
        ),
        contextProvenance: WorkflowContextProvenance(
          sourceRunId: contextProvenance?.sourceRunId ?? reusableRun?.runId,
          sourceAttemptId: contextProvenance?.sourceAttemptId ?? reusableRun?.attempt.attemptId,
          fields: (contextProvenance?.fields ?? []) + [attemptedAppProvenance]
        )
      )
    }

    return (
      ResolvedContextValue(
        value: app,
        provenance: attemptedAppProvenance
      ),
      simulatorPreparation,
      WorkflowEnvironmentPreflight(
        status: .passed,
        summary: "Environment preflight passed for the resolved diagnosis context.",
        checks: checks,
        validatedAt: validatedAt
      )
    )
  }

  private struct ResolvedContextValue<Value> {
    let value: Value
    let provenance: WorkflowContextFieldProvenance
  }

  private struct ResolvedStartContext {
    let project: String
    let scheme: String
    let simulator: String
    let configuration: String
    let contextProvenance: WorkflowContextProvenance
    let reuseAppContext: Bool
  }

  private func resolveContext(
    request: DiagnosisStartRequest,
    defaults: WorkflowDefaultsSnapshot,
    reusableRun: WorkflowRunRecord?,
    validatedAt _: Date
  ) async throws -> ResolvedStartContext {
    var provenanceFields: [WorkflowContextFieldProvenance] = []

    let project = try await resolveProject(
      request.project,
      defaults: defaults,
      reusableRun: reusableRun,
      currentProvenanceFields: provenanceFields
    )
    provenanceFields.append(project.provenance)

    let scheme = try await resolveScheme(
      request.scheme,
      project: project.value,
      defaults: defaults,
      reusableRun: reusableRun,
      currentProvenanceFields: provenanceFields
    )
    provenanceFields.append(scheme.provenance)

    let simulator = try await resolveSimulator(
      request.simulator,
      defaults: defaults,
      reusableRun: reusableRun,
      currentProvenanceFields: provenanceFields
    )
    provenanceFields.append(simulator.provenance)

    let configuration = try await resolveConfiguration(
      request.configuration,
      reusableRun: reusableRun,
      currentProvenanceFields: provenanceFields
    )
    provenanceFields.append(configuration.provenance)

    let reuseAppContext = Self.shouldReuseAppContext(from: provenanceFields)
    let hasReusedField = provenanceFields.contains { $0.source == .reusedRun }

    return ResolvedStartContext(
      project: project.value,
      scheme: scheme.value,
      simulator: simulator.value,
      configuration: configuration.value,
      contextProvenance: WorkflowContextProvenance(
        sourceRunId: hasReusedField ? reusableRun?.runId : nil,
        sourceAttemptId: hasReusedField ? reusableRun?.attempt.attemptId : nil,
        fields: provenanceFields
      ),
      reuseAppContext: reuseAppContext
    )
  }

  private func resolveProject(
    _ explicit: String?,
    defaults: WorkflowDefaultsSnapshot,
    reusableRun: WorkflowRunRecord?,
    currentProvenanceFields: [WorkflowContextFieldProvenance]
  ) async throws -> ResolvedContextValue<String> {
    if let explicit = try Self.resolveExplicitValue(explicit, field: .project) {
      return ResolvedContextValue(
        value: explicit,
        provenance: Self.fieldProvenance(field: .project, source: .explicit)
      )
    }

    if let reusableRun {
      let value = reusableRun.resolvedContext.project
      do {
        try await projectPreflightValidator(value)
      } catch {
        throw Self.contextResolutionError(
          field: .project,
          classification: Self.classifyProjectValidationError(error),
          error: error,
          reusableRun: reusableRun,
          provenanceFields: currentProvenanceFields,
          attemptedProvenance: Self.fieldProvenance(
            field: .project,
            source: .reusedRun,
            sourceRun: reusableRun
          )
        )
      }
      return ResolvedContextValue(
        value: value,
        provenance: Self.fieldProvenance(
          field: .project,
          source: .reusedRun,
          sourceRun: reusableRun
        )
      )
    }

    if let project = Self.normalized(defaults.project) {
      return ResolvedContextValue(
        value: project,
        provenance: Self.fieldProvenance(field: .project, source: .sessionDefault)
      )
    }

    do {
      return ResolvedContextValue(
        value: try await projectResolver(),
        provenance: Self.fieldProvenance(field: .project, source: .autoDetected)
      )
    } catch {
      throw Self.contextResolutionError(
        field: .project,
        classification: .resolutionFailed,
        error: error,
        reusableRun: reusableRun,
        provenanceFields: currentProvenanceFields,
        attemptedProvenance: Self.fieldProvenance(field: .project, source: .autoDetected)
      )
    }
  }

  private func resolveScheme(
    _ explicit: String?,
    project: String,
    defaults: WorkflowDefaultsSnapshot,
    reusableRun: WorkflowRunRecord?,
    currentProvenanceFields: [WorkflowContextFieldProvenance]
  ) async throws -> ResolvedContextValue<String> {
    if let explicit = try Self.resolveExplicitValue(explicit, field: .scheme) {
      return ResolvedContextValue(
        value: explicit,
        provenance: Self.fieldProvenance(field: .scheme, source: .explicit)
      )
    }

    if let reusableRun {
      let value = reusableRun.resolvedContext.scheme
      let isValid = (try? await schemeValidator(value, project)) == true
      guard isValid else {
        throw Self.contextResolutionError(
          field: .scheme,
          classification: .unsupportedContext,
          message:
            "Reused scheme '\(value)' from run \(reusableRun.runId) is not valid for project \(project).",
          reusableRun: reusableRun,
          provenanceFields: currentProvenanceFields,
          attemptedProvenance: Self.fieldProvenance(
            field: .scheme,
            source: .reusedRun,
            sourceRun: reusableRun
          )
        )
      }
      return ResolvedContextValue(
        value: value,
        provenance: Self.fieldProvenance(
          field: .scheme,
          source: .reusedRun,
          sourceRun: reusableRun
        )
      )
    }

    if let scheme = Self.normalized(defaults.scheme),
      (try? await schemeValidator(scheme, project)) == true
    {
      return ResolvedContextValue(
        value: scheme,
        provenance: Self.fieldProvenance(field: .scheme, source: .sessionDefault)
      )
    }

    do {
      return ResolvedContextValue(
        value: try await schemeResolver(project),
        provenance: Self.fieldProvenance(field: .scheme, source: .autoDetected)
      )
    } catch {
      throw Self.contextResolutionError(
        field: .scheme,
        classification: .resolutionFailed,
        error: error,
        reusableRun: reusableRun,
        provenanceFields: currentProvenanceFields,
        attemptedProvenance: Self.fieldProvenance(field: .scheme, source: .autoDetected)
      )
    }
  }

  private func resolveSimulator(
    _ explicit: String?,
    defaults: WorkflowDefaultsSnapshot,
    reusableRun: WorkflowRunRecord?,
    currentProvenanceFields: [WorkflowContextFieldProvenance]
  ) async throws -> ResolvedContextValue<String> {
    if let explicit = try Self.resolveExplicitValue(explicit, field: .simulator) {
      return ResolvedContextValue(
        value: explicit,
        provenance: Self.fieldProvenance(field: .simulator, source: .explicit)
      )
    }

    if let reusableRun {
      let value = reusableRun.resolvedContext.simulator
      do {
        try await simulatorPreflightValidator(value)
      } catch {
        throw Self.contextResolutionError(
          field: .simulator,
          classification: Self.classifySimulatorValidationError(error),
          error: error,
          reusableRun: reusableRun,
          provenanceFields: currentProvenanceFields,
          attemptedProvenance: Self.fieldProvenance(
            field: .simulator,
            source: .reusedRun,
            sourceRun: reusableRun
          )
        )
      }
      return ResolvedContextValue(
        value: value,
        provenance: Self.fieldProvenance(
          field: .simulator,
          source: .reusedRun,
          sourceRun: reusableRun
        )
      )
    }

    if let simulator = Self.normalized(defaults.simulator) {
      return ResolvedContextValue(
        value: simulator,
        provenance: Self.fieldProvenance(field: .simulator, source: .sessionDefault)
      )
    }

    do {
      return ResolvedContextValue(
        value: try await simulatorResolver(),
        provenance: Self.fieldProvenance(field: .simulator, source: .autoDetected)
      )
    } catch {
      throw Self.contextResolutionError(
        field: .simulator,
        classification: .resolutionFailed,
        error: error,
        reusableRun: reusableRun,
        provenanceFields: currentProvenanceFields,
        attemptedProvenance: Self.fieldProvenance(field: .simulator, source: .autoDetected)
      )
    }
  }

  private func resolveConfiguration(
    _ explicit: String?,
    reusableRun: WorkflowRunRecord?,
    currentProvenanceFields _: [WorkflowContextFieldProvenance]
  ) async throws -> ResolvedContextValue<String> {
    if let explicit = try Self.resolveExplicitValue(explicit, field: .build) {
      return ResolvedContextValue(
        value: explicit,
        provenance: Self.fieldProvenance(field: .build, source: .explicit)
      )
    }

    if let reusableRun {
      return ResolvedContextValue(
        value: reusableRun.resolvedContext.configuration,
        provenance: Self.fieldProvenance(
          field: .build,
          source: .reusedRun,
          sourceRun: reusableRun
        )
      )
    }

    return ResolvedContextValue(
      value: "Debug",
      provenance: Self.fieldProvenance(field: .build, source: .workflowDefault)
    )
  }

  private func resolveAppContext(
    project: String,
    scheme: String,
    simulator: String,
    configuration: String,
    reusableRun: WorkflowRunRecord?,
    reuseAppContext: Bool,
    currentProvenanceFields: [WorkflowContextFieldProvenance]
  ) async throws -> ResolvedContextValue<AppContext> {
    if reuseAppContext, let reusableRun {
      let app = reusableRun.resolvedContext.app
      guard FileManager.default.fileExists(atPath: app.appPath) else {
        throw Self.contextResolutionError(
          field: .app,
          classification: .notFound,
          message:
            "Reused app context from run \(reusableRun.runId) is no longer available at \(app.appPath).",
          reusableRun: reusableRun,
          provenanceFields: currentProvenanceFields,
          attemptedProvenance: Self.fieldProvenance(
            field: .app,
            source: .reusedRun,
            sourceRun: reusableRun
          )
        )
      }
      if let bundle = Bundle(path: app.appPath),
        let bundleId = bundle.bundleIdentifier,
        bundleId != app.bundleId
      {
        throw Self.contextResolutionError(
          field: .app,
          classification: .unsupportedContext,
          message:
            "Reused app context from run \(reusableRun.runId) no longer matches the app bundle at \(app.appPath).",
          reusableRun: reusableRun,
          provenanceFields: currentProvenanceFields,
          attemptedProvenance: Self.fieldProvenance(
            field: .app,
            source: .reusedRun,
            sourceRun: reusableRun
          )
        )
      }
      return ResolvedContextValue(
        value: app,
        provenance: Self.fieldProvenance(
          field: .app,
          source: .reusedRun,
          sourceRun: reusableRun
        )
      )
    }

    do {
      let app = try await appContextResolver(project, scheme, simulator, configuration)
      return ResolvedContextValue(
        value: app,
        provenance: Self.fieldProvenance(
          field: .app,
          source: .derived,
          detail: "Resolved from project, scheme, simulator, and configuration."
        )
      )
    } catch {
      throw Self.contextResolutionError(
        field: .app,
        classification: Self.classifyAppContextError(error),
        error: error,
        reusableRun: reusableRun,
        provenanceFields: currentProvenanceFields,
        attemptedProvenance: Self.fieldProvenance(field: .app, source: .derived)
      )
    }
  }

  private static func shouldReuseContext(_ request: DiagnosisStartRequest) -> Bool {
    request.reuseRunId != nil
      || request.project == nil
      || request.scheme == nil
      || request.simulator == nil
      || request.configuration == nil
  }

  private static func shouldReuseAppContext(from fields: [WorkflowContextFieldProvenance]) -> Bool {
    let reusableFields: Set<ContextField> = [.project, .scheme, .simulator, .build]
    let reusedFields = Set(fields.filter { $0.source == .reusedRun }.map(\.field))
    return reusableFields.isSubset(of: reusedFields)
  }

  private static func fieldProvenance(
    field: ContextField,
    source: WorkflowContextValueSource,
    sourceRun: WorkflowRunRecord? = nil,
    detail: String? = nil
  ) -> WorkflowContextFieldProvenance {
    WorkflowContextFieldProvenance(
      field: field,
      source: source,
      sourceRunId: sourceRun?.runId,
      sourceAttemptId: sourceRun?.attempt.attemptId,
      detail: detail
    )
  }

  private static func contextResolutionError(
    field: ContextField,
    classification: WorkflowFailureClassification,
    error: Error? = nil,
    message: String? = nil,
    reusableRun: WorkflowRunRecord?,
    provenanceFields: [WorkflowContextFieldProvenance],
    attemptedProvenance: WorkflowContextFieldProvenance,
    options: [String] = [],
    preflight: WorkflowEnvironmentPreflight? = nil
  ) -> WorkflowContextResolutionError {
    let hasReusedField =
      attemptedProvenance.source == .reusedRun
      || provenanceFields.contains { $0.source == .reusedRun }
    return WorkflowContextResolutionError(
      field: field,
      classification: classification,
      message: message
        ?? Self.contextualMessage(
          for: field,
          provenance: attemptedProvenance,
          error: error
        ),
      options: options.isEmpty ? (error.map { Self.extractOptions(from: $0) } ?? []) : options,
      preflight: preflight,
      contextProvenance: WorkflowContextProvenance(
        sourceRunId: hasReusedField ? reusableRun?.runId : nil,
        sourceAttemptId: hasReusedField ? reusableRun?.attempt.attemptId : nil,
        fields: provenanceFields + [attemptedProvenance]
      )
    )
  }

  private static func contextualMessage(
    for field: ContextField,
    provenance: WorkflowContextFieldProvenance,
    error: Error?
  ) -> String {
    let fieldName = field.rawValue.replacingOccurrences(of: "_", with: " ")
    let detail = error.map { "\($0)" } ?? provenance.detail ?? "invalid value"
    switch provenance.source {
    case .reusedRun:
      if let sourceRunId = provenance.sourceRunId {
        return "Reused \(fieldName) from run \(sourceRunId) is no longer valid: \(detail)"
      }
      return "Reused \(fieldName) is no longer valid: \(detail)"
    case .explicit:
      return "Explicit \(fieldName) override is not valid: \(detail)"
    case .sessionDefault:
      return "Session default \(fieldName) is not valid: \(detail)"
    case .workflowDefault:
      return "Workflow default \(fieldName) is not valid: \(detail)"
    case .autoDetected:
      return "Auto-detected \(fieldName) is not valid: \(detail)"
    case .derived:
      return detail
    }
  }

  private static func resolveExplicitValue(
    _ explicit: String?,
    field: ContextField
  ) throws -> String? {
    guard let explicit else { return nil }
    let trimmed = explicit.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw WorkflowContextResolutionError(
        field: field,
        classification: .resolutionFailed,
        message:
          "Explicit \(field.rawValue.replacingOccurrences(of: "_", with: " ")) override must not be empty.",
        options: []
      )
    }
    return trimmed
  }

  private static func normalized(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private static func extractOptions(from error: Error) -> [String] {
    let lines = "\(error)"
      .split(separator: "\n")
      .map { $0.trimmingCharacters(in: .whitespaces) }
    guard lines.count > 1 else { return [] }
    return lines.dropFirst().filter { !$0.isEmpty }
  }

  private static func preflightFailure(
    kind: WorkflowEnvironmentCheckKind,
    field: ContextField,
    classification: WorkflowFailureClassification,
    error: Error,
    contextProvenance: WorkflowContextProvenance? = nil,
    validatedAt: Date,
    priorChecks: [WorkflowEnvironmentCheck]
  ) -> WorkflowContextResolutionError {
    let status: WorkflowEnvironmentPreflightStatus =
      classification == .unsupportedContext ? .unsupported : .failed
    let message = "\(error)"
    let failedCheck = WorkflowEnvironmentCheck(
      kind: kind,
      field: field,
      status: status,
      message: message
    )
    return WorkflowContextResolutionError(
      field: field,
      classification: classification,
      message: message,
      options: extractOptions(from: error),
      preflight: WorkflowEnvironmentPreflight(
        status: status,
        summary: preflightSummary(for: field, status: status),
        checks: priorChecks + [failedCheck],
        validatedAt: validatedAt
      ),
      contextProvenance: contextProvenance
    )
  }

  private static func preflightSummary(
    for field: ContextField,
    status: WorkflowEnvironmentPreflightStatus
  ) -> String {
    let fieldName = field.rawValue.replacingOccurrences(of: "_", with: " ")
    switch status {
    case .passed:
      return "Environment preflight passed for the resolved diagnosis context."
    case .failed:
      return "Environment preflight failed while validating \(fieldName)."
    case .unsupported:
      return "Environment preflight found unsupported local state while validating \(fieldName)."
    }
  }

  private static func classifyProjectValidationError(_ error: Error)
    -> WorkflowFailureClassification
  {
    let message = "\(error)".lowercased()
    if message.contains("not found") {
      return .notFound
    }
    if message.contains(".xcodeproj") || message.contains(".xcworkspace")
      || message.contains("unsupported")
    {
      return .unsupportedContext
    }
    return .resolutionFailed
  }

  private static func classifySchemeValidationError(_ error: Error) -> WorkflowFailureClassification {
    let message = "\(error)".lowercased()
    if message.contains("not found") {
      return .notFound
    }
    return .resolutionFailed
  }

  private static func classifySimulatorValidationError(_ error: Error)
    -> WorkflowFailureClassification
  {
    let message = "\(error)".lowercased()
    if message.contains("no booted simulator found") {
      return .unsupportedContext
    }
    if message.contains("ambiguous") {
      return .resolutionFailed
    }
    if message.contains("not available") || message.contains("not found") {
      return .notFound
    }
    if message.contains("unsupported") {
      return .unsupportedContext
    }
    return .resolutionFailed
  }

  private static func classifySimulatorPreparationError(_ error: Error)
    -> WorkflowFailureClassification
  {
    let message = "\(error)".lowercased()
    if message.contains("not available") || message.contains("not found") {
      return .notFound
    }
    if message.contains("ambiguous") {
      return .resolutionFailed
    }
    if message.contains("could not be prepared")
      || message.contains("bootstatus")
      || message.contains("simctl boot")
      || message.contains("remained in state")
    {
      return .unsupportedContext
    }
    return classifySimulatorValidationError(error)
  }

  private static func classifyToolingError(_ error: Error) -> WorkflowFailureClassification {
    let message = "\(error)".lowercased()
    if message.contains("unable to find utility")
      || message.contains("active developer environment") || message.contains("developer directory")
      || message.contains("xcode-select") || message.contains("simctl")
    {
      return .unsupportedContext
    }
    return .resolutionFailed
  }

  private static func classifyAppContextError(_ error: Error) -> WorkflowFailureClassification {
    let message = "\(error)".lowercased()
    if message.contains("unsupported")
      || message.contains("did not contain product_bundle_identifier")
      || message.contains("did not contain an app product path")
      || message.contains("unable to find utility")
      || message.contains("active developer environment") || message.contains("developer directory")
      || message.contains("xcode-select")
    {
      return .unsupportedContext
    }
    return .resolutionFailed
  }

  private static func validateToolingAvailability() async throws {
    try await validateTool(named: "xcodebuild")
    try await validateTool(named: "simctl")
  }

  private static func validateTool(named tool: String) async throws {
    let result = try await Shell.run("/usr/bin/xcrun", arguments: ["--find", tool], timeout: 15)
    guard result.succeeded else {
      let detail = result.stderr.isEmpty ? result.stdout : result.stderr
      throw ToolValidationError(
        "Required tool '\(tool)' is unavailable in the active developer environment: \(detail.trimmingCharacters(in: .whitespacesAndNewlines))"
      )
    }
  }
}

private struct WorkflowContextResolutionError: Error {
  let field: ContextField
  let classification: WorkflowFailureClassification
  let message: String
  let options: [String]
  let preflight: WorkflowEnvironmentPreflight?
  let contextProvenance: WorkflowContextProvenance?

  init(
    field: ContextField,
    classification: WorkflowFailureClassification,
    message: String,
    options: [String],
    preflight: WorkflowEnvironmentPreflight? = nil,
    contextProvenance: WorkflowContextProvenance? = nil
  ) {
    self.field = field
    self.classification = classification
    self.message = message
    self.options = options
    self.preflight = preflight
    self.contextProvenance = contextProvenance
  }

  var status: WorkflowStatus {
    switch classification {
    case .resolutionFailed, .notFound, .invalidRunState, .executionFailed:
      return .failed
    case .unsupportedContext:
      return .unsupported
    }
  }
}

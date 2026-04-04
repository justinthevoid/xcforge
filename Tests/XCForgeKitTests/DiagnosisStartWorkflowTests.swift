import Darwin
import Foundation
import Testing

@testable import XCForgeKit

@Suite("DiagnosisStartWorkflow")
struct DiagnosisStartWorkflowTests {

  @Test("successful start resolves context and persists a run record")
  func successfulStartPersistsRun() async throws {
    let tempDir = makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let session = isolatedSession(baseDirectory: tempDir)

    let store = RunStore(baseDirectory: tempDir)
    let fixedDate = Date(timeIntervalSince1970: 1_743_417_600)
    let workflow = DiagnosisStartWorkflow(
      session: session,
      resolveProject: { "/tmp/MyApp.xcodeproj" },
      resolveScheme: { _ in "MyApp" },
      resolveSimulator: { "SIM-123" },
      validateTooling: {},
      validateProject: { _ in },
      validateResolvedScheme: { _, _ in },
      validateResolvedSimulator: { _ in },
      prepareSimulatorContext: { simulator in
        makePreparedSimulatorContext(requested: simulator)
      },
      resolveAppContext: { _, _, _, _ in
        AppContext(bundleId: "com.example.myapp", appPath: "/tmp/Derived/MyApp.app")
      },
      persistRun: { run in try store.save(run) },
      now: { fixedDate }
    )

    let result = await workflow.start(request: DiagnosisStartRequest())

    #expect(result.isSuccessfulStart)
    #expect(result.status == .inProgress)
    #expect(
      result.resolvedContext
        == ResolvedWorkflowContext(
          project: "/tmp/MyApp.xcodeproj",
          scheme: "MyApp",
          simulator: "SIM-123",
          configuration: "Debug",
          app: AppContext(bundleId: "com.example.myapp", appPath: "/tmp/Derived/MyApp.app"),
          simulatorPreparation: makePreparedSimulatorContext(requested: "SIM-123")
        ))
    #expect(result.runId != nil)
    #expect(result.attemptId != nil)
    #expect(result.persistedRunPath != nil)
    #expect(result.environmentPreflight?.status == .passed)
    #expect(result.environmentPreflight?.checks.count == 5)
    #expect(
      result.resolvedContext?.simulatorPreparation
        == makePreparedSimulatorContext(requested: "SIM-123"))
    #expect(result.resolvedContext?.simulatorPreparation?.initialState == "Booted")
    #expect(result.resolvedContext?.simulatorPreparation?.action == .reusedBooted)

    let persisted = try store.load(runId: try #require(result.runId))
    #expect(persisted.workflow == .diagnosis)
    #expect(persisted.phase == .diagnosisStart)
    #expect(persisted.status == .inProgress)
    #expect(persisted.createdAt == fixedDate)
    #expect(persisted.updatedAt == fixedDate)
    #expect(persisted.resolvedContext == result.resolvedContext)
    #expect(persisted.environmentPreflight == result.environmentPreflight)
    #expect(
      persisted.resolvedContext.simulatorPreparation
        == makePreparedSimulatorContext(requested: "SIM-123"))

    let defaults = await session.workflowDefaultsSnapshot()
    #expect(defaults.project == nil)
    #expect(defaults.scheme == nil)
    #expect(defaults.simulator == nil)
  }

  @Test("omitted fields reuse the latest active diagnosis context")
  func omittedFieldsReuseLatestActiveContext() async throws {
    let tempDir = makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let session = isolatedSession(baseDirectory: tempDir)

    let store = RunStore(baseDirectory: tempDir)
    let appPath =
      tempDir
      .appendingPathComponent("reused", isDirectory: true)
      .appendingPathComponent("MyApp.app", isDirectory: true)
    try FileManager.default.createDirectory(
      at: appPath,
      withIntermediateDirectories: true,
      attributes: nil
    )

    let reusableRun = makeReusableRun(
      runId: "reused-run-1",
      attemptId: "attempt-reused-1",
      project: "/tmp/Reused.xcodeproj",
      scheme: "ReusedScheme",
      simulator: "ReusedSim",
      configuration: "Release",
      appPath: appPath.path,
      status: .inProgress
    )
    _ = try store.save(reusableRun)

    let workflow = DiagnosisStartWorkflow(
      session: session,
      resolveProject: { throw TestFailure.unusedResolver },
      resolveScheme: { _ in throw TestFailure.unusedResolver },
      validateScheme: { scheme, project in
        scheme == reusableRun.resolvedContext.scheme
          && project == reusableRun.resolvedContext.project
      },
      resolveSimulator: { throw TestFailure.unusedResolver },
      resolveReusableRun: { _ in try store.reusableDiagnosisRun() },
      validateTooling: {},
      validateProject: { _ in },
      validateResolvedScheme: { _, _ in },
      validateResolvedSimulator: { _ in },
      prepareSimulatorContext: { simulator in
        makePreparedSimulatorContext(requested: simulator, selected: "ReusedSim")
      },
      resolveAppContext: { _, _, _, _ in
        throw TestFailure.unusedResolver
      },
      persistRun: { run in try store.save(run) }
    )

    let result = await workflow.start(request: DiagnosisStartRequest())

    #expect(result.isSuccessfulStart)
    #expect(result.resolvedContext?.project == reusableRun.resolvedContext.project)
    #expect(result.resolvedContext?.scheme == reusableRun.resolvedContext.scheme)
    #expect(result.resolvedContext?.simulator == reusableRun.resolvedContext.simulator)
    #expect(result.resolvedContext?.configuration == reusableRun.resolvedContext.configuration)
    #expect(result.resolvedContext?.app == reusableRun.resolvedContext.app)
    #expect(result.contextProvenance?.sourceRunId == reusableRun.runId)
    #expect(
      result.contextProvenance?.fields.map(\.source) == [
        .reusedRun,
        .reusedRun,
        .reusedRun,
        .reusedRun,
        .reusedRun,
      ])

    let defaults = await session.workflowDefaultsSnapshot()
    #expect(defaults.project == nil)
    #expect(defaults.scheme == nil)
    #expect(defaults.simulator == nil)
  }

  @Test("explicit overrides preserve reuse provenance without mutating defaults")
  func explicitOverridePreservesReuseProvenance() async throws {
    let tempDir = makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let session = isolatedSession(baseDirectory: tempDir)
    await session.setDefaults(
      project: "/tmp/Stored.xcodeproj",
      scheme: "StoredScheme",
      simulator: "StoredSim"
    )

    let store = RunStore(baseDirectory: tempDir)
    let appPath =
      tempDir
      .appendingPathComponent("reused", isDirectory: true)
      .appendingPathComponent("MyApp.app", isDirectory: true)
    try FileManager.default.createDirectory(
      at: appPath,
      withIntermediateDirectories: true,
      attributes: nil
    )

    let reusableRun = makeReusableRun(
      runId: "reused-run-2",
      attemptId: "attempt-reused-2",
      project: "/tmp/Reused.xcodeproj",
      scheme: "ReusedScheme",
      simulator: "ReusedSim",
      configuration: "Release",
      appPath: appPath.path,
      status: .inProgress
    )
    _ = try store.save(reusableRun)

    let workflow = DiagnosisStartWorkflow(
      session: session,
      resolveProject: { throw TestFailure.unusedResolver },
      resolveScheme: { _ in throw TestFailure.unusedResolver },
      validateScheme: { scheme, project in
        scheme == reusableRun.resolvedContext.scheme
          && project == reusableRun.resolvedContext.project
      },
      resolveSimulator: { throw TestFailure.unusedResolver },
      resolveReusableRun: { _ in try store.load(runId: reusableRun.runId) },
      validateTooling: {},
      validateProject: { _ in },
      validateResolvedScheme: { _, _ in },
      validateResolvedSimulator: { _ in },
      prepareSimulatorContext: { simulator in
        makePreparedSimulatorContext(requested: simulator, selected: "ReusedSim")
      },
      resolveAppContext: { _, scheme, _, configuration in
        AppContext(
          bundleId: "com.example.\(scheme).\(configuration)",
          appPath: "/tmp/Derived/\(scheme)-\(configuration).app"
        )
      },
      persistRun: { run in try store.save(run) }
    )

    let result = await workflow.start(
      request: DiagnosisStartRequest(
        scheme: "OverrideScheme",
        reuseRunId: reusableRun.runId
      )
    )

    #expect(result.isSuccessfulStart)
    #expect(result.resolvedContext?.project == reusableRun.resolvedContext.project)
    #expect(result.resolvedContext?.scheme == "OverrideScheme")
    #expect(result.resolvedContext?.simulator == reusableRun.resolvedContext.simulator)
    #expect(result.resolvedContext?.configuration == reusableRun.resolvedContext.configuration)
    #expect(result.resolvedContext?.app.bundleId == "com.example.OverrideScheme.Release")
    #expect(
      result.contextProvenance?.fields.first(where: { $0.field == .project })?.source == .reusedRun)
    #expect(
      result.contextProvenance?.fields.first(where: { $0.field == .scheme })?.source == .explicit)
    #expect(
      result.contextProvenance?.fields.first(where: { $0.field == .simulator })?.source
        == .reusedRun)
    #expect(
      result.contextProvenance?.fields.first(where: { $0.field == .build })?.source == .reusedRun)
    #expect(result.contextProvenance?.fields.first(where: { $0.field == .app })?.source == .derived)

    let defaults = await session.workflowDefaultsSnapshot()
    #expect(defaults.project == "/tmp/Stored.xcodeproj")
    #expect(defaults.scheme == "StoredScheme")
    #expect(defaults.simulator == "StoredSim")
  }

  @Test("all-explicit starts do not claim a source run when nothing was reused")
  func allExplicitStartsDoNotClaimSourceRun() async throws {
    let tempDir = makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let store = RunStore(baseDirectory: tempDir)
    let appPath =
      tempDir
      .appendingPathComponent("reused", isDirectory: true)
      .appendingPathComponent("MyApp.app", isDirectory: true)
    try FileManager.default.createDirectory(
      at: appPath,
      withIntermediateDirectories: true,
      attributes: nil
    )

    let reusableRun = makeReusableRun(
      runId: "reused-run-explicit",
      attemptId: "attempt-reused-explicit",
      project: "/tmp/Reused.xcodeproj",
      scheme: "ReusedScheme",
      simulator: "ReusedSim",
      configuration: "Release",
      appPath: appPath.path,
      status: .inProgress
    )
    _ = try store.save(reusableRun)

    let workflow = DiagnosisStartWorkflow(
      session: isolatedSession(baseDirectory: tempDir),
      resolveProject: { throw TestFailure.unusedResolver },
      resolveScheme: { _ in throw TestFailure.unusedResolver },
      resolveSimulator: { throw TestFailure.unusedResolver },
      resolveReusableRun: { _ in try store.reusableDiagnosisRun(runId: reusableRun.runId) },
      validateTooling: {},
      validateProject: { _ in },
      validateResolvedScheme: { _, _ in },
      validateResolvedSimulator: { _ in },
      prepareSimulatorContext: { simulator in
        makePreparedSimulatorContext(requested: simulator, selected: "ExplicitSim")
      },
      resolveAppContext: { _, _, _, _ in
        AppContext(bundleId: "com.example.explicit", appPath: "/tmp/Derived/Explicit.app")
      },
      persistRun: { run in try store.save(run) }
    )

    let result = await workflow.start(
      request: DiagnosisStartRequest(
        project: "/tmp/Explicit.xcodeproj",
        scheme: "ExplicitScheme",
        simulator: "ExplicitSim",
        reuseRunId: reusableRun.runId,
        configuration: "Debug"
      )
    )

    #expect(result.isSuccessfulStart)
    #expect(result.contextProvenance?.sourceRunId == nil)
    #expect(result.contextProvenance?.sourceAttemptId == nil)
    #expect(
      result.contextProvenance?.fields.map(\.source) == [
        .explicit,
        .explicit,
        .explicit,
        .explicit,
        .derived,
      ])
  }

  @Test("incompatible reused context fails explicitly without auto-detect fallback")
  func incompatibleReuseFailsExplicitly() async throws {
    let tempDir = makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let store = RunStore(baseDirectory: tempDir)
    let appPath =
      tempDir
      .appendingPathComponent("reused", isDirectory: true)
      .appendingPathComponent("MyApp.app", isDirectory: true)
    try FileManager.default.createDirectory(
      at: appPath,
      withIntermediateDirectories: true,
      attributes: nil
    )

    let reusableRun = makeReusableRun(
      runId: "reused-run-3",
      attemptId: "attempt-reused-3",
      project: "/tmp/Reused.xcodeproj",
      scheme: "ReusedScheme",
      simulator: "ReusedSim",
      configuration: "Release",
      appPath: appPath.path,
      status: .inProgress
    )
    _ = try store.save(reusableRun)

    let workflow = DiagnosisStartWorkflow(
      session: isolatedSession(baseDirectory: tempDir),
      resolveProject: { throw TestFailure.unusedResolver },
      resolveScheme: { _ in throw TestFailure.unusedResolver },
      validateScheme: { _, _ in false },
      resolveSimulator: { throw TestFailure.unusedResolver },
      resolveReusableRun: { _ in try store.load(runId: reusableRun.runId) },
      validateTooling: {},
      validateProject: { _ in },
      validateResolvedScheme: { _, _ in },
      validateResolvedSimulator: { _ in },
      prepareSimulatorContext: { simulator in
        makePreparedSimulatorContext(requested: simulator, selected: "ReusedSim")
      },
      resolveAppContext: { _, _, _, _ in
        throw TestFailure.unusedResolver
      },
      persistRun: { run in try store.save(run) }
    )

    let result = await workflow.start(
      request: DiagnosisStartRequest(reuseRunId: reusableRun.runId)
    )

    #expect(!result.isSuccessfulStart)
    #expect(result.status == .unsupported)
    #expect(result.failure?.field == .scheme)
    #expect(result.failure?.classification == .unsupportedContext)
    #expect(result.contextProvenance?.sourceRunId == reusableRun.runId)
    #expect(result.contextProvenance?.fields.first?.source == .reusedRun)
    #expect(result.environmentPreflight == nil)
    #expect(result.persistedRunPath == nil)
  }

  @Test("explicit overrides do not mutate saved defaults")
  func explicitOverridesLeaveDefaultsUntouched() async {
    let tempDir = makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let session = isolatedSession(baseDirectory: tempDir)
    await session.setDefaults(
      project: "/tmp/Stored.xcodeproj",
      scheme: "StoredScheme",
      simulator: "StoredSim"
    )

    let store = RunStore(baseDirectory: tempDir)
    let workflow = DiagnosisStartWorkflow(
      session: session,
      resolveProject: { throw TestFailure.unusedResolver },
      resolveScheme: { _ in throw TestFailure.unusedResolver },
      resolveSimulator: { throw TestFailure.unusedResolver },
      validateTooling: {},
      validateProject: { _ in },
      validateResolvedScheme: { _, _ in },
      validateResolvedSimulator: { _ in },
      prepareSimulatorContext: { simulator in
        makePreparedSimulatorContext(requested: simulator)
      },
      resolveAppContext: { _, _, _, _ in
        AppContext(bundleId: "com.example.override", appPath: "/tmp/Derived/Override.app")
      },
      persistRun: { run in try store.save(run) }
    )

    let result = await workflow.start(
      request: DiagnosisStartRequest(
        project: "/tmp/Override.xcodeproj",
        scheme: "OverrideScheme",
        simulator: "OverrideSim"
      )
    )

    #expect(result.isSuccessfulStart)
    #expect(result.resolvedContext?.project == "/tmp/Override.xcodeproj")
    #expect(result.resolvedContext?.scheme == "OverrideScheme")
    #expect(result.resolvedContext?.simulator == "OverrideSim")
    #expect(result.resolvedContext?.configuration == "Debug")
    #expect(result.resolvedContext?.simulatorPreparation?.requested == "OverrideSim")
    #expect(result.resolvedContext?.simulatorPreparation?.selected == "OverrideSim")

    let defaults = await session.workflowDefaultsSnapshot()
    #expect(defaults.project == "/tmp/Stored.xcodeproj")
    #expect(defaults.scheme == "StoredScheme")
    #expect(defaults.simulator == "StoredSim")
  }

  @Test("stored scheme defaults are reused before auto-detect when valid for an explicit project")
  func validStoredSchemeDefaultIsReused() async {
    let tempDir = makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let session = isolatedSession(baseDirectory: tempDir)
    await session.setDefaults(
      project: "/tmp/Stored.xcodeproj",
      scheme: "StoredScheme",
      simulator: "StoredSim"
    )

    let store = RunStore(baseDirectory: tempDir)
    let workflow = DiagnosisStartWorkflow(
      session: session,
      resolveProject: { throw TestFailure.unusedResolver },
      resolveScheme: { _ in throw TestFailure.unusedResolver },
      validateScheme: { scheme, project in
        scheme == "StoredScheme" && project == "/tmp/ExplicitProject.xcodeproj"
      },
      resolveSimulator: { throw TestFailure.unusedResolver },
      validateTooling: {},
      validateProject: { _ in },
      validateResolvedScheme: { _, _ in },
      validateResolvedSimulator: { _ in },
      prepareSimulatorContext: { simulator in
        makePreparedSimulatorContext(requested: simulator, selected: "StoredSim")
      },
      resolveAppContext: { _, scheme, _, _ in
        AppContext(bundleId: "com.example.app", appPath: "/tmp/\(scheme).app")
      },
      persistRun: { run in try store.save(run) }
    )

    let result = await workflow.start(
      request: DiagnosisStartRequest(project: "/tmp/ExplicitProject.xcodeproj")
    )

    #expect(result.isSuccessfulStart)
    #expect(result.resolvedContext?.scheme == "StoredScheme")
  }

  @Test("invalid stored scheme falls back to auto-detect for the resolved project")
  func invalidStoredSchemeFallsBackToAutodetect() async {
    let tempDir = makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let session = isolatedSession(baseDirectory: tempDir)
    await session.setDefaults(project: nil, scheme: "StaleScheme", simulator: nil)

    let store = RunStore(baseDirectory: tempDir)
    let workflow = DiagnosisStartWorkflow(
      session: session,
      resolveProject: { "/tmp/DetectedProject.xcodeproj" },
      resolveScheme: { project in
        #expect(project == "/tmp/DetectedProject.xcodeproj")
        return "DetectedScheme"
      },
      validateScheme: { scheme, _ in
        #expect(scheme == "StaleScheme")
        return false
      },
      resolveSimulator: { "SIM-123" },
      validateTooling: {},
      validateProject: { _ in },
      validateResolvedScheme: { _, _ in },
      validateResolvedSimulator: { _ in },
      prepareSimulatorContext: { simulator in
        makePreparedSimulatorContext(requested: simulator)
      },
      resolveAppContext: { _, scheme, _, _ in
        AppContext(bundleId: "com.example.app", appPath: "/tmp/\(scheme).app")
      },
      persistRun: { run in try store.save(run) }
    )

    let result = await workflow.start(request: DiagnosisStartRequest())

    #expect(result.isSuccessfulStart)
    #expect(result.resolvedContext?.scheme == "DetectedScheme")
  }

  @Test("ambiguous project resolution returns explicit failure and does not persist a run")
  func ambiguousProjectFailsExplicitly() async {
    let tempDir = makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let store = RunStore(baseDirectory: tempDir)
    let workflow = DiagnosisStartWorkflow(
      session: isolatedSession(baseDirectory: tempDir),
      resolveProject: {
        throw ResolverError(
          """
          2 projects found — specify which one:
            App.xcodeproj
            App.xcworkspace
          """
        )
      },
      resolveScheme: { _ in "unused" },
      resolveSimulator: { "unused" },
      validateTooling: {},
      validateProject: { _ in },
      validateResolvedScheme: { _, _ in },
      validateResolvedSimulator: { _ in },
      prepareSimulatorContext: { simulator in
        makePreparedSimulatorContext(requested: simulator)
      },
      resolveAppContext: { _, _, _, _ in
        AppContext(bundleId: "unused", appPath: "unused")
      },
      persistRun: { run in try store.save(run) }
    )

    let result = await workflow.start(request: DiagnosisStartRequest())

    #expect(!result.isSuccessfulStart)
    #expect(result.status == .failed)
    #expect(result.failure?.field == .project)
    #expect(result.failure?.classification == .resolutionFailed)
    #expect(result.failure?.options == ["App.xcodeproj", "App.xcworkspace"])
    #expect(result.environmentPreflight == nil)
    #expect(result.persistedRunPath == nil)
    let contents = (try? FileManager.default.contentsOfDirectory(atPath: tempDir.path)) ?? []
    #expect(contents.allSatisfy { $0 == "defaults" })
  }

  @Test("app context resolution failures are classified as unsupported")
  func appResolutionFailureIsUnsupported() async {
    let tempDir = makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let store = RunStore(baseDirectory: tempDir)
    let workflow = DiagnosisStartWorkflow(
      session: isolatedSession(baseDirectory: tempDir),
      resolveProject: { "/tmp/MyApp.xcodeproj" },
      resolveScheme: { _ in "MyApp" },
      resolveSimulator: { "SIM-123" },
      validateTooling: {},
      validateProject: { _ in },
      validateResolvedScheme: { _, _ in },
      validateResolvedSimulator: { _ in },
      prepareSimulatorContext: { simulator in
        makePreparedSimulatorContext(requested: simulator)
      },
      resolveAppContext: { _, _, _, _ in
        throw BuildSettingsError("Build settings did not contain an app product path for MyApp")
      },
      persistRun: { run in try store.save(run) }
    )

    let result = await workflow.start(request: DiagnosisStartRequest())

    #expect(!result.isSuccessfulStart)
    #expect(result.status == .unsupported)
    #expect(result.failure?.field == .app)
    #expect(result.failure?.classification == .unsupportedContext)
    #expect(result.environmentPreflight?.status == .unsupported)
    #expect(result.environmentPreflight?.checks.last?.kind == .appContext)
    #expect(result.persistedRunPath == nil)
  }

  @Test("transient app context failures remain resolution failures")
  func transientAppResolutionFailureIsFailed() async {
    let tempDir = makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let store = RunStore(baseDirectory: tempDir)
    let workflow = DiagnosisStartWorkflow(
      session: isolatedSession(baseDirectory: tempDir),
      resolveProject: { "/tmp/MyApp.xcodeproj" },
      resolveScheme: { _ in "MyApp" },
      resolveSimulator: { "SIM-123" },
      validateTooling: {},
      validateProject: { _ in },
      validateResolvedScheme: { _, _ in },
      validateResolvedSimulator: { _ in },
      prepareSimulatorContext: { simulator in
        makePreparedSimulatorContext(requested: simulator)
      },
      resolveAppContext: { _, _, _, _ in
        throw BuildSettingsError("Unable to resolve app context for MyApp: xcodebuild timed out")
      },
      persistRun: { run in try store.save(run) }
    )

    let result = await workflow.start(request: DiagnosisStartRequest())

    #expect(!result.isSuccessfulStart)
    #expect(result.status == .failed)
    #expect(result.failure?.field == .app)
    #expect(result.failure?.classification == .resolutionFailed)
    #expect(result.environmentPreflight?.status == .failed)
  }

  @Test("invalid explicit simulator is reported as an environment preflight failure")
  func invalidExplicitSimulatorFailsPreflight() async throws {
    let tempDir = makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let store = RunStore(baseDirectory: tempDir)
    let workflow = DiagnosisStartWorkflow(
      session: isolatedSession(baseDirectory: tempDir),
      resolveProject: { throw TestFailure.unusedResolver },
      resolveScheme: { _ in throw TestFailure.unusedResolver },
      resolveSimulator: { throw TestFailure.unusedResolver },
      validateTooling: {},
      validateProject: { _ in },
      validateResolvedScheme: { _, _ in },
      validateResolvedSimulator: { _ in },
      prepareSimulatorContext: { simulator in
        throw ResolverError(
          """
          Simulator '\(simulator)' is not available for this workflow context.
          Available simulators:
            iPhone 16 Pro — SIM-123
          """
        )
      },
      resolveAppContext: { _, _, _, _ in
        AppContext(bundleId: "unused", appPath: "unused")
      },
      persistRun: { run in try store.save(run) }
    )

    let result = await workflow.start(
      request: DiagnosisStartRequest(
        project: "/tmp/MyApp.xcodeproj",
        scheme: "MyApp",
        simulator: "MissingSim"
      )
    )

    #expect(!result.isSuccessfulStart)
    #expect(result.status == .failed)
    #expect(result.failure?.field == .simulator)
    #expect(result.failure?.classification == .notFound)
    #expect(result.environmentPreflight?.status == .failed)
    #expect(result.environmentPreflight?.checks.count == 4)
    #expect(result.environmentPreflight?.checks.last?.kind == .simulator)
    #expect(result.persistedRunPath == nil)
  }

  @Test("invalid explicit project is reported as a project preflight failure")
  func invalidExplicitProjectFailsPreflight() async throws {
    let tempDir = makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let store = RunStore(baseDirectory: tempDir)
    let workflow = DiagnosisStartWorkflow(
      session: isolatedSession(baseDirectory: tempDir),
      resolveProject: { throw TestFailure.unusedResolver },
      resolveScheme: { _ in throw TestFailure.unusedResolver },
      resolveSimulator: { throw TestFailure.unusedResolver },
      validateTooling: {},
      validateProject: { project in
        throw ResolverError("Project path not found: \(project)")
      },
      validateResolvedScheme: { _, _ in },
      validateResolvedSimulator: { _ in },
      prepareSimulatorContext: { simulator in
        makePreparedSimulatorContext(requested: simulator)
      },
      resolveAppContext: { _, _, _, _ in
        AppContext(bundleId: "unused", appPath: "unused")
      },
      persistRun: { run in try store.save(run) }
    )

    let result = await workflow.start(
      request: DiagnosisStartRequest(
        project: "/tmp/Missing.xcodeproj",
        scheme: "MyApp",
        simulator: "SIM-123"
      )
    )

    #expect(!result.isSuccessfulStart)
    #expect(result.status == .failed)
    #expect(result.failure?.field == .project)
    #expect(result.failure?.classification == .notFound)
    #expect(result.environmentPreflight?.checks.count == 2)
    #expect(result.environmentPreflight?.checks.last?.kind == .project)
    #expect(result.persistedRunPath == nil)
  }

  @Test("invalid explicit scheme is reported as a scheme preflight failure")
  func invalidExplicitSchemeFailsPreflight() async throws {
    let tempDir = makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let store = RunStore(baseDirectory: tempDir)
    let workflow = DiagnosisStartWorkflow(
      session: isolatedSession(baseDirectory: tempDir),
      resolveProject: { throw TestFailure.unusedResolver },
      resolveScheme: { _ in throw TestFailure.unusedResolver },
      resolveSimulator: { throw TestFailure.unusedResolver },
      validateTooling: {},
      validateProject: { _ in },
      validateResolvedScheme: { scheme, _ in
        throw ResolverError(
          """
          Scheme '\(scheme)' was not found in MyApp.xcodeproj.
          Available schemes:
            MyApp
          """
        )
      },
      validateResolvedSimulator: { _ in },
      prepareSimulatorContext: { simulator in
        makePreparedSimulatorContext(requested: simulator)
      },
      resolveAppContext: { _, _, _, _ in
        AppContext(bundleId: "unused", appPath: "unused")
      },
      persistRun: { run in try store.save(run) }
    )

    let result = await workflow.start(
      request: DiagnosisStartRequest(
        project: "/tmp/MyApp.xcodeproj",
        scheme: "MissingScheme",
        simulator: "SIM-123"
      )
    )

    #expect(!result.isSuccessfulStart)
    #expect(result.status == .failed)
    #expect(result.failure?.field == .scheme)
    #expect(result.failure?.classification == .notFound)
    #expect(result.environmentPreflight?.checks.count == 3)
    #expect(result.environmentPreflight?.checks.last?.kind == .scheme)
    #expect(result.persistedRunPath == nil)
  }

  @Test("missing tooling is reported before workflow start succeeds")
  func unavailableToolingFailsPreflight() async throws {
    let tempDir = makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let store = RunStore(baseDirectory: tempDir)
    let workflow = DiagnosisStartWorkflow(
      session: isolatedSession(baseDirectory: tempDir),
      resolveProject: { "/tmp/MyApp.xcodeproj" },
      resolveScheme: { _ in "MyApp" },
      resolveSimulator: { "SIM-123" },
      validateTooling: {
        throw ToolValidationError(
          "Required tool 'simctl' is unavailable in the active developer environment: xcrun: error: unable to find utility \"simctl\""
        )
      },
      validateProject: { _ in },
      validateResolvedScheme: { _, _ in },
      validateResolvedSimulator: { _ in },
      prepareSimulatorContext: { simulator in
        makePreparedSimulatorContext(requested: simulator)
      },
      resolveAppContext: { _, _, _, _ in
        AppContext(bundleId: "unused", appPath: "unused")
      },
      persistRun: { run in try store.save(run) }
    )

    let result = await workflow.start(request: DiagnosisStartRequest())

    #expect(!result.isSuccessfulStart)
    #expect(result.status == .unsupported)
    #expect(result.failure?.field == .tooling)
    #expect(result.failure?.classification == .unsupportedContext)
    #expect(result.environmentPreflight?.status == .unsupported)
    #expect(result.environmentPreflight?.checks.count == 1)
    #expect(result.environmentPreflight?.checks.first?.kind == .tooling)
    #expect(result.persistedRunPath == nil)
  }

  @Test("run store expands tilde in the override directory")
  func runStoreExpandsTildeOverride() {
    let previous = ProcessInfo.processInfo.environment["XCFORGE_RUN_STORE_DIR"]
    setenv("XCFORGE_RUN_STORE_DIR", "~/xcforge-test-runs", 1)
    defer {
      if let previous {
        setenv("XCFORGE_RUN_STORE_DIR", previous, 1)
      } else {
        unsetenv("XCFORGE_RUN_STORE_DIR")
      }
    }

    let store = RunStore()
    #expect(store.baseDirectory.path.hasPrefix(NSHomeDirectory()))
    #expect(!store.baseDirectory.path.contains("/~/"))
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

  /// Creates a SessionState backed by a temp directory — no disk pollution.
  /// When `baseDirectory` is provided the DefaultsStore uses a subdirectory of
  /// that path so cleanup is handled by the caller's existing `defer`.
  /// When omitted a fresh temp directory is created; the caller must clean it up.
  private func isolatedSession(baseDirectory: URL? = nil) -> SessionState {
    let dir = baseDirectory ?? makeTempDirectory()
    let defaultsDir = dir.appendingPathComponent("defaults", isDirectory: true)
    try? FileManager.default.createDirectory(
      at: defaultsDir, withIntermediateDirectories: true, attributes: nil)
    return SessionState(defaultsStore: DefaultsStore(baseDirectory: defaultsDir))
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

  private func makeReusableRun(
    runId: String,
    attemptId: String,
    project: String,
    scheme: String,
    simulator: String,
    configuration: String,
    appPath: String,
    status: WorkflowStatus
  ) -> WorkflowRunRecord {
    WorkflowRunRecord(
      runId: runId,
      workflow: .diagnosis,
      phase: .diagnosisStart,
      status: status,
      createdAt: Date(timeIntervalSince1970: 1_743_417_600),
      updatedAt: Date(timeIntervalSince1970: 1_743_417_700),
      attempt: WorkflowAttemptRecord(
        attemptId: attemptId,
        attemptNumber: 1,
        phase: .diagnosisStart,
        startedAt: Date(timeIntervalSince1970: 1_743_417_600),
        status: status
      ),
      resolvedContext: ResolvedWorkflowContext(
        project: project,
        scheme: scheme,
        simulator: simulator,
        configuration: configuration,
        app: AppContext(bundleId: "com.example.\(scheme)", appPath: appPath)
      )
    )
  }
}

private enum TestFailure: Error {
  case unusedResolver
}

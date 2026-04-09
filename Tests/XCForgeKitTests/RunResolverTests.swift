import Foundation
import Testing

@testable import XCForgeKit

@Suite("RunResolver")
struct RunResolverTests {

  // MARK: - Explicit run ID

  @Test("explicit run ID returns matching record")
  func explicitRunIdReturnsMatchingRecord() {
    let record = makeRecord(runId: "abc-123")
    let resolver = RunResolver(
      strategy: .activeOrRecent,
      loadRun: { runId in
        guard runId == "abc-123" else { throw CocoaError(.fileNoSuchFile) }
        return record
      },
      loadLatestActiveRun: { nil },
      loadLatestRun: { nil }
    )

    let result = resolver.resolve("abc-123")
    guard case .success(let run) = result else {
      Issue.record("Expected success, got \(result)")
      return
    }
    #expect(run.runId == "abc-123")
  }

  @Test("empty string run ID fails with emptyRunId")
  func emptyStringFailsWithEmptyRunId() {
    let resolver = RunResolver(
      strategy: .activeOrRecent,
      loadRun: { _ in throw CocoaError(.fileNoSuchFile) },
      loadLatestActiveRun: { nil },
      loadLatestRun: { nil }
    )

    let result = resolver.resolve("   ")
    guard case .failure(.emptyRunId) = result else {
      Issue.record("Expected .emptyRunId, got \(result)")
      return
    }
  }

  @Test("missing explicit run ID fails with notFound")
  func missingExplicitRunIdFailsWithNotFound() {
    let resolver = RunResolver(
      strategy: .activeOrRecent,
      loadRun: { _ in throw CocoaError(.fileNoSuchFile) },
      loadLatestActiveRun: { nil },
      loadLatestRun: { nil }
    )

    let result = resolver.resolve("nonexistent")
    guard case .failure(.notFound(let runId)) = result else {
      Issue.record("Expected .notFound, got \(result)")
      return
    }
    #expect(runId == "nonexistent")
  }

  @Test("load failure returns loadFailed")
  func loadFailureReturnsLoadFailed() {
    struct CustomError: Error {}
    let resolver = RunResolver(
      strategy: .activeOrRecent,
      loadRun: { _ in throw CustomError() },
      loadLatestActiveRun: { nil },
      loadLatestRun: { nil }
    )

    let result = resolver.resolve("some-id")
    guard case .failure(.loadFailed) = result else {
      Issue.record("Expected .loadFailed, got \(result)")
      return
    }
  }

  // MARK: - activeOrRecent strategy

  @Test("nil run ID with active run returns active run")
  func nilRunIdWithActiveRunReturnsActiveRun() {
    let active = makeRecord(runId: "active-1")
    let resolver = RunResolver(
      strategy: .activeOrRecent,
      loadRun: { _ in throw CocoaError(.fileNoSuchFile) },
      loadLatestActiveRun: { active },
      loadLatestRun: { makeRecord(runId: "recent-1") }
    )

    let result = resolver.resolve(nil)
    guard case .success(let run) = result else {
      Issue.record("Expected success, got \(result)")
      return
    }
    #expect(run.runId == "active-1")
  }

  @Test("nil run ID with no active falls back to recent")
  func nilRunIdWithNoActiveFallsBackToRecent() {
    let recent = makeRecord(runId: "recent-1")
    let resolver = RunResolver(
      strategy: .activeOrRecent,
      loadRun: { _ in throw CocoaError(.fileNoSuchFile) },
      loadLatestActiveRun: { nil },
      loadLatestRun: { recent }
    )

    let result = resolver.resolve(nil)
    guard case .success(let run) = result else {
      Issue.record("Expected success, got \(result)")
      return
    }
    #expect(run.runId == "recent-1")
  }

  @Test("nil run ID with no runs returns noRunsAvailable")
  func nilRunIdWithNoRunsReturnsNoRunsAvailable() {
    let resolver = RunResolver(
      strategy: .activeOrRecent,
      loadRun: { _ in throw CocoaError(.fileNoSuchFile) },
      loadLatestActiveRun: { nil },
      loadLatestRun: { nil }
    )

    let result = resolver.resolve(nil)
    guard case .failure(.noRunsAvailable) = result else {
      Issue.record("Expected .noRunsAvailable, got \(result)")
      return
    }
  }

  // MARK: - terminalFirst strategy

  @Test("terminalFirst returns terminal run when available")
  func terminalFirstReturnsTerminalRun() {
    let terminal = makeRecord(runId: "terminal-1")
    let resolver = RunResolver(
      strategy: .terminalFirst,
      loadRun: { _ in throw CocoaError(.fileNoSuchFile) },
      loadLatestActiveRun: { makeRecord(runId: "active-1") },
      loadLatestTerminalRun: { terminal },
      loadLatestRun: { makeRecord(runId: "recent-1") }
    )

    let result = resolver.resolve(nil)
    guard case .success(let run) = result else {
      Issue.record("Expected success, got \(result)")
      return
    }
    #expect(run.runId == "terminal-1")
  }

  @Test("terminalFirst with in-progress run returns runStillInProgress")
  func terminalFirstWithInProgressRunReturnsStillInProgress() {
    let resolver = RunResolver(
      strategy: .terminalFirst,
      loadRun: { _ in throw CocoaError(.fileNoSuchFile) },
      loadLatestActiveRun: { makeRecord(runId: "active-1") },
      loadLatestTerminalRun: { nil },
      loadLatestRun: { nil }
    )

    let result = resolver.resolve(nil)
    guard case .failure(.runStillInProgress(let runId)) = result else {
      Issue.record("Expected .runStillInProgress, got \(result)")
      return
    }
    #expect(runId == "active-1")
  }

  @Test("terminalFirst with no runs at all returns noRunsAvailable")
  func terminalFirstWithNoRunsReturnsNoRunsAvailable() {
    let resolver = RunResolver(
      strategy: .terminalFirst,
      loadRun: { _ in throw CocoaError(.fileNoSuchFile) },
      loadLatestActiveRun: { nil },
      loadLatestTerminalRun: { nil },
      loadLatestRun: { nil }
    )

    let result = resolver.resolve(nil)
    guard case .failure(.noRunsAvailable) = result else {
      Issue.record("Expected .noRunsAvailable, got \(result)")
      return
    }
  }

  // MARK: - Helpers

  private func makeRecord(runId: String) -> WorkflowRunRecord {
    WorkflowRunRecord(
      runId: runId,
      workflow: .diagnosis,
      phase: .diagnosisStart,
      status: .inProgress,
      createdAt: Date(timeIntervalSince1970: 1_743_700_000),
      updatedAt: Date(timeIntervalSince1970: 1_743_700_100),
      attempt: WorkflowAttemptRecord(
        attemptId: "attempt-1",
        attemptNumber: 1,
        phase: .diagnosisStart,
        startedAt: Date(timeIntervalSince1970: 1_743_700_000),
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
}

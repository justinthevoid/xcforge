import Foundation

/// Centralised run-ID resolution shared by CLI, MCP tools, and workflow layers.
///
/// Each call site injects its own loader closures (for testability) and maps the
/// returned ``RunResolutionFailure`` to its domain-specific error type.
public struct RunResolver: Sendable {

  /// The fallback strategy used when no explicit run ID is provided.
  public enum Strategy: Sendable {
    /// Try the latest active run first, then the latest run of any status.
    case activeOrRecent
    /// Try the latest terminal (completed/failed) run first. If none exists, check
    /// whether an active or recent run is available and report it as still in-progress.
    case terminalFirst
  }

  public typealias LoadRun = @Sendable (String) throws -> WorkflowRunRecord
  public typealias LoadOptionalRun = @Sendable () throws -> WorkflowRunRecord?

  let loadRun: LoadRun
  let loadLatestActiveRun: LoadOptionalRun
  let loadLatestTerminalRun: LoadOptionalRun?
  let loadLatestRun: LoadOptionalRun
  private let strategy: Strategy

  public init(
    strategy: Strategy = .activeOrRecent,
    loadRun: @escaping LoadRun,
    loadLatestActiveRun: @escaping LoadOptionalRun,
    loadLatestTerminalRun: LoadOptionalRun? = nil,
    loadLatestRun: @escaping LoadOptionalRun
  ) {
    self.strategy = strategy
    self.loadRun = loadRun
    self.loadLatestActiveRun = loadLatestActiveRun
    self.loadLatestTerminalRun = loadLatestTerminalRun
    self.loadLatestRun = loadLatestRun
  }

  /// Resolve an optional run-ID string to a concrete ``WorkflowRunRecord``.
  public func resolve(_ runId: String?) -> Result<WorkflowRunRecord, RunResolutionFailure> {
    if let runId {
      let trimmed = runId.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else {
        return .failure(.emptyRunId)
      }
      do {
        return .success(try loadRun(trimmed))
      } catch let error as CocoaError
        where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile
      {
        return .failure(.notFound(runId: trimmed))
      } catch {
        return .failure(.loadFailed(underlyingError: error))
      }
    }

    do {
      switch strategy {
      case .activeOrRecent:
        return try resolveActiveOrRecent()
      case .terminalFirst:
        return try resolveTerminalFirst()
      }
    } catch {
      return .failure(.loadFailed(underlyingError: error))
    }
  }

  private func resolveActiveOrRecent() throws -> Result<WorkflowRunRecord, RunResolutionFailure> {
    if let run = try loadLatestActiveRun() {
      return .success(run)
    }
    if let run = try loadLatestRun() {
      return .success(run)
    }
    return .failure(.noRunsAvailable)
  }

  private func resolveTerminalFirst() throws -> Result<WorkflowRunRecord, RunResolutionFailure> {
    if let loadTerminal = loadLatestTerminalRun, let run = try loadTerminal() {
      return .success(run)
    }

    let activeRun = try loadLatestActiveRun()
    let latestRun = try loadLatestRun()

    if let run = activeRun ?? latestRun {
      return .failure(.runStillInProgress(runId: run.runId))
    }

    return .failure(.noRunsAvailable)
  }
}

/// Describes why run-ID resolution failed.
public enum RunResolutionFailure: Error, Sendable {
  /// The caller supplied an empty or whitespace-only run ID.
  case emptyRunId
  /// No run record exists for the given ID.
  case notFound(runId: String)
  /// A run was found but is still in progress (used by ``RunResolver/Strategy/terminalFirst``).
  case runStillInProgress(runId: String)
  /// No diagnosis runs are available at all.
  case noRunsAvailable
  /// The underlying store threw an unexpected error.
  case loadFailed(underlyingError: Error)
}

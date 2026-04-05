import Foundation

// MARK: - DebuggerRegistryError

public enum DebuggerRegistryError: Error, CustomStringConvertible {
  case notFound(String)

  public var description: String {
    switch self {
    case .notFound(let id):
      return "Session not found or expired: \(id)"
    }
  }
}

// MARK: - DebuggerSessionRegistry

/// Actor-isolated singleton that owns all live `DebuggerSession` instances.
/// Sessions are keyed by their UUID string. Expired or detached sessions are
/// removed so subsequent lookups return `notFound` (→ `.fail("Session not found or expired")`).
public actor DebuggerSessionRegistry {

  // MARK: - Singleton

  public static let shared = DebuggerSessionRegistry()

  // MARK: - Properties

  private var sessions: [String: DebuggerSession] = [:]

  // MARK: - Initialization

  public init() {}

  // MARK: - Public Methods

  /// Create a new session for an already-launched `DebuggerSession` and return its ID.
  public func create(session: DebuggerSession) -> String {
    let id = session.sessionID
    sessions[id] = session
    return id
  }

  /// Look up a session by ID. Throws `notFound` if absent or expired.
  public func session(for id: String) throws -> DebuggerSession {
    guard let session = sessions[id] else {
      throw DebuggerRegistryError.notFound(id)
    }
    return session
  }

  /// Async-throwing lookup — same semantics as `session(for:)` but callable from async context.
  public func lookupSession(for id: String) async throws -> DebuggerSession {
    guard let session = sessions[id] else {
      throw DebuggerRegistryError.notFound(id)
    }
    return session
  }

  /// Remove a session from the registry (and terminate the underlying process).
  public func remove(id: String) {
    if let session = sessions.removeValue(forKey: id) {
      Task { await session.terminate() }
    }
  }

  /// Remove and terminate all sessions.
  public func removeAll() {
    let all = sessions
    sessions.removeAll()
    for (_, session) in all {
      Task { await session.terminate() }
    }
  }
}

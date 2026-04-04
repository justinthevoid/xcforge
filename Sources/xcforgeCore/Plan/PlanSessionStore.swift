import Foundation

/// Actor-based store for suspended plans. Sessions auto-expire after 5 minutes.
public actor PlanSessionStore {
    public static let shared = PlanSessionStore()

    private var sessions: [String: Entry] = [:]
    private let ttl: TimeInterval = 300 // 5 minutes

    private struct Entry {
        let plan: SuspendedPlan
        let createdAt: Date
    }

    /// Store a suspended plan. Returns the session ID.
    public func store(_ plan: SuspendedPlan) -> String {
        purgeExpired()
        let id = UUID().uuidString
        sessions[id] = Entry(plan: plan, createdAt: Date())
        return id
    }

    /// Consume a suspended plan (one-shot retrieval). Returns nil if expired or not found.
    public func consume(_ sessionId: String) -> SuspendedPlan? {
        purgeExpired()
        guard let entry = sessions.removeValue(forKey: sessionId) else { return nil }
        return entry.plan
    }

    /// Check if a session exists (without consuming).
    public func exists(_ sessionId: String) -> Bool {
        purgeExpired()
        return sessions[sessionId] != nil
    }

    /// Number of active sessions.
    public var count: Int {
        purgeExpired()
        return sessions.count
    }

    private func purgeExpired() {
        let now = Date()
        sessions = sessions.filter { now.timeIntervalSince($0.value.createdAt) < ttl }
    }
}

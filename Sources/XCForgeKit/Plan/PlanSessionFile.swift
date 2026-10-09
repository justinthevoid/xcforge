import Foundation
import MCP

/// Suspended plans saved to disk, so `xcforge plan decide` in a new process can resume what
/// `xcforge plan run` paused. The MCP server keeps its sessions in memory (`PlanSessionStore`).
public enum PlanSessionFile {
  /// How long a saved session can be resumed.
  public static let ttl: TimeInterval = 3600

  struct Saved: Codable {
    let steps: Value
    let pauseIndex: Int
    let question: String
    let completedResults: [StepResult]
    let variableBindings: [String: VariableStore.ElementBinding]
    let errorStrategy: String
    let timeoutSeconds: Double
    let startTime: Double
    let savedAt: Date
  }

  public static func directory(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
    if let override = environment["XCFORGE_PLAN_SESSION_DIR"], !override.isEmpty { return override }
    return NSHomeDirectory() + "/.xcforge/plan-sessions"
  }

  static func path(for id: String, in directory: String) -> String? {
    // Session IDs are UUIDs; anything else must not become a path.
    guard UUID(uuidString: id) != nil else { return nil }
    return (directory as NSString).appendingPathComponent("\(id).json")
  }

  /// Save a suspended plan with the raw steps it was parsed from. Returns the session ID.
  public static func save(_ plan: SuspendedPlan, steps: [Value], directory: String = directory()) throws -> String {
    let id = UUID().uuidString
    let saved = Saved(
      steps: .array(steps), pauseIndex: plan.pauseIndex, question: plan.question,
      completedResults: plan.completedResults, variableBindings: plan.variableBindings,
      errorStrategy: plan.errorStrategy.rawValue, timeoutSeconds: plan.timeoutSeconds,
      startTime: plan.startTime, savedAt: Date())
    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    let data = try JSONEncoder().encode(saved)
    guard let path = path(for: id, in: directory) else { return id }
    try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    return id
  }

  public enum LoadError: Error, CustomStringConvertible {
    case notFound(String)
    case expired(String)
    case unreadable(String)

    public var description: String {
      switch self {
      case .notFound(let id): return "Session '\(id)' not found. Re-run the plan."
      case .expired(let id): return "Session '\(id)' expired (1-hour limit). Re-run the plan."
      case .unreadable(let detail): return "Saved session can't be read: \(detail). Re-run the plan."
      }
    }
  }

  /// Load and delete a saved session, with the raw steps for saving it again if it pauses once
  /// more. The time it spent waiting for a decision doesn't count against the plan's timeout.
  public static func consume(_ id: String, directory: String = directory(), now: Date = Date()) throws -> Resumed {
    guard let path = path(for: id, in: directory), let data = FileManager.default.contents(atPath: path) else {
      throw LoadError.notFound(id)
    }
    try? FileManager.default.removeItem(atPath: path)
    let saved: Saved
    do {
      saved = try JSONDecoder().decode(Saved.self, from: data)
    } catch {
      throw LoadError.unreadable("\(error)")
    }
    let waited = now.timeIntervalSince(saved.savedAt)
    guard waited < ttl else { throw LoadError.expired(id) }
    guard case .array(let steps) = saved.steps else { throw LoadError.unreadable("steps are not an array") }
    let parsed: [PlanStep]
    do {
      parsed = try PlanParser.parse(steps)
    } catch {
      throw LoadError.unreadable("\(error)")
    }
    let plan = SuspendedPlan(
      steps: parsed, pauseIndex: saved.pauseIndex, question: saved.question,
      completedResults: saved.completedResults, variableBindings: saved.variableBindings,
      errorStrategy: ErrorStrategy(rawValue: saved.errorStrategy) ?? .abortWithScreenshot,
      timeoutSeconds: saved.timeoutSeconds, startTime: saved.startTime + max(waited, 0), screenshotBase64: nil)
    return Resumed(plan: plan, steps: steps)
  }

  public struct Resumed: Sendable {
    public let plan: SuspendedPlan
    /// The raw steps, for saving the plan again if it pauses once more.
    public let steps: [Value]
  }
}

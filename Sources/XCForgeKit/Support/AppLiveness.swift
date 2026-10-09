import Foundation

/// Whether an app launched on a simulator is still running a moment later, and why not.
///
/// `simctl launch` returns as soon as the process exists, so an app that crashes during
/// startup still "launches". Simulator apps are host processes, so their pid can be
/// checked with `ps`, and their crash reports land in the host's DiagnosticReports.
public enum AppLiveness {
  /// How long a launched app is watched before it counts as running. Startup crashes after
  /// `main` (a bad first view, a failed migration) often land a few seconds in, later on a
  /// loaded Mac. `XCFORGE_LAUNCH_WATCH_SECONDS` overrides it.
  static var settleSeconds: TimeInterval {
    seconds("XCFORGE_LAUNCH_WATCH_SECONDS", default: 8)
  }

  /// How long to wait for the crash report once the app has died. macOS writes `.ips` files
  /// late under memory pressure. `XCFORGE_CRASH_REPORT_WAIT_SECONDS` overrides it.
  static var reportWaitSeconds: TimeInterval {
    seconds("XCFORGE_CRASH_REPORT_WAIT_SECONDS", default: 15)
  }

  static func seconds(
    _ key: String, default fallback: TimeInterval,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> TimeInterval {
    guard let raw = environment[key], let value = TimeInterval(raw), value >= 0, value.isFinite else {
      return fallback
    }
    return value
  }

  enum Outcome: Equatable, Sendable {
    case running
    /// The app died; `afterSeconds` is roughly how long after launch it was found gone.
    case exited(CrashSummary?, afterSeconds: Double? = nil)
  }

  /// The pid in `simctl launch` output (`com.example.app: 1234`).
  public static func pid(fromLaunchOutput output: String) -> Int32? {
    for line in output.split(whereSeparator: \.isNewline).reversed() {
      let parts = line.split(separator: ":", omittingEmptySubsequences: false)
      // Only `<bundle id>: <pid>`; a URL with a port mustn't read as a pid.
      guard parts.count == 2, !parts[0].isEmpty, !parts[0].contains(where: \.isWhitespace) else { continue }
      if let pid = Int32(parts[1].trimmingCharacters(in: .whitespaces)) { return pid }
    }
    return nil
  }

  /// True when `pid` exists and isn't a zombie.
  static func isRunning(pid: Int32, env: Environment) async -> Bool {
    let arguments = ["-p", String(pid), "-o", "stat="]
    // When ps can't run, say running: never report a crash that wasn't seen.
    guard let result = try? await env.shell.run("/bin/ps", arguments: arguments, timeout: 5) else { return true }
    let state = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    return result.succeeded && !state.isEmpty && !state.hasPrefix("Z")
  }

  /// Watch the app for `settle` seconds, polling, and report whether it stayed up. When it
  /// died, wait up to `reportWait` seconds for the crash report it left.
  static func check(
    pid: Int32, bundleId: String, launchedAt: Date, settle: TimeInterval = settleSeconds,
    reportWait: TimeInterval = reportWaitSeconds, env: Environment
  ) async -> Outcome {
    let interval: TimeInterval = 0.5
    var watched: TimeInterval = 0
    var alive = true
    while watched < settle {
      let step = min(interval, settle - watched)
      try? await Task.sleep(nanoseconds: UInt64(step * 1_000_000_000))
      watched += step
      if !(await isRunning(pid: pid, env: env)) {
        alive = false
        break
      }
    }
    if alive, await isRunning(pid: pid, env: env) { return .running }
    let diedAfter = Date().timeIntervalSince(launchedAt)
    var waited: TimeInterval = 0
    while true {
      if let path = CrashReports.newest(bundleId: bundleId, after: launchedAt),
        let text = try? String(contentsOfFile: path, encoding: .utf8),
        let summary = CrashReports.summarize(text, path: path)
      {
        return .exited(summary, afterSeconds: diedAfter)
      }
      guard waited < reportWait else { break }
      try? await Task.sleep(nanoseconds: 1_000_000_000)
      waited += 1
    }
    return .exited(nil, afterSeconds: diedAfter)
  }

  /// One line per fact, for tool output.
  static func describe(_ outcome: Outcome, bundleId: String) -> String {
    switch outcome {
    case .running:
      return "App running: true"
    case .exited(nil, let after):
      let when = after.map { String(format: "about %.1fs after launch", $0) } ?? "soon after launch"
      return """
        App running: false (\(bundleId) exited \(when); no crash report yet. macOS can take a minute to \
        write it under load: look for the app's newest .ips in \(CrashReports.directory()))
        """
    case .exited(let summary?, let after):
      let when = after.map { String(format: " about %.1fs after launch", $0) } ?? " at launch"
      var lines = ["App running: false (\(bundleId) crashed\(when))", "Crash: \(summary.headline)"]
      lines += summary.frames.map { "  \($0)" }
      lines.append("Crash report: \(summary.path)")
      return lines.joined(separator: "\n")
    }
  }
}

/// The parts of a crash report an agent needs: what happened and where.
struct CrashSummary: Equatable, Sendable, Codable {
  let exception: String
  let reason: String?
  let frames: [String]
  let path: String

  var headline: String {
    reason.map { "\(exception): \($0)" } ?? exception
  }
}

enum CrashReports {
  static func directory() -> String {
    if let override = ProcessInfo.processInfo.environment["XCFORGE_CRASH_REPORTS_DIR"], !override.isEmpty {
      return override
    }
    return NSHomeDirectory() + "/Library/Logs/DiagnosticReports"
  }

  /// The newest `.ips` report for `bundleId` written after `date`.
  static func newest(bundleId: String, after date: Date, in directory: String = directory()) -> String? {
    let fm = FileManager.default
    guard let names = try? fm.contentsOfDirectory(atPath: directory) else { return nil }
    var best: (path: String, date: Date)?
    for name in names where name.hasSuffix(".ips") {
      let path = (directory as NSString).appendingPathComponent(name)
      guard let modified = (try? fm.attributesOfItem(atPath: path))?[.modificationDate] as? Date,
        modified >= date.addingTimeInterval(-1),
        best.map({ modified > $0.date }) ?? true,
        let header = headerLine(path),
        reportBundleID(header) == bundleId
      else { continue }
      best = (path, modified)
    }
    return best?.path
  }

  private static func headerLine(_ path: String) -> String? {
    guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
    defer { try? handle.close() }
    let data = (try? handle.read(upToCount: 4096)) ?? Data()
    return String(data: data, encoding: .utf8)?.split(whereSeparator: \.isNewline).first.map(String.init)
  }

  static func reportBundleID(_ header: String) -> String? {
    guard let data = header.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }
    return json["bundleID"] as? String
  }

  /// Exception, termination reason and the crashed thread's top frames from an `.ips`
  /// report (a JSON header line, then the JSON body).
  static func summarize(_ text: String, path: String, frameLimit: Int = 8) -> CrashSummary? {
    guard let newline = text.firstIndex(where: \.isNewline),
      let data = String(text[text.index(after: newline)...]).data(using: .utf8),
      let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }

    let exception = body["exception"] as? [String: Any]
    var name = (exception?["type"] as? String) ?? "crash"
    if let signal = exception?["signal"] as? String { name += " (\(signal))" }

    var reason: String?
    if let asi = body["asi"] as? [String: [String]], let first = asi.values.flatMap({ $0 }).first {
      reason = first
    } else if let termination = body["termination"] as? [String: Any] {
      reason = termination["indicator"] as? String
    }

    let images = (body["usedImages"] as? [[String: Any]]) ?? []
    let threads = (body["threads"] as? [[String: Any]]) ?? []
    let crashed = threads.first { ($0["triggered"] as? Bool) == true } ?? threads.first
    let frames = ((crashed?["frames"] as? [[String: Any]]) ?? []).prefix(frameLimit).map { frame -> String in
      let index = frame["imageIndex"] as? Int
      let image = index.flatMap { $0 < images.count ? images[$0]["name"] as? String : nil } ?? "?"
      if let symbol = frame["symbol"] as? String { return "\(image)  \(symbol)" }
      return "\(image)  +\(frame["imageOffset"] as? Int ?? 0)"
    }
    return CrashSummary(exception: name, reason: reason, frames: Array(frames), path: path)
  }
}

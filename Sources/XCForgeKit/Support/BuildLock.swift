import Foundation

/// A first-come, first-served build lock shared between sessions on one Mac.
///
/// The lock itself is a plain `flock(2)` on `path`, which is what macOS `lockf(1)` takes,
/// so xcforge queues correctly with shell wrappers such as `lockf /tmp/ios.lock xcodebuild ...`.
/// On top of that, xcforge waiters register a ticket in `<path>.queue/` and only try the
/// lock when their ticket is the oldest live one, so they are served in arrival order.
/// The current xcforge holder is recorded in `<path>.holder` for `xcforge lock status`.
public enum BuildLock {

  public struct Entry: Codable, Sendable, Equatable {
    public let pid: Int32
    public let command: String
    public let cwd: String
    public let since: Date
  }

  public struct Status: Sendable {
    public let lockPath: String
    /// True when someone holds the flock right now.
    public let held: Bool
    /// The xcforge process holding it, when the holder file is live.
    public let holder: Entry?
    /// Processes with the lock file open when the holder is not xcforge (e.g. a `lockf` wrapper).
    public let externalHolders: [String]
    /// xcforge waiters in queue order.
    public let queue: [Entry]
  }

  public struct Handle: Sendable {
    let fd: Int32
    let holderPath: String
    public let waitedSeconds: TimeInterval

    /// Release the lock. Safe to call once; the kernel also releases it if the process dies.
    public func release() {
      try? FileManager.default.removeItem(atPath: holderPath)
      _ = flock(fd, LOCK_UN)
      _ = close(fd)
    }
  }

  public enum LockError: Error, CustomStringConvertible {
    case cannotOpen(String, Int32)
    case timedOut(path: String, waited: TimeInterval, status: String)

    public var description: String {
      switch self {
      case .cannotOpen(let path, let code):
        return "Cannot open build lock \(path): \(String(cString: strerror(code)))"
      case .timedOut(let path, let waited, let status):
        return "Gave up waiting \(Int(waited))s for build lock \(path).\n\(status)"
      }
    }
  }

  static func queueDir(_ path: String) -> String { path + ".queue" }
  static func holderPath(_ path: String) -> String { path + ".holder" }

  // MARK: - Acquire

  /// Wait in line for the lock, then take it. Throws `LockError.timedOut` after `maxWait`.
  public static func acquire(
    path: String, label: String, maxWait: TimeInterval, pollInterval: TimeInterval = 1.0
  ) async throws -> Handle {
    let fm = FileManager.default
    let parent = (path as NSString).deletingLastPathComponent
    if !parent.isEmpty {
      try? fm.createDirectory(atPath: parent, withIntermediateDirectories: true, attributes: nil)
    }
    let queue = queueDir(path)
    try? fm.createDirectory(atPath: queue, withIntermediateDirectories: true, attributes: nil)

    let fd = open(path, O_RDWR | O_CREAT | O_CLOEXEC, 0o644)
    guard fd >= 0 else { throw LockError.cannotOpen(path, errno) }

    let pid = ProcessInfo.processInfo.processIdentifier
    let me = Entry(pid: pid, command: label, cwd: fm.currentDirectoryPath, since: Date())
    let nanos = UInt64(Date().timeIntervalSince1970 * 1_000_000_000)
    let ticketName = String(format: "%020llu-%d.json", nanos, pid)
    let ticketPath = (queue as NSString).appendingPathComponent(ticketName)
    write(me, to: ticketPath)

    let start = Date()
    var announced = false
    while true {
      let waiting = liveTickets(in: queue)
      let first = waiting.first?.name
      if first == nil || first == ticketName {
        if flock(fd, LOCK_EX | LOCK_NB) == 0 {
          try? fm.removeItem(atPath: ticketPath)
          let waited = Date().timeIntervalSince(start)
          let holder = Entry(pid: pid, command: label, cwd: me.cwd, since: Date())
          write(holder, to: holderPath(path))
          if announced {
            Log.warn("Build lock \(path) acquired after \(Int(waited))s")
          }
          return Handle(fd: fd, holderPath: holderPath(path), waitedSeconds: waited)
        }
      }
      if !announced {
        let ahead = waiting.firstIndex { $0.name == ticketName } ?? 0
        Log.warn("Waiting for build lock \(path) (\(ahead) queued ahead)")
        announced = true
      }
      let waited = Date().timeIntervalSince(start)
      if waited >= maxWait || Task.isCancelled {
        try? fm.removeItem(atPath: ticketPath)
        _ = close(fd)
        let snapshot = format(status(path: path, externalHolders: []))
        throw LockError.timedOut(path: path, waited: waited, status: snapshot)
      }
      try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
    }
  }

  // MARK: - Status

  /// Read the lock's holder and queue. `externalHolders` is filled in by the caller
  /// (e.g. from `lsof`) since this function performs no subprocess calls.
  public static func status(path: String, externalHolders: [String]) -> Status {
    var held = false
    let fd = open(path, O_RDONLY | O_CLOEXEC)
    if fd >= 0 {
      if flock(fd, LOCK_EX | LOCK_NB) == 0 {
        _ = flock(fd, LOCK_UN)
      } else {
        held = true
      }
      _ = close(fd)
    }
    var holder: Entry? = read(holderPath(path))
    if let h = holder, !isAlive(h.pid) || !held { holder = nil }
    let queue = liveTickets(in: queueDir(path)).map(\.entry)
    return Status(
      lockPath: path, held: held, holder: holder,
      externalHolders: held && holder == nil ? externalHolders : [], queue: queue)
  }

  /// Status including processes outside xcforge that have the lock file open (via `lsof`).
  public static func status(path: String, env: Environment) async -> Status {
    let first = status(path: path, externalHolders: [])
    guard first.held, first.holder == nil else { return first }
    var holders: [String] = []
    if let result = try? await env.shell.run(
      "/usr/sbin/lsof", arguments: ["-F", "pc", path], timeout: 5)
    {
      holders = externalHolders(lsofOutput: result.stdout, queued: Set(first.queue.map { String($0.pid) }))
    }
    return status(path: path, externalHolders: holders)
  }

  /// Processes `lsof -F pc` shows with the lock file open, minus xcforge processes that are
  /// only queued for it (they open the file to wait).
  static func externalHolders(lsofOutput: String, queued: Set<String>) -> [String] {
    var holders: [String] = []
    var pid: String?
    for line in lsofOutput.split(separator: "\n") {
      if line.hasPrefix("p") {
        pid = String(line.dropFirst())
      } else if line.hasPrefix("c"), let p = pid, !queued.contains(p) {
        holders.append("pid \(p) \(line.dropFirst())")
      }
    }
    return holders
  }

  /// Resolve the lock path from explicit value, `XCFORGE_BUILD_LOCK` or `.xcforge.yaml`.
  public static func configuredPath(explicit: String?, cwd: String) -> String? {
    if let explicit, !explicit.isEmpty { return explicit }
    return XcodebuildOptions.effective(cwd: cwd).lockPath
  }

  /// Human-readable rendering of a status.
  public static func format(_ status: Status, now: Date = Date()) -> String {
    var lines = ["Build lock: \(status.lockPath)"]
    if !status.held {
      lines.append("Holder: none (free)")
    } else if let h = status.holder {
      let held = Int(now.timeIntervalSince(h.since))
      lines.append("Holder: xcforge pid \(h.pid), \(held)s — \(h.command)")
      lines.append("  cwd: \(h.cwd)")
    } else if !status.externalHolders.isEmpty {
      lines.append("Holder: outside xcforge")
      for p in status.externalHolders { lines.append("  \(p)") }
    } else {
      lines.append("Holder: outside xcforge (process unknown)")
    }
    if status.queue.isEmpty {
      lines.append("Queue: empty")
    } else {
      lines.append("Queue (\(status.queue.count), first-come first-served):")
      for (i, e) in status.queue.enumerated() {
        let waited = Int(now.timeIntervalSince(e.since))
        lines.append("  \(i + 1). pid \(e.pid), waiting \(waited)s — \(e.command)")
      }
    }
    return lines.joined(separator: "\n")
  }

  // MARK: - Helpers

  struct Ticket {
    let name: String
    let entry: Entry
  }

  /// Tickets of live waiters in arrival order. Tickets left by dead processes are removed.
  static func liveTickets(in dir: String) -> [Ticket] {
    let fm = FileManager.default
    guard let names = try? fm.contentsOfDirectory(atPath: dir) else { return [] }
    var tickets: [Ticket] = []
    for name in names.sorted() where name.hasSuffix(".json") {
      let full = (dir as NSString).appendingPathComponent(name)
      guard let entry: Entry = read(full) else { continue }
      if isAlive(entry.pid) {
        tickets.append(Ticket(name: name, entry: entry))
      } else {
        try? fm.removeItem(atPath: full)
      }
    }
    return tickets
  }

  static func isAlive(_ pid: Int32) -> Bool {
    if pid <= 0 { return false }
    return kill(pid, 0) == 0 || errno == EPERM
  }

  private static func write(_ entry: Entry, to path: String) {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    guard let data = try? encoder.encode(entry) else { return }
    try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
  }

  private static func read(_ path: String) -> Entry? {
    guard let data = FileManager.default.contents(atPath: path) else { return nil }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try? decoder.decode(Entry.self, from: data)
  }
}

import Foundation

/// A capture process (a log stream, an app's console) that outlives the CLI command that
/// started it. Each CLI command is its own process, so an in-memory buffer is gone by the
/// time `read` runs; this writes the stream to files and keeps the pid in a state file, so
/// `start`, `read` and `stop` can be separate commands.
public struct DetachedCapture: Sendable {
  public struct State: Codable, Sendable {
    public let pid: Int32
    public let mode: String?
    public let bundleId: String?
    public let startedAt: Date
    /// Byte offsets reads start from, per stream: `clear` moves them to the end.
    public var readFrom: [String: UInt64]
  }

  public enum Stream: String, Sendable, CaseIterable {
    case stdout, stderr
  }

  public let name: String
  public let directory: String

  public init(name: String, directory: String = DetachedCapture.defaultDirectory()) {
    self.name = name
    self.directory = directory
  }

  /// The simulator log stream started by `xcforge log start`.
  public static var log: DetachedCapture { DetachedCapture(name: "log") }
  /// The app console started by `xcforge console launch`.
  public static var console: DetachedCapture { DetachedCapture(name: "console") }

  public static func defaultDirectory() -> String {
    if let override = ProcessInfo.processInfo.environment["XCFORGE_CAPTURE_DIR"], !override.isEmpty {
      return override
    }
    return NSHomeDirectory() + "/.xcforge/capture"
  }

  var statePath: String { (directory as NSString).appendingPathComponent("\(name).json") }

  public func outputPath(_ stream: Stream) -> String {
    (directory as NSString).appendingPathComponent("\(name).\(stream.rawValue).log")
  }

  /// Start `executable arguments` under nohup with its output going to files, replacing
  /// any capture of the same name. Environment entries are added to this process's own.
  @discardableResult
  public func start(
    executable: String = "/usr/bin/xcrun", arguments: [String], environment: [String: String] = [:],
    captureStderr: Bool = false, mode: String? = nil, bundleId: String? = nil
  ) throws -> State {
    stop()
    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    for stream in Stream.allCases {
      FileManager.default.createFile(atPath: outputPath(stream), contents: nil)
    }
    guard let out = FileHandle(forWritingAtPath: outputPath(.stdout)),
      let err = FileHandle(forWritingAtPath: outputPath(.stderr))
    else { throw CocoaError(.fileWriteUnknown) }
    defer {
      try? out.close()
      try? err.close()
    }

    let process = Process()
    // nohup keeps the capture alive when the shell that ran the CLI goes away.
    process.executableURL = URL(fileURLWithPath: "/usr/bin/nohup")
    process.arguments = [executable] + arguments
    if !environment.isEmpty {
      process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
    }
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = out
    process.standardError = captureStderr ? err : FileHandle.nullDevice
    try process.run()

    let state = State(
      pid: process.processIdentifier, mode: mode, bundleId: bundleId, startedAt: Date(), readFrom: [:])
    try save(state)
    return state
  }

  /// Stop the capture. Returns false when none was running.
  @discardableResult
  public func stop() -> Bool {
    guard let state = state() else { return false }
    let running = Self.isAlive(state.pid)
    if running { kill(state.pid, SIGTERM) }
    try? FileManager.default.removeItem(atPath: statePath)
    return running
  }

  public func state() -> State? {
    guard let data = FileManager.default.contents(atPath: statePath) else { return nil }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try? decoder.decode(State.self, from: data)
  }

  public var isRunning: Bool {
    state().map { Self.isAlive($0.pid) } ?? false
  }

  /// Whether a capture was started and its output is still on disk, running or not.
  public var exists: Bool { state() != nil }

  static func isAlive(_ pid: Int32) -> Bool {
    pid > 0 && kill(pid, 0) == 0
  }

  /// Lines written since the last `clear` (or since `fromByte`, when given).
  public func lines(_ stream: Stream, fromByte: UInt64? = nil) -> [String] {
    let start = fromByte ?? state()?.readFrom[stream.rawValue] ?? 0
    guard let handle = FileHandle(forReadingAtPath: outputPath(stream)) else { return [] }
    defer { try? handle.close() }
    try? handle.seek(toOffset: start)
    let data = (try? handle.readToEnd()) ?? Data()
    return String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
  }

  /// Complete lines written after byte `offset`, and the offset to read from next. A line
  /// still being written stays for the next call.
  public func newLines(_ stream: Stream, after offset: UInt64) -> (lines: [String], next: UInt64) {
    guard let handle = FileHandle(forReadingAtPath: outputPath(stream)) else { return ([], offset) }
    defer { try? handle.close() }
    try? handle.seek(toOffset: offset)
    let data = (try? handle.readToEnd()) ?? Data()
    guard let lastNewline = data.lastIndex(of: UInt8(ascii: "\n")) else { return ([], offset) }
    let complete = data[data.startIndex...lastNewline]
    let lines = String(decoding: complete, as: UTF8.self).split(separator: "\n").map(String.init)
    return (lines, offset + UInt64(complete.count))
  }

  /// The current end of a stream's output, for reading only what comes after it.
  public func byteCount(_ stream: Stream) -> UInt64 {
    let size = (try? FileManager.default.attributesOfItem(atPath: outputPath(stream)))?[.size]
    return (size as? NSNumber)?.uint64Value ?? 0
  }

  /// Skip everything captured so far on later reads.
  public func clear() {
    guard var state = state() else { return }
    for stream in Stream.allCases {
      state.readFrom[stream.rawValue] = byteCount(stream)
    }
    try? save(state)
  }

  private func save(_ state: State) throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(state).write(to: URL(fileURLWithPath: statePath), options: .atomic)
  }
}

/// Reading a capture: the newest lines by default, with a count of what was left out.
public enum CaptureTail {
  /// How many lines a read returns when the caller doesn't say.
  public static let defaultLines = 200

  /// The last `last` lines (`defaultLines` when nil, everything when 0) and how many
  /// earlier lines were omitted.
  public static func tail(_ lines: [String], last: Int?) -> (lines: [String], omitted: Int) {
    let limit = last ?? defaultLines
    guard limit > 0, lines.count > limit else { return (lines, 0) }
    return (Array(lines.suffix(limit)), lines.count - limit)
  }

  /// Keep the end of `text` when it's over `limit` characters: the newest output matters most.
  public static func keepEnd(_ text: String, limit: Int) -> String {
    guard text.count > limit else { return text }
    return "... [earlier output truncated]\n" + String(text.suffix(limit))
  }

  public static func omittedNote(_ omitted: Int) -> String? {
    omitted > 0 ? "(\(omitted) earlier lines omitted; last 0 returns all)" : nil
  }
}

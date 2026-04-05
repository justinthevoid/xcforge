import ArgumentParser
import Foundation
import XCForgeKit

struct Logs: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "log",
    abstract: "Stream, read, and wait on simulator logs.",
    subcommands: [LogStart.self, LogStop.self, LogRead.self, LogWait.self],
    defaultSubcommand: LogRead.self
  )
}

// MARK: - LogResult (Codable wrapper for JSON output)

struct LogResult: Codable {
  let succeeded: Bool
  let message: String
  let lineCount: Int?
}

// MARK: - log start

struct LogStart: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "start",
    abstract: "Start capturing real-time logs from a simulator with smart filtering."
  )

  @Option(help: "Simulator name or UDID. Auto-detected from booted simulator if omitted.")
  var simulator: String?

  @Option(help: "Filter mode: app, smart, verbose. Default: smart")
  var mode: String?

  @Option(help: "Filter by process name (efficient server-side filter).")
  var process: String?

  @Option(help: "Filter by subsystem, e.g. 'com.myapp'. Bypasses mode logic.")
  var subsystem: String?

  @Option(help: "Custom NSPredicate filter. Bypasses mode logic.")
  var predicate: String?

  @Option(help: "Log level: default, info, debug. Default: debug")
  var level: String?

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    let useJSON = shouldOutputJSON(flag: json)
    let mode = self.mode ?? "smart"
    let level = self.level ?? "debug"

    let env = Environment.live
    let sim: String
    do {
      sim = try await env.session.resolveSimulator(simulator)
    } catch {
      let msg = "Failed to resolve simulator: \(error)"
      if useJSON {
        print(
          try WorkflowJSONRenderer.renderJSON(
            LogResult(succeeded: false, message: msg, lineCount: nil)))
      } else {
        print(msg)
      }
      throw ExitCode.failure
    }

    let (logArgs, note) = await LogTools.buildLogArgs(
      simulator: sim, mode: mode, level: level,
      process: process, subsystem: subsystem, predicate: predicate
    )

    do {
      try await LogCapture.shared.start(arguments: logArgs, mode: mode)
      let msg = "Log capture started (\(note))"
      if useJSON {
        print(
          try WorkflowJSONRenderer.renderJSON(
            LogResult(succeeded: true, message: msg, lineCount: nil)))
      } else {
        print(msg)
      }
    } catch {
      let msg = "Failed to start log capture: \(error)"
      if useJSON {
        print(
          try WorkflowJSONRenderer.renderJSON(
            LogResult(succeeded: false, message: msg, lineCount: nil)))
      } else {
        print(msg)
      }
      throw ExitCode.failure
    }
  }
}

// MARK: - log stop

struct LogStop: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "stop",
    abstract: "Stop the running log capture."
  )

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    let useJSON = shouldOutputJSON(flag: json)
    await LogCapture.shared.stop()
    let msg = "Log capture stopped"
    if useJSON {
      print(
        try WorkflowJSONRenderer.renderJSON(
          LogResult(succeeded: true, message: msg, lineCount: nil)))
    } else {
      print(msg)
    }
  }
}

// MARK: - log read

struct LogRead: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "read",
    abstract: "Read captured log lines with topic-based filtering."
  )

  @Option(
    name: .long, parsing: .singleValue,
    help:
      "Topics to include (repeatable): network, lifecycle, springboard, widgets, background, system. Default: app + crashes."
  )
  var include: [String] = []

  @Option(help: "Only return last N lines (applied after topic filtering).")
  var last: Int?

  @Flag(help: "Clear buffer after reading.")
  var clear = false

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    let useJSON = shouldOutputJSON(flag: json)
    var topics: Set<String> = ["app", "crashes"]
    for t in include {
      topics.insert(t)
    }

    let isRunning = await LogCapture.shared.isRunning
    let captureMode = await LogCapture.shared.captureMode
    let allLines: [String]
    if clear {
      allLines = await LogCapture.shared.readAndClear()
    } else {
      allLines = await LogCapture.shared.read(last: nil)
    }

    if allLines.isEmpty {
      let statusNote = isRunning ? " (capture is running)" : " (capture not running)"
      let msg = "No log lines captured\(statusNote)"
      if useJSON {
        print(
          try WorkflowJSONRenderer.renderJSON(
            LogResult(succeeded: true, message: msg, lineCount: 0)))
      } else {
        print(msg)
      }
      return
    }

    // Get session info for topic categorization
    let env = Environment.live
    let bundleId = await env.session.bundleId
    let appPath = await env.session.appPath
    let processName = appPath.flatMap { LogTools.deriveProcessName(from: $0) }

    // Filter by topics
    let filterResult = LogTools.filterByTopics(
      lines: allLines, include: topics,
      bundleId: bundleId, processName: processName
    )

    // Apply `last` AFTER filtering
    let finalLines: [String]
    if let n = last {
      finalLines = Array(filterResult.filteredLines.suffix(n))
    } else {
      finalLines = filterResult.filteredLines
    }

    if useJSON {
      let output = finalLines.joined(separator: "\n")
      let truncated =
        output.count > 50000 ? String(output.prefix(50000)) + "\n... [truncated]" : output
      print(
        try WorkflowJSONRenderer.renderJSON(
          LogResult(succeeded: true, message: truncated, lineCount: finalLines.count)))
    } else {
      let summary = LogTools.buildTopicSummary(
        result: filterResult, include: topics,
        captureMode: captureMode, bundleId: bundleId
      )
      let output = finalLines.joined(separator: "\n")
      let truncated =
        output.count > 50000 ? String(output.prefix(50000)) + "\n... [truncated]" : output
      print(LogRenderer.renderRead(summary: summary, logs: truncated, lineCount: finalLines.count))
    }
  }
}

// MARK: - log wait

struct LogWait: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "wait",
    abstract: "Wait for a specific log pattern to appear in the log stream."
  )

  @Option(help: "Regex pattern to match in log lines.")
  var pattern: String

  @Option(help: "Max seconds to wait. Default: 30")
  var timeout: Double?

  @Option(
    help: "Simulator name or UDID. Auto-detected if omitted (used if log capture not running).")
  var simulator: String?

  @Option(help: "Filter by subsystem (used if log capture not running).")
  var subsystem: String?

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    let useJSON = shouldOutputJSON(flag: json)
    let timeout = self.timeout ?? 30.0

    // Compile regex
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
      let msg = "Invalid regex pattern: \(pattern)"
      if useJSON {
        print(
          try WorkflowJSONRenderer.renderJSON(
            LogResult(succeeded: false, message: msg, lineCount: nil)))
      } else {
        print(msg)
      }
      throw ExitCode.failure
    }

    // Resolve simulator
    let env = Environment.live
    let sim: String
    do {
      sim = try await env.session.resolveSimulator(simulator)
    } catch {
      let msg = "Failed to resolve simulator: \(error)"
      if useJSON {
        print(
          try WorkflowJSONRenderer.renderJSON(
            LogResult(succeeded: false, message: msg, lineCount: nil)))
      } else {
        print(msg)
      }
      throw ExitCode.failure
    }

    // Start log capture if not running
    let wasRunning = await LogCapture.shared.isRunning
    if !wasRunning {
      let (logArgs, _) = await LogTools.buildLogArgs(
        simulator: sim, mode: "smart", level: "debug",
        process: nil, subsystem: subsystem, predicate: nil
      )
      do {
        try await LogCapture.shared.start(arguments: logArgs)
      } catch {
        let msg = "Failed to start log capture: \(error)"
        if useJSON {
          print(
            try WorkflowJSONRenderer.renderJSON(
              LogResult(succeeded: false, message: msg, lineCount: nil)))
        } else {
          print(msg)
        }
        throw ExitCode.failure
      }
    }

    // Clear existing buffer to only match new lines
    _ = await LogCapture.shared.readAndClear()

    let startTime = CFAbsoluteTimeGetCurrent()
    let deadline = startTime + timeout
    var matchedLines: [String] = []

    // Poll for matches
    while CFAbsoluteTimeGetCurrent() < deadline {
      let lines = await LogCapture.shared.readAndClear()
      for line in lines {
        let range = NSRange(line.startIndex..., in: line)
        if regex.firstMatch(in: line, range: range) != nil {
          matchedLines.append(line)
        }
      }

      if !matchedLines.isEmpty {
        let elapsed = String(format: "%.1f", CFAbsoluteTimeGetCurrent() - startTime)
        let output = matchedLines.joined(separator: "\n")
        let truncated =
          output.count > 10000 ? String(output.prefix(10000)) + "\n... [truncated]" : output
        let msg = "Pattern matched after \(elapsed)s (\(matchedLines.count) line(s)):\n\(truncated)"
        if useJSON {
          print(
            try WorkflowJSONRenderer.renderJSON(
              LogResult(succeeded: true, message: msg, lineCount: matchedLines.count)))
        } else {
          print(msg)
        }
        return
      }

      try await Task.sleep(nanoseconds: 200_000_000)  // 200ms
    }

    // Timeout
    let elapsed = String(format: "%.1f", CFAbsoluteTimeGetCurrent() - startTime)
    let msg = "Timeout after \(elapsed)s -- pattern '\(pattern)' not found"
    if useJSON {
      print(
        try WorkflowJSONRenderer.renderJSON(LogResult(succeeded: false, message: msg, lineCount: 0))
      )
    } else {
      print(msg)
    }
    throw ExitCode.failure
  }
}

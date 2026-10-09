import ArgumentParser
import Foundation
import XCForgeKit

struct Console: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "console",
    abstract: "Launch, read, and stop app console output capture.",
    subcommands: [ConsoleLaunch.self, ConsoleRead.self, ConsoleStop.self],
    defaultSubcommand: ConsoleRead.self
  )
}

struct ConsoleResult: Codable {
  let succeeded: Bool
  let message: String
  let stdout: [String]?
  let stderr: [String]?
  let isRunning: Bool?
  let bundleId: String?
}

struct ConsoleLaunch: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "launch",
    abstract: "Launch an app with console output capture."
  )

  @Option(help: "Simulator name or UDID. Auto-detected from booted simulator if omitted.")
  var simulator: String?

  @Option(name: .long, help: "App bundle identifier. Auto-detected from last build if omitted.")
  var bundleId: String?

  @Option(help: "Space-separated launch arguments for the app.")
  var args: String?

  @Option(help: "Environment variable for the app, KEY=VALUE (repeatable).")
  var env: [String] = []

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    let useJSON = shouldOutputJSON(flag: json)
    let environment = Environment.live
    guard let resolvedBundleId = await environment.session.resolveBundleId(bundleId) else {
      let result = ConsoleResult(
        succeeded: false,
        message: "Missing bundle_id — provide --bundle-id or run build first",
        stdout: nil, stderr: nil, isRunning: nil, bundleId: nil
      )
      if useJSON {
        print(try ConsoleRenderer.renderJSON(result))
      } else {
        print(ConsoleRenderer.renderError(result.message))
      }
      throw ExitCode.failure
    }

    let launchArgs = args?.split(separator: " ").map(String.init) ?? []

    let sim: String
    let childEnvironment: [String: String]
    do {
      sim = try await environment.session.resolveSimulator(simulator)
      childEnvironment = try SimTools.parseEnvironment(env)
    } catch {
      let result = ConsoleResult(
        succeeded: false,
        message: "\(error)",
        stdout: nil, stderr: nil, isRunning: nil, bundleId: nil
      )
      if useJSON {
        print(try ConsoleRenderer.renderJSON(result))
      } else {
        print(ConsoleRenderer.renderError(result.message))
      }
      throw ExitCode.failure
    }

    do {
      let udid = try await SimTools.resolveSimulator(sim)
      // The console streams to files in the background, so `console read` in a later
      // command still sees it.
      var simctlArgs = ["simctl", "launch", "--console", "--terminate-running-process", udid, resolvedBundleId]
      simctlArgs += launchArgs
      var simctlEnvironment: [String: String] = [:]
      for (key, value) in childEnvironment {
        simctlEnvironment["SIMCTL_CHILD_" + key] = value
      }
      try DetachedCapture.console.start(
        arguments: simctlArgs, environment: simctlEnvironment, captureStderr: true, bundleId: resolvedBundleId)
      let msg = "Console capture started for \(resolvedBundleId). `xcforge console read` reads it."
      let result = ConsoleResult(
        succeeded: true,
        message: msg,
        stdout: nil, stderr: nil,
        isRunning: true,
        bundleId: resolvedBundleId
      )
      if useJSON {
        print(try ConsoleRenderer.renderJSON(result))
      } else {
        print(ConsoleRenderer.renderLaunch(result))
      }
    } catch {
      let result = ConsoleResult(
        succeeded: false,
        message: "Launch failed: \(error)",
        stdout: nil, stderr: nil, isRunning: false, bundleId: resolvedBundleId
      )
      if useJSON {
        print(try ConsoleRenderer.renderJSON(result))
      } else {
        print(ConsoleRenderer.renderError(result.message))
      }
      throw ExitCode.failure
    }
  }
}

struct ConsoleRead: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "read",
    abstract: "Read captured console output from a running app."
  )

  @Option(help: "Return the last N lines per stream. Default: 200; 0 returns all.")
  var last: Int?

  @Flag(help: "Clear buffer after reading.")
  var clear = false

  @Option(help: "Which stream to read: stdout, stderr, or both. Default: both.")
  var stream: String = "both"

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    let useJSON = shouldOutputJSON(flag: json)
    let capture = DetachedCapture.console
    let stdoutTail = CaptureTail.tail(capture.lines(.stdout), last: last)
    let stderrTail = CaptureTail.tail(capture.lines(.stderr), last: last)
    if clear { capture.clear() }

    var message = clear ? "Buffer cleared after reading" : "Console output read"
    if !capture.exists { message = "No console capture. Start one with `xcforge console launch`." }
    let omitted = (stream == "stderr" ? 0 : stdoutTail.omitted) + (stream == "stdout" ? 0 : stderrTail.omitted)
    if let note = CaptureTail.omittedNote(omitted) { message += " \(note)" }

    let result = ConsoleResult(
      succeeded: true,
      message: message,
      stdout: stream == "stderr" ? nil : stdoutTail.lines,
      stderr: stream == "stdout" ? nil : stderrTail.lines,
      isRunning: capture.isRunning,
      bundleId: capture.state()?.bundleId
    )

    if useJSON {
      print(try ConsoleRenderer.renderJSON(result))
    } else {
      print(ConsoleRenderer.renderRead(result, stream: stream, cleared: clear))
    }
  }
}

struct ConsoleStop: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "stop",
    abstract: "Stop the app console capture and terminate the app."
  )

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    let useJSON = shouldOutputJSON(flag: json)
    let stopped = DetachedCapture.console.stop()

    let result = ConsoleResult(
      succeeded: true,
      message: stopped ? "App console stopped" : "No console capture was running",
      stdout: nil, stderr: nil,
      isRunning: false, bundleId: nil
    )

    if useJSON {
      print(try ConsoleRenderer.renderJSON(result))
    } else {
      print(ConsoleRenderer.renderStop(result))
    }
  }
}

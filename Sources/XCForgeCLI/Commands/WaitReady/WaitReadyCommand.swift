import ArgumentParser
import Foundation
import XCForgeKit

/// `xcforge wait-ready` — standalone launch-readiness gate. Script-friendly:
/// exits non-zero on timeout so `wait-ready && screenshot` composes. Backed by
/// the same shared `ReadinessProbe` as `pose`/`screenshot` and `wait_ready`.
struct WaitReady: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "wait-ready",
    abstract: """
      Block until the screen is actually ready (real signal, not a blind \
      sleep). Signals (comma = all must hold): launch-complete, \
      a11y:<id>, text:<substring>. Exits non-zero on timeout.
      """
  )

  @Option(
    name: .customLong("for"),
    help:
      "Readiness signal(s), comma-separated (all must hold). e.g. 'a11y:home.title' or 'launch-complete,text:Welcome'. Default: launch-complete."
  )
  var signal: String = "launch-complete"

  @Option(
    help:
      "Ceiling in seconds. Capture happens the instant the signal holds, so a high ceiling costs nothing on the fast path. 0 skips the gate (pass-through): reports ready and exits 0. Default: 20."
  )
  var timeout: Double = 20

  @Option(help: "Poll cadence in milliseconds. Default: 150.")
  var pollMs: Int = 150

  @Option(help: "Simulator name or UDID. Auto-detected from booted simulator if omitted.")
  var simulator: String?

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    let useJSON = shouldOutputJSON(flag: json)
    let env = Environment.live

    let exec = await WaitReadyTools.executeWaitReady(
      signalSpec: signal,
      timeout: timeout,
      pollMs: pollMs,
      simulator: simulator,
      env: env
    )

    if useJSON {
      print(try WorkflowJSONRenderer.renderJSON(exec))
    } else {
      var lines: [String] = []
      lines.append(exec.ready ? "Ready" : "NOT ready")
      lines.append("mode: \(exec.mode)")
      lines.append("elapsedMs: \(exec.elapsedMs)")
      lines.append("signals: \(exec.signals.joined(separator: ", "))")
      lines.append("satisfied: \(exec.satisfied.joined(separator: ", "))")
      if let reason = exec.reason { lines.append("reason: \(reason)") }
      print(lines.joined(separator: "\n"))
    }

    if !exec.ready {
      throw ExitCode.failure
    }
  }
}

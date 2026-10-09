import ArgumentParser
import Foundation
import XCForgeKit

struct WDA: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "wda",
    abstract: "Run WebDriverAgent on a physical device so `xcforge ui` commands can drive it.",
    discussion: """
      `wda start` builds and signs the runner for the device, launches it, and records its URL.
      Then point UI commands at the device with XCFORGE_DEVICE=<udid> (or WDA_BASE_URL=<url>).
      The device must be unlocked, in Developer Mode, with Settings > Developer > Enable UI
      Automation turned on.
      """,
    subcommands: [WDAStart.self, WDAStatus.self, WDAStop.self],
    defaultSubcommand: WDAStatus.self
  )
}

struct WDAStart: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "start",
    abstract: "Build, sign and start WebDriverAgent on a device (reuses a runner that already answers)."
  )

  @Option(help: "Device name or UDID.")
  var device: String

  @Option(help: "Apple development team ID for signing. Default: XCFORGE_WDA_TEAM.")
  var team: String?

  @Option(help: "Runner bundle id. Default: com.xcforge.wda.<team>.runner.")
  var bundleId: String?

  @Option(help: "Port WDA listens on.")
  var port: Int = DeviceWDA.defaultPort

  @Option(help: "Seconds to wait for the runner to answer after launch.")
  var startTimeout: Int = 120

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  @OptionGroup var xcodebuild: XcodebuildOptionGroup

  mutating func run() async throws {
    let command = self
    try await xcodebuild.scoped { try await command.execute() }
  }

  func execute() async throws {
    let state: DeviceWDA.State
    do {
      state = try await DeviceWDA.start(
        device: device, team: team, bundleID: bundleId, port: port,
        startTimeout: TimeInterval(startTimeout), env: Environment.live)
    } catch {
      fputs("\(error)\n", stderr)
      throw ExitCode.failure
    }
    if shouldOutputJSON(flag: json) {
      print(try WorkflowJSONRenderer.renderJSON(state))
    } else {
      print("WebDriverAgent running on \(state.name ?? state.udid) at \(state.url)")
      print("Use it from UI commands with:")
      print("  export XCFORGE_DEVICE=\(state.udid)")
      print("Runner log: \(state.logPath)")
    }
  }
}

struct WDAStatus: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "status",
    abstract: "Show device runners started with `wda start` and whether they answer."
  )

  @Option(help: "Only this device (name or UDID).")
  var device: String?

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  struct Entry: Codable {
    let udid: String
    let name: String?
    let url: String
    let pid: Int32
    let healthy: Bool
    let logPath: String
  }

  mutating func run() async throws {
    var states = DeviceWDA.all()
    if let device { states = states.filter { $0.udid == device || $0.name == device } }
    var entries: [Entry] = []
    for state in states {
      entries.append(
        Entry(
          udid: state.udid, name: state.name, url: state.url, pid: state.pid,
          healthy: await DeviceWDA.isHealthy(state.url), logPath: state.logPath))
    }
    if shouldOutputJSON(flag: json) {
      print(try WorkflowJSONRenderer.renderJSON(entries))
      return
    }
    if entries.isEmpty {
      print("No device runners recorded. Start one with `xcforge wda start --device <udid>`.")
      return
    }
    for e in entries {
      print("\(e.name ?? e.udid): \(e.healthy ? "answering" : "NOT answering") at \(e.url) (pid \(e.pid))")
    }
  }
}

struct WDAStop: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "stop",
    abstract: "Stop the WebDriverAgent runner started on a device."
  )

  @Option(help: "Device name or UDID.")
  var device: String

  mutating func run() async throws {
    let known = DeviceWDA.load(device: device) != nil
    await DeviceWDA.stop(device: device, env: Environment.live)
    print(known ? "Stopped WebDriverAgent on \(device)" : "No WebDriverAgent recorded for \(device)")
  }
}

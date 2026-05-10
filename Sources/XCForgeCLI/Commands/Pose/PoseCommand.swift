import ArgumentParser
import Foundation
import XCForgeKit

/// Sugar over `build run` that appends `<key> <name>` to the simulator launch
/// argv. Apps with a debug router that reads ProcessInfo.arguments can use this
/// to jump directly into a target screen on every iteration.
struct Pose: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "pose",
    abstract: """
      Build, install, and launch the app with a launch arg appended (default key: -pose). \
      Apps with a debug router can map this to deep-link into a specific screen.
      """
  )

  @Argument(help: "Pose name to pass after the launch-arg key (e.g. 'Settings').")
  var name: String

  @Option(help: "Launch-arg key. Default: -pose")
  var key: String = "-pose"

  @Option(help: "Path to .xcodeproj or .xcworkspace. Auto-detected if omitted.")
  var project: String?

  @Option(help: "Xcode scheme name. Auto-detected if omitted.")
  var scheme: String?

  @Option(help: "Simulator name or UDID. Auto-detected from booted simulator if omitted.")
  var simulator: String?

  @Option(help: "Build configuration (Debug/Release). Default: Debug")
  var configuration: String?

  @Option(
    help:
      "Optional output path. After a successful launch, capture a PNG to this path. Failures here only warn."
  )
  var screenshot: String?

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    let useJSON = shouldOutputJSON(flag: json)
    let env = Environment.live

    let exec = await PoseTools.executePose(
      name: name,
      key: key,
      project: project,
      scheme: scheme,
      simulator: simulator,
      configuration: configuration ?? "Debug",
      screenshotPath: screenshot,
      env: env
    )

    if useJSON {
      print(try WorkflowJSONRenderer.renderJSON(exec))
    } else {
      var lines: [String] = []
      if exec.succeeded {
        lines.append("Posed '\(exec.pose)' in \(exec.elapsed)s")
      } else {
        lines.append("Pose '\(exec.pose)' FAILED in \(exec.elapsed)s")
      }
      lines.append("Key: \(exec.key)")
      lines.append("Scheme: \(exec.scheme)")
      lines.append("Simulator: \(exec.simulator)")
      if let bid = exec.bundleId { lines.append("Bundle ID: \(bid)") }
      if let path = exec.appPath { lines.append("App path: \(path)") }
      lines.append("Launch: \(exec.launchMessage)")
      if let path = exec.screenshotPath { lines.append("Screenshot: \(path)") }
      if let warning = exec.screenshotWarning { lines.append("Warning: \(warning)") }
      print(lines.joined(separator: "\n"))
    }

    if !exec.succeeded {
      throw ExitCode.failure
    }
  }
}

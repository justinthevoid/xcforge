import ArgumentParser
import Foundation
import XCForgeKit

struct Lock: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "lock",
    abstract: "Inspect the shared build lock.",
    subcommands: [LockStatus.self],
    defaultSubcommand: LockStatus.self
  )
}

struct LockStatus: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "status",
    abstract: "Show who holds the build lock, who is queued, and for how long."
  )

  @Option(name: .customLong("lock"), help: "Lock file. Default: XCFORGE_BUILD_LOCK or .xcforge.yaml buildLock.")
  var lockPath: String?

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    let env = Environment.live
    guard
      let path = BuildLock.configuredPath(
        explicit: lockPath.map { ($0 as NSString).expandingTildeInPath },
        cwd: env.currentDirectoryPath())
    else {
      print("No build lock configured. Pass --lock, set XCFORGE_BUILD_LOCK, or add buildLock to .xcforge.yaml.")
      throw ExitCode.validationFailure
    }
    let status = await BuildLock.status(path: path, env: env)
    if shouldOutputJSON(flag: json) {
      let now = Date()
      let payload: [String: Any] = [
        "lock": status.lockPath,
        "held": status.held,
        "holder": status.holder.map { holder -> Any in
          [
            "pid": Int(holder.pid), "command": holder.command, "cwd": holder.cwd,
            "heldSeconds": Int(now.timeIntervalSince(holder.since)),
          ]
        } ?? NSNull(),
        "externalHolders": status.externalHolders,
        "queue": status.queue.map { entry -> [String: Any] in
          [
            "pid": Int(entry.pid), "command": entry.command,
            "waitingSeconds": Int(now.timeIntervalSince(entry.since)),
          ]
        },
      ]
      let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
      print(String(decoding: data, as: UTF8.self))
    } else {
      print(BuildLock.format(status))
    }
  }
}

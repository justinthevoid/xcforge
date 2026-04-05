import ArgumentParser
import Foundation
import XCForgeKit

struct Sim: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "sim",
    abstract: "Manage iOS simulators (list, boot, shutdown, install, launch, and more).",
    subcommands: [
      SimList.self, SimBoot.self, SimShutdown.self,
      SimInstall.self, SimLaunch.self, SimTerminate.self,
      SimClone.self, SimErase.self, SimDelete.self,
      SimOrientation.self, SimRecordStart.self, SimRecordStop.self,
      SimLocation.self, SimLocationReset.self,
      SimAppearance.self, SimStatusBar.self, SimStatusBarClear.self,
    ],
    defaultSubcommand: SimList.self
  )
}

struct SimList: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "list",
    abstract: "List available iOS simulators with their state and UDID."
  )

  @Option(help: "Filter simulators by name, state, or runtime (e.g. 'iPhone', 'Booted').")
  var filter: String?

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    let useJSON = shouldOutputJSON(flag: json)
    let env = Environment.live
    let result = await SimTools.executeListSims(filter: filter, env: env)

    if useJSON {
      print(try WorkflowJSONRenderer.renderJSON(result))
    } else {
      print(SimRenderer.render(result))
    }

    if !result.succeeded {
      throw ExitCode.failure
    }
  }
}

struct SimBoot: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "boot",
    abstract: "Boot an iOS simulator by name or UDID."
  )

  @Argument(help: "Simulator name or UDID.")
  var simulator: String

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    let useJSON = shouldOutputJSON(flag: json)
    let env = Environment.live
    let result = await SimTools.executeBootSim(simulator: simulator, env: env)

    if useJSON {
      print(try WorkflowJSONRenderer.renderJSON(result))
    } else {
      print(SimRenderer.render(result))
    }

    if !result.succeeded {
      throw ExitCode.failure
    }
  }
}

struct SimShutdown: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "shutdown",
    abstract: "Shutdown a running simulator. Use 'all' to shutdown all simulators."
  )

  @Argument(help: "Simulator name or UDID. Use 'all' to shutdown all.")
  var simulator: String

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    let useJSON = shouldOutputJSON(flag: json)
    let env = Environment.live
    let result = await SimTools.executeShutdownSim(simulator: simulator, env: env)

    if useJSON {
      print(try WorkflowJSONRenderer.renderJSON(result))
    } else {
      print(SimRenderer.render(result))
    }

    if !result.succeeded {
      throw ExitCode.failure
    }
  }
}

struct SimInstall: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "install",
    abstract:
      "Install an app bundle on a booted simulator. Auto-detects from last build if omitted."
  )

  @Option(help: "Simulator name or UDID. Auto-detected from booted simulator if omitted.")
  var simulator: String?

  @Option(help: "Path to .app bundle. Auto-detected from last build if omitted.")
  var appPath: String?

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    let useJSON = shouldOutputJSON(flag: json)
    let env = Environment.live
    let result = await SimTools.executeInstallApp(simulator: simulator, appPath: appPath, env: env)

    if useJSON {
      print(try WorkflowJSONRenderer.renderJSON(result))
    } else {
      print(SimRenderer.render(result))
    }

    if !result.succeeded {
      throw ExitCode.failure
    }
  }
}

struct SimLaunch: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "launch",
    abstract: "Launch an app on a booted simulator. Auto-detects from last build if omitted."
  )

  @Option(help: "Simulator name or UDID. Auto-detected from booted simulator if omitted.")
  var simulator: String?

  @Option(help: "App bundle identifier. Auto-detected from last build if omitted.")
  var bundleId: String?

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    let useJSON = shouldOutputJSON(flag: json)
    let env = Environment.live
    let result = await SimTools.executeLaunchApp(simulator: simulator, bundleId: bundleId, env: env)

    if useJSON {
      print(try WorkflowJSONRenderer.renderJSON(result))
    } else {
      print(SimRenderer.render(result))
    }

    if !result.succeeded {
      throw ExitCode.failure
    }
  }
}

struct SimTerminate: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "terminate",
    abstract: "Terminate a running app on a simulator. Auto-detects from last build if omitted."
  )

  @Option(help: "Simulator name or UDID. Auto-detected from booted simulator if omitted.")
  var simulator: String?

  @Option(help: "App bundle identifier. Auto-detected from last build if omitted.")
  var bundleId: String?

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    let useJSON = shouldOutputJSON(flag: json)
    let env = Environment.live
    let result = await SimTools.executeTerminateApp(
      simulator: simulator, bundleId: bundleId, env: env)

    if useJSON {
      print(try WorkflowJSONRenderer.renderJSON(result))
    } else {
      print(SimRenderer.render(result))
    }

    if !result.succeeded {
      throw ExitCode.failure
    }
  }
}

struct SimClone: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "clone",
    abstract: "Clone a simulator to create a snapshot of its current state."
  )

  @Argument(help: "Source simulator name or UDID.")
  var simulator: String

  @Option(help: "Name for the cloned simulator.")
  var name: String

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    let useJSON = shouldOutputJSON(flag: json)
    let env = Environment.live
    let result = await SimTools.executeCloneSim(simulator: simulator, name: name, env: env)

    if useJSON {
      print(try WorkflowJSONRenderer.renderJSON(result))
    } else {
      print(SimRenderer.render(result))
    }

    if !result.succeeded {
      throw ExitCode.failure
    }
  }
}

struct SimErase: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "erase",
    abstract: "Erase a simulator to factory state. Simulator must be shut down first."
  )

  @Argument(help: "Simulator name, UDID, or 'all' to erase all simulators.")
  var simulator: String

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    let useJSON = shouldOutputJSON(flag: json)
    let env = Environment.live
    let result = await SimTools.executeEraseSim(simulator: simulator, env: env)

    if useJSON {
      print(try WorkflowJSONRenderer.renderJSON(result))
    } else {
      print(SimRenderer.render(result))
    }

    if !result.succeeded {
      throw ExitCode.failure
    }
  }
}

struct SimDelete: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "delete",
    abstract: "Permanently delete a simulator."
  )

  @Argument(help: "Simulator name or UDID to delete.")
  var simulator: String

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    let useJSON = shouldOutputJSON(flag: json)
    let env = Environment.live
    let result = await SimTools.executeDeleteSim(simulator: simulator, env: env)

    if useJSON {
      print(try WorkflowJSONRenderer.renderJSON(result))
    } else {
      print(SimRenderer.render(result))
    }

    if !result.succeeded {
      throw ExitCode.failure
    }
  }
}

struct SimOrientation: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "orientation",
    abstract:
      "Set device orientation via WDA (PORTRAIT, LANDSCAPE, LANDSCAPE_LEFT, LANDSCAPE_RIGHT)."
  )

  @Argument(help: "Target orientation: PORTRAIT, LANDSCAPE, LANDSCAPE_LEFT, LANDSCAPE_RIGHT.")
  var orientation: String

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    let useJSON = shouldOutputJSON(flag: json)
    let env = Environment.live
    let result = await SimTools.executeSetOrientation(orientation: orientation, env: env)

    if useJSON {
      print(try WorkflowJSONRenderer.renderJSON(result))
    } else {
      print(SimRenderer.render(result))
    }

    if !result.succeeded {
      throw ExitCode.failure
    }
  }
}

// MARK: - Video Recording

struct SimRecordStart: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "record-start",
    abstract: "Start recording simulator screen to a video file."
  )

  @Option(help: "Simulator name or UDID. Auto-detected from booted simulator if omitted.")
  var simulator: String?

  @Option(help: "Output file path. Defaults to /tmp/xcforge-recording-<timestamp>.mov.")
  var path: String?

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    let useJSON = shouldOutputJSON(flag: json)
    let env = Environment.live
    let result = await SimTools.executeRecordVideoStart(simulator: simulator, path: path, env: env)

    if useJSON {
      print(try WorkflowJSONRenderer.renderJSON(result))
    } else {
      print(SimRenderer.render(result))
    }

    if !result.succeeded {
      throw ExitCode.failure
    }
  }
}

struct SimRecordStop: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "record-stop",
    abstract: "Stop an active video recording and return the file path."
  )

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    let useJSON = shouldOutputJSON(flag: json)
    let result = await SimTools.executeRecordVideoStop()

    if useJSON {
      print(try WorkflowJSONRenderer.renderJSON(result))
    } else {
      print(SimRenderer.render(result))
    }

    if !result.succeeded {
      throw ExitCode.failure
    }
  }
}

// MARK: - Simulator Location

struct SimLocation: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "location",
    abstract: "Set simulated GPS location on a simulator."
  )

  @Argument(help: "Latitude coordinate (e.g. 37.7749).")
  var latitude: Double

  @Argument(help: "Longitude coordinate (e.g. -122.4194).")
  var longitude: Double

  @Option(help: "Simulator name or UDID. Auto-detected from booted simulator if omitted.")
  var simulator: String?

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    let useJSON = shouldOutputJSON(flag: json)
    let env = Environment.live
    let result = await SimTools.executeSetSimLocation(
      simulator: simulator, latitude: latitude, longitude: longitude, env: env)

    if useJSON {
      print(try WorkflowJSONRenderer.renderJSON(result))
    } else {
      print(SimRenderer.render(result))
    }

    if !result.succeeded {
      throw ExitCode.failure
    }
  }
}

struct SimLocationReset: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "location-reset",
    abstract: "Reset simulator location to default."
  )

  @Option(help: "Simulator name or UDID. Auto-detected from booted simulator if omitted.")
  var simulator: String?

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    let useJSON = shouldOutputJSON(flag: json)
    let env = Environment.live
    let result = await SimTools.executeResetSimLocation(simulator: simulator, env: env)

    if useJSON {
      print(try WorkflowJSONRenderer.renderJSON(result))
    } else {
      print(SimRenderer.render(result))
    }

    if !result.succeeded {
      throw ExitCode.failure
    }
  }
}

// MARK: - Simulator Appearance

struct SimAppearance: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "appearance",
    abstract: "Set simulator appearance to light or dark mode."
  )

  @Argument(help: "Appearance mode: light or dark.")
  var appearance: String

  @Option(help: "Simulator name or UDID. Auto-detected from booted simulator if omitted.")
  var simulator: String?

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    let useJSON = shouldOutputJSON(flag: json)
    let env = Environment.live
    let result = await SimTools.executeSetSimAppearance(
      simulator: simulator, appearance: appearance, env: env)

    if useJSON {
      print(try WorkflowJSONRenderer.renderJSON(result))
    } else {
      print(SimRenderer.render(result))
    }

    if !result.succeeded {
      throw ExitCode.failure
    }
  }
}

// MARK: - Status Bar

struct SimStatusBar: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "statusbar",
    abstract: "Override simulator status bar values for clean screenshots."
  )

  @Option(help: "Simulator name or UDID. Auto-detected from booted simulator if omitted.")
  var simulator: String?

  @Option(help: "Time string to display (e.g. '9:41').")
  var time: String?

  @Option(help: "Battery level percentage (0-100).")
  var batteryLevel: Int?

  @Option(help: "Battery state: charging, charged, discharging.")
  var batteryState: String?

  @Option(help: "Cellular signal bars (0-4).")
  var cellularBars: Int?

  @Option(help: "WiFi signal bars (0-3).")
  var wifiBars: Int?

  @Option(help: "Carrier name to display.")
  var operatorName: String?

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    let useJSON = shouldOutputJSON(flag: json)
    let env = Environment.live
    let result = await SimTools.executeSimStatusBar(
      simulator: simulator, time: time, batteryLevel: batteryLevel,
      batteryState: batteryState, cellularBars: cellularBars,
      wifiBars: wifiBars, operatorName: operatorName, env: env
    )

    if useJSON {
      print(try WorkflowJSONRenderer.renderJSON(result))
    } else {
      print(SimRenderer.render(result))
    }

    if !result.succeeded {
      throw ExitCode.failure
    }
  }
}

struct SimStatusBarClear: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "statusbar-clear",
    abstract: "Clear all status bar overrides and restore defaults."
  )

  @Option(help: "Simulator name or UDID. Auto-detected from booted simulator if omitted.")
  var simulator: String?

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    let useJSON = shouldOutputJSON(flag: json)
    let env = Environment.live
    let result = await SimTools.executeSimStatusBarClear(simulator: simulator, env: env)

    if useJSON {
      print(try WorkflowJSONRenderer.renderJSON(result))
    } else {
      print(SimRenderer.render(result))
    }

    if !result.succeeded {
      throw ExitCode.failure
    }
  }
}

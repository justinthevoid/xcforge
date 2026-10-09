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
      SimInfo.self, SimOpenURL.self, SimContentSize.self, SimLocale.self, SimContainer.self, SimPush.self,
      SimPrivacy.self,
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

  @Option(name: .customLong("arg"), help: "Launch argument for the app (repeatable).")
  var args: [String] = []

  @Option(help: "Environment variable for the app, KEY=VALUE (repeatable).")
  var env: [String] = []

  @Option(help: "URL or deep link to open once the app is running.")
  var url: String?

  @Flag(inversion: .prefixedNo, help: "Terminate a running copy first. Default: on.")
  var terminate = true

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    let useJSON = shouldOutputJSON(flag: json)
    let result = await SimTools.executeLaunchApp(
      simulator: simulator, bundleId: bundleId, args: args, environment: env, url: url,
      terminateFirst: terminate, env: Environment.live)

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

// MARK: - Sim Info

struct SimInfo: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "info",
    abstract: """
      Show live screen geometry for a booted simulator: \
      pixel size, point size, and scale (derived from SIMULATOR_MAINSCREEN_*).
      """
  )

  @Option(help: "Simulator name or UDID. Auto-detected from booted simulator if omitted.")
  var simulator: String?

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    let useJSON = shouldOutputJSON(flag: json)
    let env = Environment.live

    let outcome = await SimTools.executeSimInfo(simulator: simulator, env: env)
    switch outcome {
    case .success(let info):
      if useJSON {
        print(try WorkflowJSONRenderer.renderJSON(info))
      } else {
        let pxW = Int(info.pixelSize.width)
        let pxH = Int(info.pixelSize.height)
        let ptW = Int(info.pointSize.width)
        let ptH = Int(info.pointSize.height)
        print("UDID: \(info.udid)")
        print("Scale: \(info.scale)x")
        print("Pixel size: \(pxW)×\(pxH)")
        print("Point size: \(ptW)×\(ptH)")
      }
    case .failure(let error):
      let message = "sim info failed: \(error)"
      if useJSON {
        struct ErrEnvelope: Codable {
          let error: String
        }
        print(try WorkflowJSONRenderer.renderJSON(ErrEnvelope(error: message)))
      } else {
        print(message)
      }
      throw ExitCode.failure
    }
  }
}

struct SimOpenURL: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "openurl",
    abstract: "Open a URL or deep link on a simulator."
  )

  @Argument(help: "URL or deep link to open.")
  var url: String

  @Option(help: "Simulator name or UDID. Auto-detected from booted simulator if omitted.")
  var simulator: String?

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    let result = await SimTools.executeOpenURL(simulator: simulator, url: url, env: Environment.live)
    if shouldOutputJSON(flag: json) {
      print(try WorkflowJSONRenderer.renderJSON(result))
    } else {
      print(SimRenderer.render(result))
    }
    if !result.succeeded {
      throw ExitCode.failure
    }
  }
}

// MARK: - Setup

/// Print a SimResult as text or JSON and exit non-zero when it failed.
private func emit(_ result: SimTools.SimResult, json: Bool) throws {
  if shouldOutputJSON(flag: json) {
    print(try WorkflowJSONRenderer.renderJSON(result))
  } else {
    print(SimRenderer.render(result))
  }
  if !result.succeeded { throw ExitCode.failure }
}

struct SimContentSize: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "content-size",
    abstract: "Read or set the Dynamic Type text size. Prints the previous size."
  )

  @Argument(help: "Size to set, e.g. large or accessibility-large. Omit to read the current one.")
  var size: String?

  @Option(help: "Simulator name or UDID. Auto-detected from booted simulator if omitted.")
  var simulator: String?

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    let result = await SimTools.executeContentSize(simulator: simulator, size: size, env: .live)
    try emit(result, json: json)
  }
}

struct SimLocale: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "locale",
    abstract: "Read or set the simulator's locale and language. Apps pick it up on their next launch."
  )

  @Argument(help: "Locale such as fr_FR. Omit to read the current one.")
  var locale: String?

  @Option(help: "Preferred language such as fr or pt-BR. Default: the locale's language.")
  var language: String?

  @Option(help: "Simulator name or UDID. Auto-detected from booted simulator if omitted.")
  var simulator: String?

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    let result = await SimTools.executeLocale(simulator: simulator, locale: locale, language: language, env: .live)
    try emit(result, json: json)
  }
}

struct SimContainer: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "container",
    abstract: "Print the path of an app's bundle, data or app group container."
  )

  @Option(name: .customLong("bundle-id"), help: "App bundle ID. Default: the last built app.")
  var bundleId: String?

  @Option(help: "app, data, groups, or an app group identifier. Default: data")
  var container: String?

  @Option(help: "Simulator name or UDID. Auto-detected from booted simulator if omitted.")
  var simulator: String?

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    let result = await SimTools.executeAppContainer(
      simulator: simulator, bundleId: bundleId, container: container, env: .live)
    try emit(result, json: json)
  }
}

struct SimPush: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "push",
    abstract: "Deliver a push notification to an app."
  )

  @Argument(help: "APNs payload JSON, a path to a .json/.apns file, or plain alert text.")
  var payload: String

  @Option(name: .customLong("bundle-id"), help: "App bundle ID. Default: the last built app.")
  var bundleId: String?

  @Option(help: "Simulator name or UDID. Auto-detected from booted simulator if omitted.")
  var simulator: String?

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    var body = payload
    if FileManager.default.fileExists(atPath: payload),
      let contents = FileManager.default.contents(atPath: payload)
    {
      body = String(decoding: contents, as: UTF8.self)
    }
    let result = await SimTools.executePush(simulator: simulator, bundleId: bundleId, payload: body, env: .live)
    try emit(result, json: json)
  }
}

struct SimPrivacy: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "privacy",
    abstract: "Grant, revoke or reset a privacy permission so permission alerts don't block a flow."
  )

  @Argument(help: "grant, revoke or reset.")
  var action: String

  @Argument(help: "Service: all, photos, photos-add, location, location-always, contacts, microphone, and so on.")
  var service: String

  @Option(name: .customLong("bundle-id"), help: "App. Default: the last built app; reset without one resets all.")
  var bundleId: String?

  @Option(help: "Simulator name or UDID. Auto-detected from booted simulator if omitted.")
  var simulator: String?

  @Flag(help: "Emit the result as machine-readable JSON.")
  var json = false

  mutating func run() async throws {
    let result = await SimTools.executePrivacy(
      simulator: simulator, action: action, service: service, bundleId: bundleId, env: .live)
    try emit(result, json: json)
  }
}

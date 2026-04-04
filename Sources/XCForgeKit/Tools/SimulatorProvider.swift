import Foundation
import MCP

public enum SimTools {
  struct StructuredAppLaunch: Sendable, Equatable {
    let simulatorUDID: String
    let bundleId: String
    let wasRunning: Bool
    let stdout: String
    let stderr: String
    let exitCode: Int32
    let timedOut: Bool

    var succeeded: Bool {
      exitCode == 0 && !timedOut
    }
  }

  struct RuntimeContinuityReset: Sendable, Equatable {
    let simulatorUDID: String
    let bundleId: String
    let wasRunning: Bool
    let sessionCleared: Bool
  }

  public static let tools: [Tool] = [
    Tool(
      name: "list_sims",
      description: "List available iOS simulators with their state and UDID.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "filter": .object([
            "type": .string("string"),
            "description": .string("Optional filter string, e.g. 'iPhone' or 'Booted'"),
          ])
        ]),
      ])
    ),
    Tool(
      name: "boot_sim",
      description: "Boot an iOS simulator by name or UDID.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "simulator": .object([
            "type": .string("string"), "description": .string("Simulator name or UDID"),
          ])
        ]),
        "required": .array([.string("simulator")]),
      ])
    ),
    Tool(
      name: "shutdown_sim",
      description: "Shutdown a running simulator.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "simulator": .object([
            "type": .string("string"),
            "description": .string("Simulator name or UDID. Use 'all' to shutdown all."),
          ])
        ]),
        "required": .array([.string("simulator")]),
      ])
    ),
    Tool(
      name: "install_app",
      description:
        "Install an app bundle on a booted simulator. App path is auto-detected from last build if omitted.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "simulator": .object([
            "type": .string("string"),
            "description": .string(
              "Simulator name or UDID. Auto-detected from booted simulator if omitted."),
          ]),
          "app_path": .object([
            "type": .string("string"),
            "description": .string(
              "Path to .app bundle. Auto-detected from last build_sim if omitted."),
          ]),
        ]),
      ])
    ),
    Tool(
      name: "launch_app",
      description:
        "Launch an app on a booted simulator. Bundle ID is auto-detected from last build if omitted.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "simulator": .object([
            "type": .string("string"),
            "description": .string(
              "Simulator name or UDID. Auto-detected from booted simulator if omitted."),
          ]),
          "bundle_id": .object([
            "type": .string("string"),
            "description": .string(
              "App bundle identifier. Auto-detected from last build_sim if omitted."),
          ]),
        ]),
      ])
    ),
    Tool(
      name: "terminate_app",
      description:
        "Terminate a running app on a simulator. Bundle ID is auto-detected from last build if omitted.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "simulator": .object([
            "type": .string("string"),
            "description": .string(
              "Simulator name or UDID. Auto-detected from booted simulator if omitted."),
          ]),
          "bundle_id": .object([
            "type": .string("string"),
            "description": .string(
              "App bundle identifier. Auto-detected from last build_sim if omitted."),
          ]),
        ]),
      ])
    ),
    Tool(
      name: "clone_sim",
      description:
        "Clone a simulator to create a snapshot of its current state (apps, data, settings). The clone is a new simulator that can be booted independently.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "simulator": .object([
            "type": .string("string"), "description": .string("Source simulator UDID or name"),
          ]),
          "name": .object([
            "type": .string("string"), "description": .string("Name for the cloned simulator"),
          ]),
        ]),
        "required": .array([.string("simulator"), .string("name")]),
      ])
    ),
    Tool(
      name: "erase_sim",
      description:
        "Erase a simulator — resets to factory state. Removes all apps, data, and settings. Simulator must be shut down first.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "simulator": .object([
            "type": .string("string"),
            "description": .string("Simulator UDID, name, or 'all' to erase all simulators"),
          ])
        ]),
        "required": .array([.string("simulator")]),
      ])
    ),
    Tool(
      name: "delete_sim",
      description:
        "Permanently delete a simulator. Use to clean up cloned snapshots that are no longer needed.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "simulator": .object([
            "type": .string("string"), "description": .string("Simulator UDID or name to delete"),
          ])
        ]),
        "required": .array([.string("simulator")]),
      ])
    ),
    Tool(
      name: "record_video_start",
      description:
        "Start recording simulator screen to a video file. Returns the output file path. Use record_video_stop to finish.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "simulator": .object([
            "type": .string("string"),
            "description": .string(
              "Simulator name or UDID. Auto-detected from booted simulator if omitted."),
          ]),
          "path": .object([
            "type": .string("string"),
            "description": .string(
              "Output file path. Defaults to /tmp/xcforge-recording-<timestamp>.mov if omitted."),
          ]),
        ]),
      ])
    ),
    Tool(
      name: "record_video_stop",
      description: "Stop an active video recording and return the file path.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([:]),
      ])
    ),
    Tool(
      name: "set_sim_location",
      description: "Set simulated GPS location on a simulator.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "simulator": .object([
            "type": .string("string"),
            "description": .string(
              "Simulator name or UDID. Auto-detected from booted simulator if omitted."),
          ]),
          "latitude": .object([
            "type": .string("number"), "description": .string("Latitude coordinate (e.g. 37.7749)"),
          ]),
          "longitude": .object([
            "type": .string("number"),
            "description": .string("Longitude coordinate (e.g. -122.4194)"),
          ]),
        ]),
        "required": .array([.string("latitude"), .string("longitude")]),
      ])
    ),
    Tool(
      name: "reset_sim_location",
      description: "Reset simulator location to default (removes any simulated GPS override).",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "simulator": .object([
            "type": .string("string"),
            "description": .string(
              "Simulator name or UDID. Auto-detected from booted simulator if omitted."),
          ])
        ]),
      ])
    ),
    Tool(
      name: "set_sim_appearance",
      description: "Set simulator appearance to light or dark mode.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "simulator": .object([
            "type": .string("string"),
            "description": .string(
              "Simulator name or UDID. Auto-detected from booted simulator if omitted."),
          ]),
          "appearance": .object([
            "type": .string("string"),
            "description": .string("Appearance mode: light or dark"),
            "enum": .array([.string("light"), .string("dark")]),
          ]),
        ]),
        "required": .array([.string("appearance")]),
      ])
    ),
    Tool(
      name: "sim_statusbar",
      description:
        "Override simulator status bar values (time, battery, cellular, etc.) for clean screenshots.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "simulator": .object([
            "type": .string("string"),
            "description": .string(
              "Simulator name or UDID. Auto-detected from booted simulator if omitted."),
          ]),
          "time": .object([
            "type": .string("string"),
            "description": .string("Time string to display (e.g. '9:41')"),
          ]),
          "battery_level": .object([
            "type": .string("integer"), "description": .string("Battery level percentage (0-100)"),
          ]),
          "battery_state": .object([
            "type": .string("string"),
            "description": .string("Battery state"),
            "enum": .array([.string("charging"), .string("charged"), .string("discharging")]),
          ]),
          "cellular_bars": .object([
            "type": .string("integer"), "description": .string("Cellular signal bars (0-4)"),
          ]),
          "wifi_bars": .object([
            "type": .string("integer"), "description": .string("WiFi signal bars (0-3)"),
          ]),
          "operator_name": .object([
            "type": .string("string"), "description": .string("Carrier name to display"),
          ]),
        ]),
      ])
    ),
    Tool(
      name: "sim_statusbar_clear",
      description: "Clear all status bar overrides and restore default values.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "simulator": .object([
            "type": .string("string"),
            "description": .string(
              "Simulator name or UDID. Auto-detected from booted simulator if omitted."),
          ])
        ]),
      ])
    ),
    Tool(
      name: "set_orientation",
      description: """
        Set device orientation (portrait/landscape) via WDA. \
        Uses XCUIDevice.shared.orientation — the only reliable programmatic method. \
        Returns the confirmed orientation after change.
        """,
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "orientation": .object([
            "type": .string("string"),
            "description": .string(
              "Target orientation: PORTRAIT, LANDSCAPE, LANDSCAPE_LEFT, LANDSCAPE_RIGHT"),
            "enum": .array([
              .string("PORTRAIT"), .string("LANDSCAPE"),
              .string("LANDSCAPE_LEFT"), .string("LANDSCAPE_RIGHT"),
            ]),
          ])
        ]),
        "required": .array([.string("orientation")]),
      ])
    ),
  ]

  // MARK: - Input Structs

  private struct FilterInput: Decodable {
    let filter: String?
  }

  private struct SimulatorInput: Decodable {
    let simulator: String
  }

  private struct InstallAppInput: Decodable {
    let simulator: String?
    let app_path: String?
  }

  private struct AppInput: Decodable {
    let simulator: String?
    let bundle_id: String?
  }

  private struct CloneInput: Decodable {
    let simulator: String
    let name: String
  }

  private struct OrientationInput: Decodable {
    let orientation: String
  }

  private struct RecordVideoInput: Decodable {
    let simulator: String?
    let path: String?
  }

  private struct LocationInput: Decodable {
    let simulator: String?
    let latitude: Double
    let longitude: Double
  }

  private struct OptionalSimInput: Decodable {
    let simulator: String?
  }

  private struct AppearanceInput: Decodable {
    let simulator: String?
    let appearance: String
  }

  private struct StatusBarInput: Decodable {
    let simulator: String?
    let time: String?
    let battery_level: Int?
    let battery_state: String?
    let cellular_bars: Int?
    let wifi_bars: Int?
    let operator_name: String?
  }

  // MARK: - Resolve simulator name to UDID

  private static let uuidPattern = try! NSRegularExpression(
    pattern: "^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$",
    options: .caseInsensitive
  )

  public static func resolveSimulator(_ nameOrUDID: String, env: Environment = .live) async throws
    -> String
  {
    if uuidPattern.firstMatch(
      in: nameOrUDID, range: NSRange(nameOrUDID.startIndex..., in: nameOrUDID)) != nil
    {
      return nameOrUDID
    }
    if nameOrUDID == "booted" { return "booted" }

    let result = try await env.shell.xcrun(timeout: 15, "simctl", "list", "devices", "-j")
    guard let data = result.stdout.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let deviceGroups = json["devices"] as? [String: [[String: Any]]]
    else {
      throw NSError(
        domain: "SimTools", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Failed to parse simulator list"])
    }

    // Exact match only — prefix/substring matching causes false positives on destructive ops
    // (e.g. "iPhone 16 Pro" would match "iPhone 16 Pro Max" with hasPrefix)
    let needle = nameOrUDID.lowercased()
    for (_, devices) in deviceGroups {
      for device in devices {
        guard let name = device["name"] as? String,
          let udid = device["udid"] as? String
        else { continue }
        if name.lowercased() == needle { return udid }
      }
    }
    throw NSError(
      domain: "SimTools", code: 2,
      userInfo: [
        NSLocalizedDescriptionKey: "Simulator '\(nameOrUDID)' not found. Use exact name or UDID."
      ])
  }

  // MARK: - Typed Execute Methods

  public struct SimResult: Codable, Sendable {
    public let succeeded: Bool
    public let message: String
  }

  public static func executeListSims(filter: String?, env: Environment) async -> SimResult {
    do {
      let result = try await env.shell.xcrun(timeout: 15, "simctl", "list", "devices", "-j")
      guard let data = result.stdout.data(using: .utf8),
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let deviceGroups = json["devices"] as? [String: [[String: Any]]]
      else {
        return SimResult(succeeded: false, message: "Failed to parse simulator list")
      }

      var lines: [String] = []
      for (runtime, devices) in deviceGroups.sorted(by: { $0.key > $1.key }) {
        let runtimeName = runtime.split(separator: ".").last.map(String.init) ?? runtime
        for device in devices {
          let name = device["name"] as? String ?? "?"
          let state = device["state"] as? String ?? "?"
          let udid = device["udid"] as? String ?? "?"

          if let f = filter {
            let combined = "\(name) \(state) \(runtimeName)"
            if !combined.lowercased().contains(f.lowercased()) { continue }
          }

          let marker = state == "Booted" ? "[ON]" : "[--]"
          lines.append("\(marker) \(name) (\(runtimeName)) — \(state)\n   UDID: \(udid)")
        }
      }

      let message =
        lines.isEmpty
        ? "No simulators found" + (filter.map { " matching '\($0)'" } ?? "")
        : lines.joined(separator: "\n")
      return SimResult(succeeded: true, message: message)
    } catch {
      return SimResult(succeeded: false, message: "Error: \(error)")
    }
  }

  public static func executeBootSim(simulator: String, env: Environment) async -> SimResult {
    do {
      let udid = try await resolveSimulator(simulator, env: env)
      let result = try await env.shell.xcrun(timeout: 60, "simctl", "boot", udid)
      if result.succeeded || result.stderr.contains("current state: Booted") {
        return SimResult(succeeded: true, message: "Simulator booted: \(udid)")
      }
      return SimResult(succeeded: false, message: "Boot failed: \(result.stderr)")
    } catch {
      return SimResult(succeeded: false, message: "Error: \(error)")
    }
  }

  public static func executeShutdownSim(simulator: String, env: Environment) async -> SimResult {
    do {
      let target = simulator == "all" ? "all" : try await resolveSimulator(simulator, env: env)
      let result = try await env.shell.xcrun(timeout: 10, "simctl", "shutdown", target)
      return result.succeeded
        ? SimResult(succeeded: true, message: "Simulator shutdown: \(target)")
        : SimResult(succeeded: false, message: "Shutdown failed: \(result.stderr)")
    } catch {
      return SimResult(succeeded: false, message: "Error: \(error)")
    }
  }

  public static func executeInstallApp(simulator: String?, appPath: String?, env: Environment) async
    -> SimResult
  {
    guard let resolvedAppPath = await env.session.resolveAppPath(appPath) else {
      return SimResult(
        succeeded: false, message: "Missing app path — provide it or run a build first")
    }
    let sim: String
    do {
      sim = try await env.session.resolveSimulator(simulator)
    } catch {
      return SimResult(succeeded: false, message: "\(error)")
    }
    do {
      let udid = try await resolveSimulator(sim, env: env)
      let result = try await env.shell.xcrun(
        timeout: 60, "simctl", "install", udid, resolvedAppPath)

      // Invalidate WDA session — reinstalled app binary makes the old session stale.
      // Stale sessions accumulate and eventually crash WDA after multiple install cycles.
      _ = await env.wdaClient.deleteSession()

      return result.succeeded
        ? SimResult(succeeded: true, message: "App installed on \(udid)")
        : SimResult(succeeded: false, message: "Install failed: \(result.stderr)")
    } catch {
      return SimResult(succeeded: false, message: "Error: \(error)")
    }
  }

  public static func executeLaunchApp(simulator: String?, bundleId: String?, env: Environment) async
    -> SimResult
  {
    guard let resolvedBundleId = await env.session.resolveBundleId(bundleId) else {
      return SimResult(
        succeeded: false, message: "Missing bundle ID — provide it or run a build first")
    }
    let sim: String
    do {
      sim = try await env.session.resolveSimulator(simulator)
    } catch {
      return SimResult(succeeded: false, message: "\(error)")
    }
    do {
      let udid = try await resolveSimulator(sim, env: env)
      let launch = try await launchAppStructured(
        simulatorUDID: udid, bundleId: resolvedBundleId, env: env)

      if launch.succeeded {
        let note = launch.wasRunning ? " (was running, relaunched)" : ""
        return SimResult(
          succeeded: true,
          message: "Launched \(resolvedBundleId) on \(udid)\(note)\n\(launch.stdout)")
      }

      if launch.timedOut {
        return SimResult(
          succeeded: false, message: "Launch timed out after 15s. The simulator may need a restart."
        )
      }

      return SimResult(succeeded: false, message: "Launch failed: \(launch.stderr)")
    } catch {
      return SimResult(succeeded: false, message: "Error: \(error)")
    }
  }

  public static func executeTerminateApp(simulator: String?, bundleId: String?, env: Environment)
    async -> SimResult
  {
    guard let resolvedBundleId = await env.session.resolveBundleId(bundleId) else {
      return SimResult(
        succeeded: false, message: "Missing bundle ID — provide it or run a build first")
    }
    let sim: String
    do {
      sim = try await env.session.resolveSimulator(simulator)
    } catch {
      return SimResult(succeeded: false, message: "\(error)")
    }
    do {
      let udid = try await resolveSimulator(sim, env: env)
      let result = try await env.shell.xcrun(
        timeout: 10, "simctl", "terminate", udid, resolvedBundleId)

      // Invalidate WDA session — the terminated app may have been the session target.
      // Keeping a stale session causes WDA instability over multiple terminate cycles.
      _ = await env.wdaClient.deleteSession()

      return result.succeeded
        ? SimResult(succeeded: true, message: "Terminated \(resolvedBundleId)")
        : SimResult(succeeded: false, message: "Terminate failed: \(result.stderr)")
    } catch {
      return SimResult(succeeded: false, message: "Error: \(error)")
    }
  }

  public static func executeCloneSim(simulator: String, name: String, env: Environment) async
    -> SimResult
  {
    guard !name.isEmpty else {
      return SimResult(succeeded: false, message: "Missing required: simulator, name")
    }
    do {
      let udid = try await resolveSimulator(simulator, env: env)
      let result = try await env.shell.xcrun(timeout: 60, "simctl", "clone", udid, name)
      if result.succeeded {
        let cloneUDID = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return SimResult(
          succeeded: true,
          message: "Cloned simulator: \(name)\nSource: \(udid)\nClone UDID: \(cloneUDID)")
      }
      return SimResult(succeeded: false, message: "Clone failed: \(result.stderr)")
    } catch {
      return SimResult(succeeded: false, message: "Error: \(error)")
    }
  }

  public static func executeEraseSim(simulator: String, env: Environment) async -> SimResult {
    do {
      let target =
        simulator.lowercased() == "all" ? "all" : try await resolveSimulator(simulator, env: env)
      let result = try await env.shell.xcrun(timeout: 30, "simctl", "erase", target)

      if result.succeeded {
        _ = await env.wdaClient.deleteSession()
        return SimResult(succeeded: true, message: "Erased simulator: \(target)")
      }
      if result.stderr.contains("state: Booted") {
        return SimResult(
          succeeded: false, message: "Cannot erase a booted simulator. Shut it down first.")
      }
      return SimResult(succeeded: false, message: "Erase failed: \(result.stderr)")
    } catch {
      return SimResult(succeeded: false, message: "Error: \(error)")
    }
  }

  public static func executeDeleteSim(simulator: String, env: Environment) async -> SimResult {
    do {
      let udid = try await resolveSimulator(simulator, env: env)
      let result = try await env.shell.xcrun(timeout: 30, "simctl", "delete", udid)

      if result.succeeded {
        _ = await env.wdaClient.deleteSession()
        return SimResult(succeeded: true, message: "Deleted simulator: \(udid)")
      }
      return SimResult(succeeded: false, message: "Delete failed: \(result.stderr)")
    } catch {
      return SimResult(succeeded: false, message: "Error: \(error)")
    }
  }

  public static func executeSetOrientation(orientation: String, env: Environment) async -> SimResult
  {
    do {
      let result = try await env.wdaClient.setOrientation(orientation)
      return SimResult(succeeded: true, message: "Orientation set to \(result)")
    } catch {
      return SimResult(succeeded: false, message: "Orientation failed: \(error)")
    }
  }

  // MARK: - Video Recording State

  private static let videoRecording = VideoRecordingState()

  private actor VideoRecordingState {
    private var process: Process?
    private var outputPath: String?

    /// Atomic check-and-set: returns false if already recording.
    func tryStart(process: Process, path: String) -> Bool {
      guard self.process == nil else { return false }
      self.process = process
      self.outputPath = path
      return true
    }

    func stop() -> (process: Process, path: String)? {
      guard let process, let path = outputPath else { return nil }
      self.process = nil
      self.outputPath = nil
      return (process, path)
    }
  }

  // MARK: - Video Recording

  public static func executeRecordVideoStart(simulator: String?, path: String?, env: Environment)
    async -> SimResult
  {
    let sim: String
    do {
      sim = try await env.session.resolveSimulator(simulator)
    } catch {
      return SimResult(succeeded: false, message: "\(error)")
    }
    do {
      let udid = try await resolveSimulator(sim, env: env)
      let timestamp = Int(Date().timeIntervalSince1970)
      let outputPath = path ?? "/tmp/xcforge-recording-\(timestamp).mov"

      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
      process.arguments = ["simctl", "io", udid, "recordVideo", "--codec=h264", outputPath]
      process.standardOutput = FileHandle.nullDevice
      process.standardError = FileHandle.nullDevice
      try process.run()

      // Atomic check-and-set: prevents race where two concurrent callers both start recording
      let started = await videoRecording.tryStart(process: process, path: outputPath)
      guard started else {
        process.terminate()
        return SimResult(
          succeeded: false,
          message: "A recording is already in progress. Stop it first with record_video_stop.")
      }
      return SimResult(succeeded: true, message: "Recording started → \(outputPath)")
    } catch {
      return SimResult(succeeded: false, message: "Failed to start recording: \(error)")
    }
  }

  public static func executeRecordVideoStop() async -> SimResult {
    guard let recording = await videoRecording.stop() else {
      return SimResult(succeeded: false, message: "No active recording to stop.")
    }
    // Only send SIGINT if the process is still running; avoids hitting a recycled PID
    if recording.process.isRunning {
      recording.process.interrupt()  // sends SIGINT
    }
    // Wait for file finalization (up to 2s)
    recording.process.waitUntilExit()
    let exists = FileManager.default.fileExists(atPath: recording.path)
    if exists {
      return SimResult(succeeded: true, message: "Recording saved → \(recording.path)")
    }
    return SimResult(
      succeeded: false, message: "Recording stopped but file not found at \(recording.path)")
  }

  // MARK: - Simulator Location

  public static func executeSetSimLocation(
    simulator: String?, latitude: Double, longitude: Double, env: Environment
  ) async -> SimResult {
    let sim: String
    do {
      sim = try await env.session.resolveSimulator(simulator)
    } catch {
      return SimResult(succeeded: false, message: "\(error)")
    }
    do {
      let udid = try await resolveSimulator(sim, env: env)
      let result = try await env.shell.xcrun(
        timeout: 10, "simctl", "location", udid, "set", "\(latitude),\(longitude)")
      return result.succeeded
        ? SimResult(succeeded: true, message: "Location set to \(latitude), \(longitude)")
        : SimResult(succeeded: false, message: "Failed to set location: \(result.stderr)")
    } catch {
      return SimResult(succeeded: false, message: "Error: \(error)")
    }
  }

  public static func executeResetSimLocation(simulator: String?, env: Environment) async
    -> SimResult
  {
    let sim: String
    do {
      sim = try await env.session.resolveSimulator(simulator)
    } catch {
      return SimResult(succeeded: false, message: "\(error)")
    }
    do {
      let udid = try await resolveSimulator(sim, env: env)
      let result = try await env.shell.xcrun(timeout: 10, "simctl", "location", udid, "clear")
      return result.succeeded
        ? SimResult(succeeded: true, message: "Location reset to default")
        : SimResult(succeeded: false, message: "Failed to reset location: \(result.stderr)")
    } catch {
      return SimResult(succeeded: false, message: "Error: \(error)")
    }
  }

  // MARK: - Simulator Appearance

  public static func executeSetSimAppearance(
    simulator: String?, appearance: String, env: Environment
  ) async -> SimResult {
    let sim: String
    do {
      sim = try await env.session.resolveSimulator(simulator)
    } catch {
      return SimResult(succeeded: false, message: "\(error)")
    }
    do {
      let udid = try await resolveSimulator(sim, env: env)
      let result = try await env.shell.xcrun(
        timeout: 10, "simctl", "ui", udid, "appearance", appearance)
      return result.succeeded
        ? SimResult(succeeded: true, message: "Appearance set to \(appearance)")
        : SimResult(succeeded: false, message: "Failed to set appearance: \(result.stderr)")
    } catch {
      return SimResult(succeeded: false, message: "Error: \(error)")
    }
  }

  // MARK: - Status Bar

  public static func executeSimStatusBar(
    simulator: String?, time: String?, batteryLevel: Int?, batteryState: String?,
    cellularBars: Int?, wifiBars: Int?, operatorName: String?, env: Environment
  ) async -> SimResult {
    guard
      time != nil || batteryLevel != nil || batteryState != nil || cellularBars != nil
        || wifiBars != nil || operatorName != nil
    else {
      return SimResult(
        succeeded: false,
        message:
          "At least one override is required (time, battery_level, battery_state, cellular_bars, wifi_bars, or operator_name)."
      )
    }
    let sim: String
    do {
      sim = try await env.session.resolveSimulator(simulator)
    } catch {
      return SimResult(succeeded: false, message: "\(error)")
    }
    do {
      let udid = try await resolveSimulator(sim, env: env)
      var args = ["simctl", "status_bar", udid, "override"]
      if let time { args += ["--time", time] }
      if let level = batteryLevel { args += ["--batteryLevel", "\(level)"] }
      if let state = batteryState { args += ["--batteryState", state] }
      if let bars = cellularBars { args += ["--cellularBars", "\(bars)"] }
      if let wifi = wifiBars { args += ["--wifiBars", "\(wifi)"] }
      if let op = operatorName { args += ["--operatorName", op] }

      let result = try await env.shell.xcrun(timeout: 10, arguments: args)
      return result.succeeded
        ? SimResult(succeeded: true, message: "Status bar overrides applied")
        : SimResult(succeeded: false, message: "Failed to set status bar: \(result.stderr)")
    } catch {
      return SimResult(succeeded: false, message: "Error: \(error)")
    }
  }

  public static func executeSimStatusBarClear(simulator: String?, env: Environment) async
    -> SimResult
  {
    let sim: String
    do {
      sim = try await env.session.resolveSimulator(simulator)
    } catch {
      return SimResult(succeeded: false, message: "\(error)")
    }
    do {
      let udid = try await resolveSimulator(sim, env: env)
      let result = try await env.shell.xcrun(timeout: 10, "simctl", "status_bar", udid, "clear")
      return result.succeeded
        ? SimResult(succeeded: true, message: "Status bar overrides cleared")
        : SimResult(succeeded: false, message: "Failed to clear status bar: \(result.stderr)")
    } catch {
      return SimResult(succeeded: false, message: "Error: \(error)")
    }
  }

  // MARK: - MCP Dispatch Helpers

  private static func dispatchResult(_ result: SimResult) -> CallTool.Result {
    result.succeeded ? .ok(result.message) : .fail(result.message)
  }

  // MARK: - Internal Helpers

  static func launchAppStructured(simulatorUDID: String, bundleId: String, env: Environment)
    async throws -> StructuredAppLaunch
  {
    let wasRunning = try await terminateAppIfRunning(
      simulatorUDID: simulatorUDID, bundleId: bundleId, env: env)
    if wasRunning {
      try? await Task.sleep(nanoseconds: 500_000_000)
    }

    let result = try await env.shell.run(
      "/usr/bin/xcrun",
      arguments: ["simctl", "launch", simulatorUDID, bundleId],
      timeout: 15
    )

    return StructuredAppLaunch(
      simulatorUDID: simulatorUDID,
      bundleId: bundleId,
      wasRunning: wasRunning,
      stdout: result.stdout,
      stderr: result.stderr,
      exitCode: result.exitCode,
      timedOut: result.exitCode == -1
    )
  }

  static func resetRuntimeContinuity(
    simulatorUDID: String, bundleId: String, wdaClient: WDAClient, env: Environment
  ) async -> RuntimeContinuityReset {
    let wasRunning =
      (try? await terminateAppIfRunning(simulatorUDID: simulatorUDID, bundleId: bundleId, env: env))
      ?? false
    if wasRunning {
      try? await Task.sleep(nanoseconds: 500_000_000)
    }
    let sessionCleared = await wdaClient.deleteSession()
    return RuntimeContinuityReset(
      simulatorUDID: simulatorUDID,
      bundleId: bundleId,
      wasRunning: wasRunning,
      sessionCleared: sessionCleared
    )
  }

  static func terminateAppIfRunning(simulatorUDID: String, bundleId: String, env: Environment)
    async throws -> Bool
  {
    let termResult = try? await env.shell.run(
      "/usr/bin/xcrun",
      arguments: ["simctl", "terminate", simulatorUDID, bundleId],
      timeout: 5
    )
    return termResult?.succeeded == true
  }
}

extension SimTools: ToolProvider {
  public static func dispatch(_ name: String, _ args: [String: Value]?, env: Environment) async
    -> CallTool.Result?
  {
    switch name {
    case "list_sims":
      switch ToolInput.decode(FilterInput.self, from: args) {
      case .failure(let err): return err
      case .success(let input):
        return dispatchResult(await executeListSims(filter: input.filter, env: env))
      }
    case "boot_sim":
      switch ToolInput.decode(SimulatorInput.self, from: args) {
      case .failure(let err): return err
      case .success(let input):
        return dispatchResult(await executeBootSim(simulator: input.simulator, env: env))
      }
    case "shutdown_sim":
      switch ToolInput.decode(SimulatorInput.self, from: args) {
      case .failure(let err): return err
      case .success(let input):
        return dispatchResult(await executeShutdownSim(simulator: input.simulator, env: env))
      }
    case "install_app":
      switch ToolInput.decode(InstallAppInput.self, from: args) {
      case .failure(let err): return err
      case .success(let input):
        return dispatchResult(
          await executeInstallApp(simulator: input.simulator, appPath: input.app_path, env: env))
      }
    case "launch_app":
      switch ToolInput.decode(AppInput.self, from: args) {
      case .failure(let err): return err
      case .success(let input):
        return dispatchResult(
          await executeLaunchApp(simulator: input.simulator, bundleId: input.bundle_id, env: env))
      }
    case "terminate_app":
      switch ToolInput.decode(AppInput.self, from: args) {
      case .failure(let err): return err
      case .success(let input):
        return dispatchResult(
          await executeTerminateApp(simulator: input.simulator, bundleId: input.bundle_id, env: env)
        )
      }
    case "clone_sim":
      switch ToolInput.decode(CloneInput.self, from: args) {
      case .failure(let err): return err
      case .success(let input):
        return dispatchResult(
          await executeCloneSim(simulator: input.simulator, name: input.name, env: env))
      }
    case "erase_sim":
      switch ToolInput.decode(SimulatorInput.self, from: args) {
      case .failure(let err): return err
      case .success(let input):
        return dispatchResult(await executeEraseSim(simulator: input.simulator, env: env))
      }
    case "delete_sim":
      switch ToolInput.decode(SimulatorInput.self, from: args) {
      case .failure(let err): return err
      case .success(let input):
        return dispatchResult(await executeDeleteSim(simulator: input.simulator, env: env))
      }
    case "set_orientation":
      switch ToolInput.decode(OrientationInput.self, from: args) {
      case .failure(let err): return err
      case .success(let input):
        return dispatchResult(await executeSetOrientation(orientation: input.orientation, env: env))
      }
    case "record_video_start":
      switch ToolInput.decode(RecordVideoInput.self, from: args) {
      case .failure(let err): return err
      case .success(let input):
        return dispatchResult(
          await executeRecordVideoStart(simulator: input.simulator, path: input.path, env: env))
      }
    case "record_video_stop":
      return dispatchResult(await executeRecordVideoStop())
    case "set_sim_location":
      switch ToolInput.decode(LocationInput.self, from: args) {
      case .failure(let err): return err
      case .success(let input):
        return dispatchResult(
          await executeSetSimLocation(
            simulator: input.simulator, latitude: input.latitude, longitude: input.longitude,
            env: env))
      }
    case "reset_sim_location":
      switch ToolInput.decode(OptionalSimInput.self, from: args) {
      case .failure(let err): return err
      case .success(let input):
        return dispatchResult(await executeResetSimLocation(simulator: input.simulator, env: env))
      }
    case "set_sim_appearance":
      switch ToolInput.decode(AppearanceInput.self, from: args) {
      case .failure(let err): return err
      case .success(let input):
        return dispatchResult(
          await executeSetSimAppearance(
            simulator: input.simulator, appearance: input.appearance, env: env))
      }
    case "sim_statusbar":
      switch ToolInput.decode(StatusBarInput.self, from: args) {
      case .failure(let err): return err
      case .success(let input):
        return dispatchResult(
          await executeSimStatusBar(
            simulator: input.simulator, time: input.time, batteryLevel: input.battery_level,
            batteryState: input.battery_state, cellularBars: input.cellular_bars,
            wifiBars: input.wifi_bars, operatorName: input.operator_name, env: env))
      }
    case "sim_statusbar_clear":
      switch ToolInput.decode(OptionalSimInput.self, from: args) {
      case .failure(let err): return err
      case .success(let input):
        return dispatchResult(await executeSimStatusBarClear(simulator: input.simulator, env: env))
      }
    default: return nil
    }
  }
}

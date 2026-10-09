import Foundation

/// The app that shows simulator windows. Xcode 26 and earlier ship Simulator.app; Xcode 27
/// replaces it with Device Hub (`DeviceHub.app`, bundle id `com.apple.dt.Devices`), and
/// `open -a Simulator` no longer works there.
public enum SimulatorApp {
  public static let simulatorBundleID = "com.apple.iphonesimulator"
  public static let deviceHubBundleID = "com.apple.dt.Devices"

  /// Bundle ids whose windows show simulator screens.
  public static let bundleIDs: Set<String> = [simulatorBundleID, deviceHubBundleID]

  /// Process names for System Events scripting, in the order they are tried.
  public static let processNames = ["Simulator", "Device Hub", "DeviceHub"]

  public static func isSimulatorApp(bundleID: String?) -> Bool {
    guard let bundleID else { return false }
    return bundleIDs.contains(bundleID)
  }

  /// Candidate app paths inside the selected Xcode, newest layout first.
  /// `developerDir` is `xcode-select -p`, e.g. `/Applications/Xcode.app/Contents/Developer`.
  static func candidatePaths(developerDir: String) -> [String] {
    let contents = (developerDir as NSString).deletingLastPathComponent
    return [
      "\(contents)/Applications/DeviceHub.app",
      "\(developerDir)/Applications/DeviceHub.app",
      "\(developerDir)/Applications/Simulator.app",
    ]
  }

  /// Path of the simulator UI app for the selected Xcode, or nil when none is found.
  static func installedPath(
    developerDir: String, exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
  ) -> String? {
    candidatePaths(developerDir: developerDir).first(where: exists)
  }

  /// Bring up the simulator UI of the selected Xcode. Best-effort: simulators run headless
  /// without it, so failure is logged and ignored.
  public static func open(shell: ShellExecutor) async {
    var developerDir = "/Applications/Xcode.app/Contents/Developer"
    if let selected = try? await shell.run("/usr/bin/xcode-select", arguments: ["-p"], timeout: 5),
      selected.succeeded, !selected.stdout.isEmpty
    {
      developerDir = selected.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if let path = installedPath(developerDir: developerDir) {
      if let result = try? await shell.run("/usr/bin/open", arguments: ["-g", path], timeout: 10),
        result.succeeded
      {
        return
      }
    }
    for bundleID in [simulatorBundleID, deviceHubBundleID] {
      if let result = try? await shell.run(
        "/usr/bin/open", arguments: ["-g", "-b", bundleID], timeout: 10),
        result.succeeded
      {
        return
      }
    }
    Log.warn("Could not open Simulator or Device Hub; simulators keep running without a window")
  }
}

import ArgumentParser
import Foundation
import XCForgeKit

/// Flags shared by every command that runs xcodebuild.
struct XcodebuildOptionGroup: ParsableArguments {
  @Option(help: "Pass -derivedDataPath to xcodebuild. Default: Xcode's shared DerivedData.")
  var derivedDataPath: String?

  @Option(help: "Exact .xcresult path for the final build or test phase (replaced if it exists).")
  var resultBundlePath: String?

  @Option(
    name: .customLong("xcodebuild-arg"), parsing: .unconditionalSingleValue,
    help: ArgumentHelp(
      "Extra xcodebuild argument inserted before the action (repeatable), e.g. --xcodebuild-arg=-jobs.",
      valueName: "ARG"))
  var xcodebuildArgs: [String] = []

  @Option(
    name: .customLong("lock"),
    help:
      "Hold this lock file while xcodebuild runs (same flock as lockf(1)); waiters queue first-come, first-served. Also XCFORGE_BUILD_LOCK."
  )
  var lockPath: String?

  @Option(name: .customLong("lock-wait"), help: "Seconds to wait for --lock before giving up. Default: 3600.")
  var lockWait: Int?

  @Option(help: "Refuse to build below this much free disk (GB). Default: warn only.")
  var minFreeGb: Double?

  @Option(help: "Kill xcodebuild after this many seconds with no output. Default: 600. 0 disables.")
  var idleTimeout: Int?

  @Flag(
    inversion: .prefixedNo,
    help: "Keep building after the first error so one run reports every error. Default: on.")
  var continueAfterErrors: Bool?

  var options: XcodebuildOptions {
    XcodebuildOptions(
      derivedDataPath: derivedDataPath.map { ($0 as NSString).expandingTildeInPath },
      resultBundlePath: resultBundlePath.map { ($0 as NSString).expandingTildeInPath },
      extraArgs: xcodebuildArgs,
      lockPath: lockPath.map { ($0 as NSString).expandingTildeInPath },
      lockWaitSeconds: lockWait.map { TimeInterval($0) },
      minFreeGB: minFreeGb,
      idleTimeoutSeconds: idleTimeout.map { TimeInterval($0) },
      continueAfterErrors: continueAfterErrors
    )
  }

  /// Run `body` with these options applied to every xcodebuild call it makes.
  func scoped(_ body: () async throws -> Void) async throws {
    try await XcodebuildOptions.$current.withValue(options) {
      try await body()
    }
  }
}

import Foundation

/// A throwaway simulator for one run, so sessions sharing a Mac never fight over one device.
///
/// `create(from:)` makes a new simulator with the same device type and runtime as the source
/// (cloning needs the source shut down, which another session may not allow), boots it and
/// waits for boot to finish. `destroy` shuts it down and deletes it.
public enum IsolatedSimulator {
  public struct Clone: Sendable, Equatable {
    public let udid: String
    public let name: String
  }

  public struct IsolatedSimulatorError: Error, CustomStringConvertible {
    public let description: String
  }

  /// Find the device type and runtime of `source` (a UDID or a name) in `simctl list` JSON.
  static func deviceSpec(source: String, listJSON: String) -> (deviceType: String, runtime: String)? {
    guard let data = listJSON.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let devices = json["devices"] as? [String: Any]
    else { return nil }
    var nameMatch: (deviceType: String, runtime: String)?
    for runtime in devices.keys.sorted(by: >) {
      guard let list = devices[runtime] as? [[String: Any]] else { continue }
      for device in list {
        guard let type = device["deviceTypeIdentifier"] as? String else { continue }
        if (device["udid"] as? String) == source { return (type, runtime) }
        if nameMatch == nil, (device["name"] as? String) == source,
          (device["isAvailable"] as? Bool) ?? true
        {
          nameMatch = (type, runtime)
        }
      }
    }
    return nameMatch
  }

  /// Create and boot a fresh simulator matching `source`.
  public static func create(from source: String, env: Environment) async throws -> Clone {
    let list = try await env.shell.run(
      "/usr/bin/xcrun", arguments: ["simctl", "list", "devices", "--json"], timeout: 30)
    guard let spec = deviceSpec(source: source, listJSON: list.stdout) else {
      throw IsolatedSimulatorError(
        description: "Can't find simulator '\(source)' to copy for an isolated run.")
    }
    let name = "xcforge-isolated-\(UUID().uuidString.prefix(8).lowercased())"
    let created = try await env.shell.run(
      "/usr/bin/xcrun", arguments: ["simctl", "create", name, spec.deviceType, spec.runtime],
      timeout: 60)
    let udid = created.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    guard created.succeeded, !udid.isEmpty else {
      throw IsolatedSimulatorError(
        description: "simctl create failed: \(created.stderr.isEmpty ? created.stdout : created.stderr)")
    }
    let clone = Clone(udid: udid, name: name)
    let booted = try await env.shell.run(
      "/usr/bin/xcrun", arguments: ["simctl", "bootstatus", udid, "-b"], timeout: 300)
    guard booted.succeeded else {
      await destroy(clone, env: env)
      throw IsolatedSimulatorError(
        description: "Isolated simulator \(name) failed to boot: \(booted.stderr)")
    }
    Log.warn("Isolated simulator \(name) (\(udid)) booted for this run")
    return clone
  }

  /// Shut down and delete an isolated simulator. Best-effort.
  public static func destroy(_ clone: Clone, env: Environment) async {
    _ = try? await env.shell.run(
      "/usr/bin/xcrun", arguments: ["simctl", "shutdown", clone.udid], timeout: 30)
    _ = try? await env.shell.run(
      "/usr/bin/xcrun", arguments: ["simctl", "delete", clone.udid], timeout: 30)
  }

  /// Run `body` against a fresh simulator copied from `source`, deleting it afterwards.
  public static func with<R>(
    source: String, env: Environment, _ body: (String) async throws -> R
  ) async throws -> R {
    let clone = try await create(from: source, env: env)
    do {
      let result = try await body(clone.udid)
      await destroy(clone, env: env)
      return result
    } catch {
      await destroy(clone, env: env)
      throw error
    }
  }
}

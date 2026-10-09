import Foundation
import MCP

/// Simulator setup an agent needs before a run: text size, language, permissions, push, and
/// where the app's files are. Each setter reports the value it replaced so it can be put back.
extension SimTools {
  public static let contentSizes = [
    "extra-small", "small", "medium", "large", "extra-large", "extra-extra-large", "extra-extra-extra-large",
    "accessibility-medium", "accessibility-large", "accessibility-extra-large",
    "accessibility-extra-extra-large", "accessibility-extra-extra-extra-large", "increment", "decrement",
  ]

  public static let privacyServices = [
    "all", "calendar", "contacts-limited", "contacts", "location", "location-always", "photos-add", "photos",
    "media-library", "microphone", "motion", "reminders", "siri",
  ]

  static let setupTools: [Tool] = [
    Tool(
      name: "sim_content_size",
      description:
        "Read or set the simulator's Dynamic Type text size. Returns the previous size so it can be restored.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "simulator": simulatorProperty,
          "size": .object([
            "type": .string("string"),
            "description": .string("Text size to set. Omit to read the current one."),
            "enum": .array(contentSizes.map { .string($0) }),
          ]),
        ]),
      ])
    ),
    Tool(
      name: "sim_locale",
      description:
        "Read or set the simulator's locale and language. Returns the previous values. Apps pick up a change on their next launch.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "simulator": simulatorProperty,
          "locale": .object([
            "type": .string("string"),
            "description": .string("Locale such as fr_FR or ar_SA. Omit to read the current one."),
          ]),
          "language": .object([
            "type": .string("string"),
            "description": .string("Preferred language such as fr or pt-BR. Default: the locale's language."),
          ]),
        ]),
      ])
    ),
    Tool(
      name: "app_container",
      description: "Path of an installed app's bundle, data or app group container on the simulator.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "simulator": simulatorProperty,
          "bundle_id": bundleIdProperty,
          "container": .object([
            "type": .string("string"),
            "description": .string("app, data, groups, or an app group identifier. Default: data"),
          ]),
        ]),
      ])
    ),
    Tool(
      name: "sim_push",
      description: "Deliver a push notification payload to an app on the simulator.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "simulator": simulatorProperty,
          "bundle_id": bundleIdProperty,
          "payload": .object([
            "type": .string("string"),
            "description": .string(
              "APNs payload as JSON, e.g. {\"aps\":{\"alert\":\"Hi\"}}. A bare alert text is wrapped for you."),
          ]),
        ]),
        "required": .array([.string("payload")]),
      ])
    ),
    Tool(
      name: "sim_privacy",
      description:
        "Grant, revoke or reset a privacy permission (photos, location, contacts, microphone...) so permission alerts don't block a flow. Changing a permission may terminate the app.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "simulator": simulatorProperty,
          "action": .object([
            "type": .string("string"),
            "enum": .array([.string("grant"), .string("revoke"), .string("reset")]),
          ]),
          "service": .object([
            "type": .string("string"),
            "enum": .array(privacyServices.map { .string($0) }),
          ]),
          "bundle_id": .object([
            "type": .string("string"),
            "description": .string(
              "App to change. Default: the last built app. reset without an app resets every app."),
          ]),
        ]),
        "required": .array([.string("action"), .string("service")]),
      ])
    ),
  ]

  private static let simulatorProperty: Value = .object([
    "type": .string("string"),
    "description": .string("Simulator name or UDID. Auto-detected from booted simulator if omitted."),
  ])

  private static let bundleIdProperty: Value = .object([
    "type": .string("string"),
    "description": .string("App bundle ID. Default: the last built app."),
  ])

  // MARK: - Inputs

  private struct ContentSizeInput: Decodable {
    let simulator: String?
    let size: String?
  }

  private struct LocaleInput: Decodable {
    let simulator: String?
    let locale: String?
    let language: String?
  }

  private struct ContainerInput: Decodable {
    let simulator: String?
    let bundle_id: String?
    let container: String?
  }

  private struct PushInput: Decodable {
    let simulator: String?
    let bundle_id: String?
    let payload: String
  }

  private struct PrivacyInput: Decodable {
    let simulator: String?
    let action: String
    let service: String
    let bundle_id: String?
  }

  static func dispatchSetup(_ name: String, _ args: [String: Value]?, env: Environment) async -> CallTool.Result? {
    func finish(_ result: SimResult) -> CallTool.Result {
      result.succeeded ? .ok(result.message) : .fail(result.message)
    }
    switch name {
    case "sim_content_size":
      switch ToolInput.decode(ContentSizeInput.self, from: args) {
      case .failure(let err): return err
      case .success(let input):
        return finish(await executeContentSize(simulator: input.simulator, size: input.size, env: env))
      }
    case "sim_locale":
      switch ToolInput.decode(LocaleInput.self, from: args) {
      case .failure(let err): return err
      case .success(let input):
        return finish(
          await executeLocale(simulator: input.simulator, locale: input.locale, language: input.language, env: env))
      }
    case "app_container":
      switch ToolInput.decode(ContainerInput.self, from: args) {
      case .failure(let err): return err
      case .success(let input):
        return finish(
          await executeAppContainer(
            simulator: input.simulator, bundleId: input.bundle_id, container: input.container, env: env))
      }
    case "sim_push":
      switch ToolInput.decode(PushInput.self, from: args) {
      case .failure(let err): return err
      case .success(let input):
        return finish(
          await executePush(simulator: input.simulator, bundleId: input.bundle_id, payload: input.payload, env: env))
      }
    case "sim_privacy":
      switch ToolInput.decode(PrivacyInput.self, from: args) {
      case .failure(let err): return err
      case .success(let input):
        return finish(
          await executePrivacy(
            simulator: input.simulator, action: input.action, service: input.service, bundleId: input.bundle_id,
            env: env))
      }
    default: return nil
    }
  }

  // MARK: - Execute

  private static func targetUDID(_ simulator: String?, env: Environment) async throws -> String {
    try await resolveSimulator(try await env.session.resolveSimulator(simulator), env: env)
  }

  private static func trimmed(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public static func executeContentSize(simulator: String?, size: String?, env: Environment) async -> SimResult {
    if let size, !contentSizes.contains(size) {
      return SimResult(
        succeeded: false, message: "Unknown size \(size). Use one of: \(contentSizes.joined(separator: ", "))")
    }
    do {
      let udid = try await targetUDID(simulator, env: env)
      let current = try await env.shell.xcrun(timeout: 10, "simctl", "ui", udid, "content_size")
      let previous = current.succeeded ? trimmed(current.stdout) : "unknown"
      guard let size else {
        return current.succeeded
          ? SimResult(succeeded: true, message: "Content size: \(previous)")
          : SimResult(succeeded: false, message: "Reading the content size failed: \(trimmed(current.stderr))")
      }
      let result = try await env.shell.xcrun(timeout: 10, "simctl", "ui", udid, "content_size", size)
      return result.succeeded
        ? SimResult(succeeded: true, message: "Content size set to \(size) (was \(previous))")
        : SimResult(succeeded: false, message: "Setting the content size failed: \(trimmed(result.stderr))")
    } catch {
      return SimResult(succeeded: false, message: "\(error)")
    }
  }

  /// The language a locale implies: `pt_BR` → `pt-BR`, `fr_FR` → `fr`.
  public static func language(forLocale locale: String) -> String {
    let parts = locale.split(whereSeparator: { $0 == "_" || $0 == "-" }).map(String.init)
    guard let code = parts.first else { return locale }
    // Languages whose regional variants differ in writing keep the region.
    let keepsRegion: Set<String> = ["pt", "zh", "en"]
    if keepsRegion.contains(code), parts.count > 1 { return "\(code)-\(parts[1])" }
    return code
  }

  public static func executeLocale(simulator: String?, locale: String?, language: String?, env: Environment) async
    -> SimResult
  {
    do {
      let udid = try await targetUDID(simulator, env: env)
      func read(_ key: String) async -> String {
        let result = try? await env.shell.xcrun(
          timeout: 10, "simctl", "spawn", udid, "defaults", "read", ".GlobalPreferences", key)
        guard let result, result.succeeded else { return "unset" }
        // `defaults read` prints arrays across lines; keep them on one.
        let words = trimmed(result.stdout).components(separatedBy: .whitespacesAndNewlines)
        return words.filter { !$0.isEmpty }.joined(separator: " ")
      }
      func write(_ key: String, _ type: String, _ value: String) async throws -> ShellResult {
        let arguments = ["simctl", "spawn", udid, "defaults", "write", ".GlobalPreferences", key, type, value]
        return try await env.shell.xcrun(timeout: 10, arguments: arguments)
      }
      let previousLocale = await read("AppleLocale")
      let previousLanguages = await read("AppleLanguages")
      guard let locale else {
        return SimResult(succeeded: true, message: "Locale: \(previousLocale) | Languages: \(previousLanguages)")
      }
      let lang = language ?? Self.language(forLocale: locale)
      let setLocale = try await write("AppleLocale", "-string", locale)
      let setLanguage = try await write("AppleLanguages", "-array", lang)
      guard setLocale.succeeded, setLanguage.succeeded else {
        let error = setLocale.succeeded ? setLanguage.stderr : setLocale.stderr
        return SimResult(succeeded: false, message: "Setting the locale failed: \(trimmed(error))")
      }
      return SimResult(
        succeeded: true,
        message:
          "Locale set to \(locale), language \(lang) (was \(previousLocale), \(previousLanguages)). Relaunch the app to apply it."
      )
    } catch {
      return SimResult(succeeded: false, message: "\(error)")
    }
  }

  public static func executeAppContainer(simulator: String?, bundleId: String?, container: String?, env: Environment)
    async -> SimResult
  {
    guard let bundle = await env.session.resolveBundleId(bundleId) else {
      return SimResult(succeeded: false, message: "Missing bundle ID — provide it or run a build first")
    }
    do {
      let udid = try await targetUDID(simulator, env: env)
      let kind = container ?? "data"
      let result = try await env.shell.xcrun(timeout: 15, "simctl", "get_app_container", udid, bundle, kind)
      return result.succeeded
        ? SimResult(succeeded: true, message: trimmed(result.stdout))
        : SimResult(succeeded: false, message: "No \(kind) container for \(bundle): \(trimmed(result.stderr))")
    } catch {
      return SimResult(succeeded: false, message: "\(error)")
    }
  }

  /// A payload as APNs JSON: JSON objects pass through, anything else becomes the alert text.
  public static func pushPayload(_ payload: String) -> Data? {
    let text = trimmed(payload)
    if text.hasPrefix("{") {
      guard let data = text.data(using: .utf8),
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] != nil
      else { return nil }
      return data
    }
    return try? JSONSerialization.data(withJSONObject: ["aps": ["alert": text]])
  }

  public static func executePush(simulator: String?, bundleId: String?, payload: String, env: Environment) async
    -> SimResult
  {
    guard let bundle = await env.session.resolveBundleId(bundleId) else {
      return SimResult(succeeded: false, message: "Missing bundle ID — provide it or run a build first")
    }
    guard let data = pushPayload(payload) else {
      return SimResult(succeeded: false, message: "payload is not a JSON object")
    }
    let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("xcforge-push-\(UUID().uuidString).apns")
    defer { try? FileManager.default.removeItem(atPath: path) }
    do {
      try data.write(to: URL(fileURLWithPath: path))
      let udid = try await targetUDID(simulator, env: env)
      let result = try await env.shell.xcrun(timeout: 15, "simctl", "push", udid, bundle, path)
      return result.succeeded
        ? SimResult(succeeded: true, message: "Push delivered to \(bundle)")
        : SimResult(succeeded: false, message: "Push failed: \(trimmed(result.stderr))")
    } catch {
      return SimResult(succeeded: false, message: "\(error)")
    }
  }

  public static func executePrivacy(
    simulator: String?, action: String, service: String, bundleId: String?, env: Environment
  ) async -> SimResult {
    guard ["grant", "revoke", "reset"].contains(action) else {
      return SimResult(succeeded: false, message: "action must be grant, revoke or reset")
    }
    guard privacyServices.contains(service) else {
      return SimResult(
        succeeded: false, message: "Unknown service \(service). Use one of: \(privacyServices.joined(separator: ", "))")
    }
    // reset without an app applies to every app; grant and revoke need one.
    let bundle = await env.session.resolveBundleId(bundleId)
    if action != "reset", bundle == nil {
      return SimResult(succeeded: false, message: "Missing bundle ID — provide it or run a build first")
    }
    do {
      let udid = try await targetUDID(simulator, env: env)
      var arguments = ["simctl", "privacy", udid, action, service]
      if let bundle, action != "reset" || bundleId != nil { arguments.append(bundle) }
      let result = try await env.shell.xcrun(timeout: 15, arguments: arguments)
      let target = arguments.count > 5 ? arguments[5] : "all apps"
      return result.succeeded
        ? SimResult(succeeded: true, message: "\(action) \(service) for \(target)")
        : SimResult(succeeded: false, message: "Privacy \(action) failed: \(trimmed(result.stderr))")
    } catch {
      return SimResult(succeeded: false, message: "\(error)")
    }
  }
}

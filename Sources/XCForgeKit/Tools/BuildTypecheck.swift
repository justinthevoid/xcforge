import Foundation
import MCP

/// Compiling one target and pointing the editor at the build: the inner-loop checks a
/// subagent runs on its own file without a full scheme build.
extension BuildTools {
  /// The schemes and targets `xcodebuild -list -json` reports for a project or workspace.
  struct ProjectListing: Sendable, Equatable {
    var schemes: [String] = []
    var targets: [String] = []

    static func parse(_ json: String) -> ProjectListing? {
      guard let data = json.data(using: .utf8),
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let info = (object["project"] ?? object["workspace"]) as? [String: Any]
      else { return nil }
      return ProjectListing(
        schemes: info["schemes"] as? [String] ?? [], targets: info["targets"] as? [String] ?? [])
    }
  }

  static func listing(_ project: String, env: Environment) async -> ProjectListing? {
    let flag = project.hasSuffix(".xcworkspace") ? "-workspace" : "-project"
    // Package resolution on a cold checkout can take most of a minute.
    let arguments = [flag, project, "-list", "-json"]
    guard let result = try? await env.shell.run(Xcodebuild.executable, arguments: arguments, timeout: 90),
      result.succeeded
    else { return nil }
    return ProjectListing.parse(result.stdout)
  }

  /// The xcodebuild arguments that build only `target`: its own scheme when there is one (so
  /// the build shares the workspace's DerivedData), else `-project <p> -target <t>`.
  /// `projects` are the `.xcodeproj` files searched for the target, with their listings.
  static func targetSelector(
    _ target: String, project: String, listing: ProjectListing, projects: [(path: String, listing: ProjectListing)]
  ) -> [String]? {
    let flag = project.hasSuffix(".xcworkspace") ? "-workspace" : "-project"
    if listing.schemes.contains(target) { return [flag, project, "-scheme", target] }
    for candidate in projects where candidate.listing.targets.contains(target) {
      return ["-project", candidate.path, "-target", target]
    }
    return nil
  }

  /// The `.xcodeproj` files a workspace sits beside (and the project itself when it is one).
  static func projectFiles(for project: String) -> [String] {
    if project.hasSuffix(".xcodeproj") { return [project] }
    let dir = (project as NSString).deletingLastPathComponent
    let entries = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
    return entries.filter { $0.hasSuffix(".xcodeproj") }.sorted().map { (dir as NSString).appendingPathComponent($0) }
  }

  public struct TypecheckSelectionError: Error, CustomStringConvertible {
    public let description: String
  }

  static func resolveTargetSelector(_ target: String, project: String, env: Environment) async throws -> [String] {
    guard let listing = await listing(project, env: env) else {
      throw TypecheckSelectionError(description: "Couldn't list schemes and targets of \(project)")
    }
    var projects: [(path: String, listing: ProjectListing)] = []
    if !listing.schemes.contains(target) {
      for path in projectFiles(for: project) {
        if path == project {
          projects.append((path, listing))
        } else if let other = await self.listing(path, env: env) {
          projects.append((path, other))
        }
      }
    }
    if let selector = targetSelector(target, project: project, listing: listing, projects: projects) {
      return selector
    }
    let targets = projects.flatMap(\.listing.targets)
    throw TypecheckSelectionError(
      description:
        "No scheme or target named \(target). Schemes: \(listing.schemes.joined(separator: ", ")). Targets: \(targets.joined(separator: ", "))"
    )
  }

  /// This scheme's DerivedData folder, from its build settings. Nil when the settings can't be read.
  static func schemeDerivedData(project: String, scheme: String, env: Environment) async -> String? {
    let flag = project.hasSuffix(".xcworkspace") ? "-workspace" : "-project"
    let args = [
      flag, project, "-scheme", scheme, "-destination", "generic/platform=iOS Simulator", "-showBuildSettings", "-json",
    ]
    guard let settings = try? await Xcodebuild.run(args, timeout: 120, env: env), settings.succeeded else {
      return nil
    }
    return derivedDataFolder(fromSettings: settings.stdout)
  }

  // MARK: - lsp setup

  public struct LSPSetupExecution: Codable, Sendable {
    public let succeeded: Bool
    public let message: String
    public let configPath: String?
    public let buildRoot: String?
  }

  /// Point `buildServer.json` (xcode-build-server's config) at the build root xcforge's builds
  /// actually use, so SourceKit-LSP finds modules instead of reporting "No such module".
  static func patchBuildServer(_ json: [String: Any], buildRoot: String) -> [String: Any] {
    var patched = json
    patched["build_root"] = buildRoot
    return patched
  }

  public static func executeLSPSetup(project: String?, scheme: String?, env: Environment) async -> LSPSetupExecution {
    func fail(_ message: String) -> LSPSetupExecution {
      LSPSetupExecution(succeeded: false, message: message, configPath: nil, buildRoot: nil)
    }
    do {
      let resolvedProject = try await env.session.resolveProject(project)
      let resolvedScheme = try await env.session.resolveScheme(scheme, project: resolvedProject)
      let which = try await env.shell.run(
        "/usr/bin/env", arguments: ["which", "xcode-build-server"], workingDirectory: nil, environment: nil,
        timeout: 10)
      let server = which.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
      guard which.succeeded, !server.isEmpty else {
        return fail("xcode-build-server is not installed: `brew install xcode-build-server`, then rerun.")
      }
      let dir = (resolvedProject as NSString).deletingLastPathComponent
      let flag = resolvedProject.hasSuffix(".xcworkspace") ? "-workspace" : "-project"
      let config = try await env.shell.run(
        server, arguments: ["config", flag, resolvedProject, "-scheme", resolvedScheme], workingDirectory: dir,
        environment: nil, timeout: 180)
      guard config.succeeded else {
        return fail("xcode-build-server config failed: \(config.stderr.isEmpty ? config.stdout : config.stderr)")
      }
      let configPath = (dir as NSString).appendingPathComponent("buildServer.json")
      // With a custom DerivedData folder, xcode-build-server would read Xcode's default one.
      var buildRoot = XcodebuildOptions.effective(cwd: dir).derivedDataPath
      if buildRoot == nil {
        buildRoot = await schemeDerivedData(project: resolvedProject, scheme: resolvedScheme, env: env)
      }
      if let buildRoot, let data = FileManager.default.contents(atPath: configPath),
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
      {
        let patched = patchBuildServer(json, buildRoot: buildRoot)
        let output = try JSONSerialization.data(withJSONObject: patched, options: [.prettyPrinted, .sortedKeys])
        try output.write(to: URL(fileURLWithPath: configPath), options: .atomic)
      }
      return LSPSetupExecution(
        succeeded: true,
        message:
          "Wrote \(configPath) for scheme \(resolvedScheme). Build the scheme once (xcforge build compile) so the index exists, then restart the language server.",
        configPath: configPath, buildRoot: buildRoot)
    } catch {
      return fail("\(error)")
    }
  }

  static func lspSetup(_ args: [String: Value]?, env: Environment) async -> CallTool.Result {
    let result = await executeLSPSetup(
      project: args?["project"]?.stringValue, scheme: args?["scheme"]?.stringValue, env: env)
    var text = result.message
    if let root = result.buildRoot { text += "\nbuild_root: \(root)" }
    return result.succeeded ? .ok(text) : .fail(text)
  }

  static let typecheckTools: [Tool] = [
    Tool(
      name: "build_typecheck",
      description: """
        Compile one target for the simulator (its own scheme when it has one, else -target), \
        reusing the workspace's DerivedData. Seconds instead of a full scheme build when checking \
        the file you just changed.
        """,
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "target": .object([
            "type": .string("string"),
            "description": .string("Target (or package product) to compile, e.g. ShutterCoachShared."),
          ]),
          "project": .object([
            "type": .string("string"),
            "description": .string("Path to .xcodeproj or .xcworkspace. Auto-detected if omitted."),
          ]),
          "simulator": .object([
            "type": .string("string"),
            "description": .string("Simulator name or UDID. Default: booted, else the newest iPhone."),
          ]),
          "configuration": .object([
            "type": .string("string"),
            "description": .string("Build configuration. Default: Debug"),
          ]),
          "fromSnapshot": .object([
            "type": .string("boolean"),
            "description": .string("Compile a snapshot of the working tree, unaffected by edits made meanwhile."),
          ]),
        ]),
        "required": .array([.string("target")]),
      ])
    ),
    Tool(
      name: "lsp_setup",
      description: """
        Write buildServer.json (via xcode-build-server) for the project and scheme, pointed at the \
        DerivedData xcforge builds into, so SourceKit-LSP editors stop reporting "No such module".
        """,
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "project": .object([
            "type": .string("string"),
            "description": .string("Path to .xcodeproj or .xcworkspace. Auto-detected if omitted."),
          ]),
          "scheme": .object([
            "type": .string("string"),
            "description": .string("Scheme to index. Auto-detected if omitted."),
          ]),
        ]),
      ])
    ),
  ]

  struct TypecheckInput: Decodable {
    let target: String
    let project: String?
    let simulator: String?
    let configuration: String?
    var fromSnapshot: Bool? = nil
  }

  static func buildTypecheck(_ args: [String: Value]?, env: Environment) async -> CallTool.Result {
    switch ToolInput.decode(TypecheckInput.self, from: args) {
    case .failure(let err): return err
    case .success(let input):
      do {
        let execution = try await executeBuild(
          project: input.project, simulator: input.simulator,
          configuration: await env.session.resolveConfiguration(input.configuration), compileOnly: true,
          target: input.target, fromSnapshot: input.fromSnapshot ?? false, env: env)
        if wantsAgentJSON(args) { return agentJSON(execution, action: "Typecheck of \(input.target)") }
        if execution.succeeded {
          var output = "\(input.target) compiled in \(execution.elapsed)s"
          if let warnings = execution.warningCount, warnings > 0 { output += " (\(warnings) warnings)" }
          return .ok(output)
        }
        return .fail(formatBuildFailure(execution))
      } catch {
        return .fail("\(error)")
      }
    }
  }
}

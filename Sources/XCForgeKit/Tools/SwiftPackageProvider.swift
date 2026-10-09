import Foundation
import MCP

public enum SwiftPackageTools {
  public static let tools: [Tool] = [
    Tool(
      name: "swift_package_build",
      description: "Run `swift build` in a Swift package directory.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "path": .object([
            "type": .string("string"),
            "description": .string(
              "Folder containing Package.swift. Default: .xcforge.yaml packagePath, the current folder, or the only package in the repo."
            ),
          ]),
          "configuration": .object([
            "type": .string("string"),
            "description": .string("Build configuration: debug or release"),
            "enum": .array([.string("debug"), .string("release")]),
          ]),
        ]),
      ])
    ),
    Tool(
      name: "swift_package_test",
      description: "Run `swift test` in a Swift package. Returns failing tests and compile errors with file and line.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "path": .object([
            "type": .string("string"),
            "description": .string(
              "Folder containing Package.swift. Default: .xcforge.yaml packagePath, the current folder, or the only package in the repo."
            ),
          ]),
          "filter": .object([
            "type": .string("string"),
            "description": .string(
              "Test filter passed as --filter (e.g. 'MyTests' or 'MyTests/testFoo')"),
          ]),
          "parallel": .object([
            "type": .string("boolean"),
            "description": .string("Run tests in parallel with --parallel"),
          ]),
        ]),
      ])
    ),
    Tool(
      name: "swift_package_run",
      description: "Run `swift run` to execute a target in a Swift package.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "path": .object([
            "type": .string("string"),
            "description": .string(
              "Folder containing Package.swift. Default: .xcforge.yaml packagePath, the current folder, or the only package in the repo."
            ),
          ]),
          "executable": .object([
            "type": .string("string"),
            "description": .string(
              "Executable target name. Omit if the package has a single executable target."),
          ]),
          "arguments": .object([
            "type": .array([.string("string")]),
            "description": .string("Arguments passed to the executable after --"),
          ]),
        ]),
      ])
    ),
    Tool(
      name: "swift_package_list",
      description: "List package dependencies as JSON using `swift package show-dependencies`.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "path": .object([
            "type": .string("string"),
            "description": .string(
              "Folder containing Package.swift. Default: .xcforge.yaml packagePath, the current folder, or the only package in the repo."
            ),
          ])
        ]),
      ])
    ),
    Tool(
      name: "swift_package_clean",
      description: "Clean Swift package build artifacts using `swift package clean`.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "path": .object([
            "type": .string("string"),
            "description": .string(
              "Folder containing Package.swift. Default: .xcforge.yaml packagePath, the current folder, or the only package in the repo."
            ),
          ])
        ]),
      ])
    ),
  ]

  // MARK: - Input Structs

  private struct BuildInput: Decodable {
    let path: String?
    let configuration: String?
  }

  private struct TestInput: Decodable {
    let path: String?
    let filter: String?
    let parallel: Bool?
  }

  private struct RunInput: Decodable {
    let path: String?
    let executable: String?
    let arguments: [String]?
  }

  private struct PathInput: Decodable {
    let path: String?
  }

  // MARK: - Result Type

  public struct SPMResult: Codable, Sendable, Error {
    public let succeeded: Bool
    public let message: String
    /// The package the command ran in.
    public var packagePath: String?
    /// Errors, test failures and counts read from the output (build and test only).
    public var parsed: SwiftPMOutput?

    public init(succeeded: Bool, message: String, packagePath: String? = nil, parsed: SwiftPMOutput? = nil) {
      self.succeeded = succeeded
      self.message = message
      self.packagePath = packagePath
      self.parsed = parsed
    }
  }

  // MARK: - Finding the package

  /// Folders never searched for packages: build output, dependencies, VCS.
  static let skippedFolders: Set<String> = [
    ".build", ".git", ".swiftpm", "DerivedData", "node_modules", "Pods", "Carthage", "build", ".xcforge",
  ]

  /// `Package.swift` folders under `root`, at most `depth` levels down, nearest first.
  public static func discoverPackages(root: String, depth: Int = 4) -> [String] {
    let fm = FileManager.default
    var found: [String] = []
    var level = [root]
    for _ in 0...depth {
      var next: [String] = []
      for dir in level {
        if fm.fileExists(atPath: (dir as NSString).appendingPathComponent("Package.swift")) { found.append(dir) }
        let children = (try? fm.contentsOfDirectory(atPath: dir)) ?? []
        for child in children.sorted() where !skippedFolders.contains(child) && !child.hasPrefix(".") {
          guard !child.hasSuffix(".xcodeproj"), !child.hasSuffix(".xcworkspace") else { continue }
          let path = (dir as NSString).appendingPathComponent(child)
          var isDir: ObjCBool = false
          if fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue { next.append(path) }
        }
      }
      level = next
    }
    return found
  }

  /// The package to use: `path`, else `.xcforge.yaml` packagePath, else the current folder when
  /// it has a Package.swift, else the only package under the repo.
  public static func resolvePackage(_ path: String?, cwd: String = FileManager.default.currentDirectoryPath)
    -> Result<String, SPMResult>
  {
    let fm = FileManager.default
    func hasManifest(_ dir: String) -> Bool {
      fm.fileExists(atPath: (dir as NSString).appendingPathComponent("Package.swift"))
    }
    if let path {
      let expanded = (path as NSString).expandingTildeInPath
      let absolute = expanded.hasPrefix("/") ? expanded : (cwd as NSString).appendingPathComponent(expanded)
      let dir = absolute.hasSuffix("Package.swift") ? (absolute as NSString).deletingLastPathComponent : absolute
      return hasManifest(dir)
        ? .success(dir) : .failure(SPMResult(succeeded: false, message: "No Package.swift found at \(dir)"))
    }
    if let configured = RepoConfig.discover(from: cwd)?.packagePath, hasManifest(configured) {
      return .success(configured)
    }
    if hasManifest(cwd) { return .success(cwd) }
    let root = RepoRoot.discover(from: cwd) ?? cwd
    let packages = discoverPackages(root: root)
    if packages.count == 1 { return .success(packages[0]) }
    let message =
      packages.isEmpty
      ? "No Package.swift in \(cwd) or under \(root). Pass path."
      : "Several packages under \(root); pass path or set packagePath in .xcforge.yaml:\n"
        + packages.map { "  " + $0 }.joined(separator: "\n")
    return .failure(SPMResult(succeeded: false, message: message))
  }

  /// Run `swift <arguments>` in `package` with the shared build lock, the idle timeout and
  /// `jobs` from the xcodebuild options, so a package build behaves like an app build.
  static func runSwift(
    _ arguments: [String], in package: String, timeout: TimeInterval, env: Environment
  ) async throws -> ShellResult {
    let options = XcodebuildOptions.effective(cwd: package)
    var args = arguments
    if let jobs = options.jobs, ["build", "test"].contains(arguments.first ?? ""), !args.contains("-j") {
      args += ["-j", String(jobs)]
    }
    var lock: BuildLock.Handle?
    if let lockPath = options.lockPath {
      lock = try await BuildLock.acquire(
        path: lockPath, label: "swift " + (arguments.first ?? ""),
        maxWait: options.lockWaitSeconds ?? XcodebuildOptions.defaultLockWaitSeconds)
    }
    defer { lock?.release() }
    let idle = options.idleTimeoutSeconds ?? XcodebuildOptions.defaultIdleTimeoutSeconds
    return try await env.shell.run(
      "/usr/bin/swift", arguments: args, workingDirectory: package, environment: nil, timeout: timeout,
      idleTimeout: idle > 0 ? idle : nil, outputLimit: Shell.defaultOutputLimit)
  }

  /// A build or test result with its errors and failures read out of the output.
  static func parsedResult(action: String, result: ShellResult, package: String) -> SPMResult {
    let output = [result.stdout, result.stderr].filter { !$0.isEmpty }.joined(separator: "\n")
    let parsed = SwiftPMOutput.parse(output)
    var message = parsed.summary(action: action, succeeded: result.succeeded, output: output)
    if let explanation = Xcodebuild.timeoutExplanation(result) { message = explanation + "\n" + message }
    message += "\npackage: \(package)"
    return SPMResult(succeeded: result.succeeded, message: message, packagePath: package, parsed: parsed)
  }

  // MARK: - Public Methods

  public static func executeBuild(path: String?, configuration: String?, env: Environment) async
    -> SPMResult
  {
    let package: String
    switch resolvePackage(path) {
    case .failure(let failure): return failure
    case .success(let resolved): package = resolved
    }
    do {
      let result = try await runSwift(["build", "-c", configuration ?? "debug"], in: package, timeout: 1800, env: env)
      return parsedResult(action: "Build", result: result, package: package)
    } catch {
      return SPMResult(succeeded: false, message: "Error: \(error)", packagePath: package)
    }
  }

  public static func executeTest(path: String?, filter: String?, parallel: Bool?, env: Environment)
    async -> SPMResult
  {
    let package: String
    switch resolvePackage(path) {
    case .failure(let failure): return failure
    case .success(let resolved): package = resolved
    }
    var arguments = ["test"]
    if let filter {
      arguments += ["--filter", filter]
    }
    if parallel == true {
      arguments.append("--parallel")
    }
    do {
      let result = try await runSwift(arguments, in: package, timeout: 1800, env: env)
      return parsedResult(action: "Tests", result: result, package: package)
    } catch {
      return SPMResult(succeeded: false, message: "Error: \(error)", packagePath: package)
    }
  }

  public static func executeRun(
    path: String?, executable: String?, arguments: [String]?, env: Environment
  ) async -> SPMResult {
    let resolvedPath: String
    switch resolvePackage(path) {
    case .failure(let failure): return failure
    case .success(let resolved): resolvedPath = resolved
    }

    var args = ["run"]
    if let executable {
      args.append(executable)
      if let arguments, !arguments.isEmpty {
        args.append("--")
        args += arguments
      }
    }

    do {
      let result = try await env.shell.run(
        "/usr/bin/swift",
        arguments: args,
        workingDirectory: resolvedPath,
        environment: nil,
        timeout: 300
      )
      if result.succeeded {
        return SPMResult(
          succeeded: true, message: result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
      }
      let combined = [result.stdout, result.stderr]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
      return SPMResult(succeeded: false, message: "Run failed:\n\(combined)")
    } catch {
      return SPMResult(succeeded: false, message: "Error: \(error)")
    }
  }

  public static func executeList(path: String?, env: Environment) async -> SPMResult {
    let resolvedPath: String
    switch resolvePackage(path) {
    case .failure(let failure): return failure
    case .success(let resolved): resolvedPath = resolved
    }

    do {
      let result = try await env.shell.run(
        "/usr/bin/swift",
        arguments: ["package", "show-dependencies", "--format", "json"],
        workingDirectory: resolvedPath,
        environment: nil,
        timeout: 30
      )
      if result.succeeded {
        return SPMResult(
          succeeded: true, message: result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
      }
      let combined = [result.stdout, result.stderr]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
      return SPMResult(succeeded: false, message: "Failed to list dependencies:\n\(combined)")
    } catch {
      return SPMResult(succeeded: false, message: "Error: \(error)")
    }
  }

  public static func executeClean(path: String?, env: Environment) async -> SPMResult {
    let resolvedPath: String
    switch resolvePackage(path) {
    case .failure(let failure): return failure
    case .success(let resolved): resolvedPath = resolved
    }

    do {
      let result = try await env.shell.run(
        "/usr/bin/swift",
        arguments: ["package", "clean"],
        workingDirectory: resolvedPath,
        environment: nil,
        timeout: 30
      )
      if result.succeeded {
        return SPMResult(succeeded: true, message: "Clean succeeded at \(resolvedPath)")
      }
      let combined = [result.stdout, result.stderr]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
      return SPMResult(succeeded: false, message: "Clean failed:\n\(combined)")
    } catch {
      return SPMResult(succeeded: false, message: "Error: \(error)")
    }
  }

  // MARK: - MCP Dispatch Helpers

  private static func dispatchResult(_ result: SPMResult) -> CallTool.Result {
    result.succeeded ? .ok(result.message) : .fail(result.message)
  }
}

extension SwiftPackageTools: ToolProvider {
  public static func dispatch(_ name: String, _ args: [String: Value]?, env: Environment) async
    -> CallTool.Result?
  {
    switch name {
    case "swift_package_build":
      switch ToolInput.decode(BuildInput.self, from: args) {
      case .failure(let err): return err
      case .success(let input):
        return dispatchResult(
          await executeBuild(path: input.path, configuration: input.configuration, env: env))
      }
    case "swift_package_test":
      switch ToolInput.decode(TestInput.self, from: args) {
      case .failure(let err): return err
      case .success(let input):
        return dispatchResult(
          await executeTest(
            path: input.path, filter: input.filter, parallel: input.parallel, env: env))
      }
    case "swift_package_run":
      switch ToolInput.decode(RunInput.self, from: args) {
      case .failure(let err): return err
      case .success(let input):
        return dispatchResult(
          await executeRun(
            path: input.path, executable: input.executable, arguments: input.arguments, env: env))
      }
    case "swift_package_list":
      switch ToolInput.decode(PathInput.self, from: args) {
      case .failure(let err): return err
      case .success(let input): return dispatchResult(await executeList(path: input.path, env: env))
      }
    case "swift_package_clean":
      switch ToolInput.decode(PathInput.self, from: args) {
      case .failure(let err): return err
      case .success(let input):
        return dispatchResult(await executeClean(path: input.path, env: env))
      }
    default: return nil
    }
  }
}

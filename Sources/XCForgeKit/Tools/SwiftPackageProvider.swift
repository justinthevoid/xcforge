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
                    "path": .object(["type": .string("string"), "description": .string("Working directory containing Package.swift. Defaults to current directory.")]),
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
            description: "Run `swift test` in a Swift package directory.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "path": .object(["type": .string("string"), "description": .string("Working directory containing Package.swift. Defaults to current directory.")]),
                    "filter": .object(["type": .string("string"), "description": .string("Test filter passed as --filter (e.g. 'MyTests' or 'MyTests/testFoo')")]),
                    "parallel": .object(["type": .string("boolean"), "description": .string("Run tests in parallel with --parallel")]),
                ]),
            ])
        ),
        Tool(
            name: "swift_package_run",
            description: "Run `swift run` to execute a target in a Swift package.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "path": .object(["type": .string("string"), "description": .string("Working directory containing Package.swift. Defaults to current directory.")]),
                    "executable": .object(["type": .string("string"), "description": .string("Executable target name. Omit if the package has a single executable target.")]),
                    "arguments": .object(["type": .array([.string("string")]), "description": .string("Arguments passed to the executable after --")]),
                ]),
            ])
        ),
        Tool(
            name: "swift_package_list",
            description: "List package dependencies as JSON using `swift package show-dependencies`.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "path": .object(["type": .string("string"), "description": .string("Working directory containing Package.swift. Defaults to current directory.")]),
                ]),
            ])
        ),
        Tool(
            name: "swift_package_clean",
            description: "Clean Swift package build artifacts using `swift package clean`.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "path": .object(["type": .string("string"), "description": .string("Working directory containing Package.swift. Defaults to current directory.")]),
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

    public struct SPMResult: Codable, Sendable {
        public let succeeded: Bool
        public let message: String
    }

    // MARK: - Public Methods

    public static func executeBuild(path: String?, configuration: String?, env: Environment) async -> SPMResult {
        let resolvedPath = path ?? FileManager.default.currentDirectoryPath
        guard FileManager.default.fileExists(atPath: resolvedPath + "/Package.swift") else {
            return SPMResult(succeeded: false, message: "No Package.swift found at \(resolvedPath)")
        }

        let config = configuration ?? "debug"
        let arguments = ["build", "-c", config]

        do {
            let result = try await env.shell.run(
                "/usr/bin/swift",
                arguments: arguments,
                workingDirectory: resolvedPath,
                environment: nil,
                timeout: 1800
            )
            if result.succeeded {
                return SPMResult(succeeded: true, message: result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            let combined = [result.stdout, result.stderr]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            return SPMResult(succeeded: false, message: "Build failed:\n\(combined)")
        } catch {
            return SPMResult(succeeded: false, message: "Error: \(error)")
        }
    }

    public static func executeTest(path: String?, filter: String?, parallel: Bool?, env: Environment) async -> SPMResult {
        let resolvedPath = path ?? FileManager.default.currentDirectoryPath
        guard FileManager.default.fileExists(atPath: resolvedPath + "/Package.swift") else {
            return SPMResult(succeeded: false, message: "No Package.swift found at \(resolvedPath)")
        }

        var arguments = ["test"]
        if let filter {
            arguments += ["--filter", filter]
        }
        if parallel == true {
            arguments.append("--parallel")
        }

        do {
            let result = try await env.shell.run(
                "/usr/bin/swift",
                arguments: arguments,
                workingDirectory: resolvedPath,
                environment: nil,
                timeout: 1800
            )
            if result.succeeded {
                return SPMResult(succeeded: true, message: result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            let combined = [result.stdout, result.stderr]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            return SPMResult(succeeded: false, message: "Tests failed:\n\(combined)")
        } catch {
            return SPMResult(succeeded: false, message: "Error: \(error)")
        }
    }

    public static func executeRun(path: String?, executable: String?, arguments: [String]?, env: Environment) async -> SPMResult {
        let resolvedPath = path ?? FileManager.default.currentDirectoryPath
        guard FileManager.default.fileExists(atPath: resolvedPath + "/Package.swift") else {
            return SPMResult(succeeded: false, message: "No Package.swift found at \(resolvedPath)")
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
                return SPMResult(succeeded: true, message: result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
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
        let resolvedPath = path ?? FileManager.default.currentDirectoryPath
        guard FileManager.default.fileExists(atPath: resolvedPath + "/Package.swift") else {
            return SPMResult(succeeded: false, message: "No Package.swift found at \(resolvedPath)")
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
                return SPMResult(succeeded: true, message: result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
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
        let resolvedPath = path ?? FileManager.default.currentDirectoryPath
        guard FileManager.default.fileExists(atPath: resolvedPath + "/Package.swift") else {
            return SPMResult(succeeded: false, message: "No Package.swift found at \(resolvedPath)")
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
    public static func dispatch(_ name: String, _ args: [String: Value]?, env: Environment) async -> CallTool.Result? {
        switch name {
        case "swift_package_build":
            switch ToolInput.decode(BuildInput.self, from: args) {
            case .failure(let err): return err
            case .success(let input): return dispatchResult(await executeBuild(path: input.path, configuration: input.configuration, env: env))
            }
        case "swift_package_test":
            switch ToolInput.decode(TestInput.self, from: args) {
            case .failure(let err): return err
            case .success(let input): return dispatchResult(await executeTest(path: input.path, filter: input.filter, parallel: input.parallel, env: env))
            }
        case "swift_package_run":
            switch ToolInput.decode(RunInput.self, from: args) {
            case .failure(let err): return err
            case .success(let input): return dispatchResult(await executeRun(path: input.path, executable: input.executable, arguments: input.arguments, env: env))
            }
        case "swift_package_list":
            switch ToolInput.decode(PathInput.self, from: args) {
            case .failure(let err): return err
            case .success(let input): return dispatchResult(await executeList(path: input.path, env: env))
            }
        case "swift_package_clean":
            switch ToolInput.decode(PathInput.self, from: args) {
            case .failure(let err): return err
            case .success(let input): return dispatchResult(await executeClean(path: input.path, env: env))
            }
        default: return nil
        }
    }
}

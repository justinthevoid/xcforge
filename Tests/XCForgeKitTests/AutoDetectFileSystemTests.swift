import Foundation
import Testing
@testable import XCForgeKit

@Suite("AutoDetect filesystem abstraction")
struct AutoDetectFileSystemTests {

    // MARK: - testTargets: SPM path

    @Test("testTargets parses test target names from mocked Package.swift")
    func testTargetsSPMPath() async throws {
        let packageContent = """
        let package = Package(
            name: "MyApp",
            targets: [
                .target(name: "MyApp"),
                .testTarget(name: "MyAppTests", dependencies: ["MyApp"]),
                .testTarget(name: "MyAppUITests", dependencies: ["MyApp"]),
            ]
        )
        """

        let env = Environment(
            shell: StubShell(),
            fileExists: { $0.hasSuffix("Package.swift") },
            readFile: { path in
                guard path.hasSuffix("Package.swift") else {
                    throw CocoaError(.fileReadNoSuchFile)
                }
                return packageContent
            }
        )

        let targets = try await AutoDetect.testTargets(
            project: "/tmp/MyApp/MyApp.xcodeproj",
            env: env
        )

        #expect(targets == ["MyAppTests", "MyAppUITests"])
    }

    // MARK: - testTargets: xcodeproj fallback

    @Test("testTargets falls through to xcodebuild when no Package.swift")
    func testTargetsXcodeprojFallback() async throws {
        let xcodebuildJSON = """
        {
            "project": {
                "targets": ["MyApp", "MyAppTests", "MyAppUITests", "Helpers"]
            }
        }
        """

        let env = Environment(
            shell: StubShell(runHandler: { _, _, _, _, _ in
                ShellResult(stdout: xcodebuildJSON, stderr: "", exitCode: 0)
            }),
            fileExists: { _ in false },
            readFile: { _ in throw CocoaError(.fileReadNoSuchFile) }
        )

        let targets = try await AutoDetect.testTargets(
            project: "/tmp/MyApp/MyApp.xcodeproj",
            env: env
        )

        #expect(targets == ["MyAppTests", "MyAppUITests"])
    }

    // MARK: - validateProject

    @Test("validateProject succeeds when directory exists")
    func validateProjectDirectoryExists() throws {
        let env = Environment(
            shell: StubShell(),
            directoryExists: { _ in true }
        )

        #expect(throws: Never.self) {
            try AutoDetect.validateProject("/tmp/MyApp.xcodeproj", env: env)
        }
    }

    @Test("validateProject throws when directory is missing")
    func validateProjectDirectoryMissing() {
        let env = Environment(
            shell: StubShell(),
            directoryExists: { _ in false }
        )

        #expect(throws: ResolverError.self) {
            try AutoDetect.validateProject("/tmp/MyApp.xcodeproj", env: env)
        }
    }
}

// MARK: - StubShell

/// Minimal ShellExecutor stub for tests that don't need shell execution.
private struct StubShell: ShellExecutor {
    var runHandler: @Sendable (String, [String], String?, [String: String]?, TimeInterval) async throws -> ShellResult = { _, _, _, _, _ in
        ShellResult(stdout: "", stderr: "", exitCode: 1)
    }

    func run(
        _ executable: String,
        arguments: [String],
        workingDirectory: String?,
        environment: [String: String]?,
        timeout: TimeInterval
    ) async throws -> ShellResult {
        try await runHandler(executable, arguments, workingDirectory, environment, timeout)
    }

    func xcrun(timeout: TimeInterval, arguments: [String]) async throws -> ShellResult {
        try await runHandler("/usr/bin/xcrun", arguments, nil, nil, timeout)
    }

    func git(_ arguments: [String], workingDirectory: String, timeout: TimeInterval) async throws -> ShellResult {
        try await runHandler("/usr/bin/git", arguments, workingDirectory, nil, timeout)
    }
}

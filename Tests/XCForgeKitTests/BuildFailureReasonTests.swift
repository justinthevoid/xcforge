import Testing

@testable import XCForgeKit

@Suite("Build failure reason classification")
struct BuildFailureReasonTests {

  // MARK: - classifyFailureReason

  @Test func compilerError() {
    let stderr = "/path/to/File.swift:42:5: error: cannot find 'foo' in scope"
    #expect(BuildTools.classifyFailureReason(stderr: stderr) == "compiler_error")
  }

  @Test func databaseLocked() {
    let stderr = "error: unable to open database file\nSourceKitService: note: some noise"
    #expect(BuildTools.classifyFailureReason(stderr: stderr) == "infrastructure")
  }

  @Test func lockedDatabase() {
    let stderr = "database is locked\nfatal error"
    #expect(BuildTools.classifyFailureReason(stderr: stderr) == "infrastructure")
  }

  @Test func corruptedDerivedData() {
    let stderr = "error: corrupted build database detected"
    #expect(BuildTools.classifyFailureReason(stderr: stderr) == "infrastructure")
  }

  @Test func signingError() {
    let stderr = "error: No signing certificate \"iOS Development\" found"
    #expect(BuildTools.classifyFailureReason(stderr: stderr) == "signing_error")
  }

  @Test func provisioningProfile() {
    let stderr = "error: requires a provisioning profile"
    #expect(BuildTools.classifyFailureReason(stderr: stderr) == "signing_error")
  }

  @Test func linkerError() {
    let stderr = "ld: Undefined symbols for architecture arm64"
    #expect(BuildTools.classifyFailureReason(stderr: stderr) == "linker_error")
  }

  @Test func linkerCommandFailed() {
    let stderr = "clang: error: linker command failed with exit code 1"
    #expect(BuildTools.classifyFailureReason(stderr: stderr) == "linker_error")
  }

  @Test func unknownError() {
    let stderr = "some unrecognized failure output"
    #expect(BuildTools.classifyFailureReason(stderr: stderr) == "unknown")
  }

  @Test func emptyStderr() {
    #expect(BuildTools.classifyFailureReason(stderr: "") == "unknown")
  }

  @Test func infrastructurePrioritizedOverCompiler() {
    // Infrastructure errors should win even if compiler errors also present
    let stderr = "unable to open database file\n/path/File.swift:1:1: error: cannot find 'x'"
    #expect(BuildTools.classifyFailureReason(stderr: stderr) == "infrastructure")
  }

  // MARK: - extractStructuredErrors

  @Test func compilerErrorsExtracted() {
    let stderr = """
      warning: some warning
      /path/File.swift:42:5: error: cannot find 'foo' in scope
      /path/File.swift:50:10: error: type 'Bar' has no member 'baz'
      note: some note
      """
    let errors = BuildTools.extractStructuredErrors(stderr: stderr, failureReason: "compiler_error")
    #expect(errors.count == 2)
    #expect(errors[0].contains("cannot find 'foo'"))
    #expect(errors[1].contains("has no member 'baz'"))
  }

  @Test func infrastructureSuppressesSourceKit() {
    let stderr = """
      unable to open database file
      SourceKit: error: some sourcekit noise
      /path/File.swift:1:1: error: cannot find 'x' in scope
      """
    let errors = BuildTools.extractStructuredErrors(stderr: stderr, failureReason: "infrastructure")
    // Should include database line and real error, but not SourceKit noise
    #expect(errors.contains { $0.contains("unable to open database") })
    #expect(!errors.contains { $0.lowercased().contains("sourcekit") })
  }

  @Test func fallbackToStderrTail() {
    let stderr = "some output with no error: markers"
    let errors = BuildTools.extractStructuredErrors(stderr: stderr, failureReason: "unknown")
    #expect(errors.count == 1)
    #expect(errors[0].contains("some output"))
  }

  @Test func emptyStderrExtraction() {
    let errors = BuildTools.extractStructuredErrors(stderr: "", failureReason: "unknown")
    #expect(errors.isEmpty)
  }

  // MARK: - formatBuildFailure

  @Test func formatIncludesFailureReason() {
    let execution = BuildTools.BuildExecution(
      succeeded: false, elapsed: "5.2", scheme: "MyApp",
      simulator: "iPhone 16", configuration: "Debug",
      bundleId: nil, appPath: nil,
      errors: [], failureReason: "compiler_error",
      structuredErrors: ["/path/File.swift:42:5: error: cannot find 'foo'"]
    )
    let output = BuildTools.formatBuildFailure(execution)
    #expect(output.contains("Failure reason: compiler_error"))
    #expect(output.contains("cannot find 'foo'"))
    #expect(output.contains("Build FAILED in 5.2s"))
  }

  @Test func formatFallsBackToLegacyErrors() {
    let execution = BuildTools.BuildExecution(
      succeeded: false, elapsed: "3.0", scheme: "MyApp",
      simulator: "iPhone 16", configuration: "Debug",
      bundleId: nil, appPath: nil,
      errors: ["some raw error"], failureReason: "unknown",
      structuredErrors: nil
    )
    let output = BuildTools.formatBuildFailure(execution)
    #expect(output.contains("some raw error"))
  }
}

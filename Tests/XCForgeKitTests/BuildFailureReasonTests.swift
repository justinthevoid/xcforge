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

  // MARK: - isInfrastructureMessage

  @Test func infraMessage_bootstrapping() {
    #expect(BuildTools.isInfrastructureMessage("operation never finished bootstrapping"))
  }

  @Test func infraMessage_lockedDatabase() {
    #expect(BuildTools.isInfrastructureMessage("unable to open database file"))
    #expect(BuildTools.isInfrastructureMessage("locked database"))
    #expect(BuildTools.isInfrastructureMessage("database is locked"))
  }

  @Test func infraMessage_corruptedDatabase() {
    #expect(BuildTools.isInfrastructureMessage("database is corrupted"))
    #expect(BuildTools.isInfrastructureMessage("corrupted database file"))
  }

  @Test func infraMessage_corruptedAloneIsNotInfra() {
    #expect(!BuildTools.isInfrastructureMessage("asset catalog corrupted"))
    #expect(!BuildTools.isInfrastructureMessage("corrupted"))
  }

  @Test func infraMessage_couldntLoadProject() {
    #expect(BuildTools.isInfrastructureMessage("couldn't load project"))
  }

  @Test func infraMessage_nonInfra() {
    #expect(!BuildTools.isInfrastructureMessage("undefined symbols for architecture arm64"))
    #expect(!BuildTools.isInfrastructureMessage("no signing certificate found"))
    #expect(!BuildTools.isInfrastructureMessage(""))
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

  @Test func infrastructureBareCryptedExcluded() {
    let stderr = """
      asset catalog corrupted
      locked database file
      """
    let errors = BuildTools.extractStructuredErrors(stderr: stderr, failureReason: "infrastructure")
    // Bare "corrupted" without "database" must not appear
    #expect(!errors.contains { $0.contains("asset catalog corrupted") })
    // Database-locked line must still appear
    #expect(errors.contains { $0.contains("locked database") })
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
      structuredErrors: ["/path/File.swift:42:5: error: cannot find 'foo'"],
      xcresultPath: nil, issues: nil, errorCount: nil, warningCount: nil
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
      structuredErrors: nil,
      xcresultPath: nil, issues: nil, errorCount: nil, warningCount: nil
    )
    let output = BuildTools.formatBuildFailure(execution)
    #expect(output.contains("some raw error"))
  }

  @Test func formatPrefersIssuesOverStructuredErrors() {
    let issues = [
      TestTools.BuildIssueObservation(
        severity: .error,
        message: "cannot find 'foo' in scope",
        location: SourceLocation(filePath: "/path/File.swift", line: 42, column: 5),
        source: "xcresult.errors"
      )
    ]
    let execution = BuildTools.BuildExecution(
      succeeded: false, elapsed: "2.0", scheme: "MyApp",
      simulator: "iPhone 16", configuration: "Debug",
      bundleId: nil, appPath: nil,
      errors: ["legacy error"], failureReason: "compiler_error",
      structuredErrors: ["legacy structured"],
      xcresultPath: "/tmp/xcf-build-123.xcresult",
      issues: issues, errorCount: 1, warningCount: 0
    )
    let output = BuildTools.formatBuildFailure(execution)
    #expect(output.contains("cannot find 'foo' in scope"))
    #expect(output.contains("File.swift:42:5"))
    #expect(!output.contains("legacy error"))
    #expect(!output.contains("legacy structured"))
    #expect(output.contains("xcresult:"))
  }

  @Test func formatSeparatesErrorsAndWarnings() {
    let issues = [
      TestTools.BuildIssueObservation(
        severity: .error, message: "type mismatch",
        location: nil, source: "xcresult.errors"
      ),
      TestTools.BuildIssueObservation(
        severity: .warning, message: "unused variable",
        location: nil, source: "xcresult.warnings"
      ),
    ]
    let execution = BuildTools.BuildExecution(
      succeeded: false, elapsed: "1.0", scheme: "MyApp",
      simulator: "iPhone 16", configuration: "Debug",
      bundleId: nil, appPath: nil,
      errors: [], failureReason: "compiler_error",
      structuredErrors: nil,
      xcresultPath: "/tmp/xcf-build-123.xcresult",
      issues: issues, errorCount: 1, warningCount: 1
    )
    let output = BuildTools.formatBuildFailure(execution)
    #expect(output.contains("Errors (1):"))
    #expect(output.contains("type mismatch"))
    #expect(output.contains("Warnings (1):"))
    #expect(output.contains("unused variable"))
  }
}

import ArgumentParser
import Foundation
import XCForgeKit

/// Options shared by `test run`, `test rerun-failed` and `build-test`, so a rerun can be
/// invoked exactly like the run it repeats.
struct TestRunOptionGroup: ParsableArguments {
  @Option(
    help:
      "Total time limit in seconds for each xcodebuild step. Takes precedence over --long. Default: 1800s (7200s with --long)."
  )
  var timeoutSeconds: Int?

  @Option(
    name: .long, parsing: .singleValue,
    help: ArgumentHelp(
      "Environment variable for the test runner (repeatable). Format: KEY=VALUE. The key is auto-prefixed with TEST_RUNNER_; Xcode strips the prefix inside the test process, so 'BLESS_BASELINE=1' surfaces as ProcessInfo.environment[\"BLESS_BASELINE\"]. TEST_RUNNER_XCFORGE_REPO_ROOT is always injected (override with --env XCFORGE_REPO_ROOT=...).",
      valueName: "KEY=VALUE"
    )
  )
  var env: [String] = []

  @Flag(
    inversion: .prefixedNo,
    help:
      "Build for testing first. --no-build tests the last build's products. Default: build (rerun-failed: skip when no source changed since the last build)."
  )
  var build: Bool?

  @Option(help: "Rerun a failing test up to this many more times; tests that then pass are reported as flaky.")
  var retries: Int?

  @Option(help: "Run every test this many times.")
  var iterations: Int?

  @Flag(help: "Repeat the tests until one fails (capped by --iterations when given).")
  var untilFailure = false

  @Flag(inversion: .prefixedNo, help: "Turn parallel testing on or off. Default: the scheme's or test plan's setting.")
  var parallel: Bool?

  @Option(help: "Time allowance per test in seconds (XCTest; Swift Testing uses .timeLimit in code).")
  var testTimeout: Int?

  @Flag(help: "Attach the last lines each failing test printed to its failure.")
  var includeConsole = false

  var testOptions: TestTools.TestRunOptions {
    TestTools.TestRunOptions(
      retries: retries, iterations: iterations, untilFailure: untilFailure, parallel: parallel,
      testTimeoutSeconds: testTimeout)
  }

  var timeout: TimeInterval? { timeoutSeconds.map { TimeInterval($0) } }
}

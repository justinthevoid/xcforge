# Test Tools (7 tools)

All test tools parse `.xcresult` bundles for structured results — no raw xcodebuild output parsing.

> **Defaults note:** the `Default` column shows the *fallback*. `configuration`
> and `testplan` (and `project`/`scheme`/`simulator`) are resolved through the
> parameter precedence chain — a committed `.xcforge.yaml` (`configuration:` /
> `testPlan:` / …) overrides the listed fallback when the parameter is omitted.
> See [auto-detection.md](auto-detection.md).
>
> **Timeout note:** `timeoutSeconds` precedence is explicit arg > `.xcforge.yaml
> testTimeout` > `--long`/`long: true` (7200s) > default 1800s. Non-positive
> values are rejected on both the explicit and the YAML path and fall through to
> the next layer with a warning. Separately, a build or test run that prints
> nothing for `idleTimeoutSeconds` (default 600, 0 disables) is killed and
> reported with `timeout: idle`.

## test_sim

Run tests and return structured xcresult summary.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `project` | No | Auto-detect | Path to .xcodeproj or .xcworkspace |
| `scheme` | No | Auto-detect | Scheme name |
| `simulator` | No | Auto-detect (booted) | Simulator name or UDID |
| `configuration` | No | Debug | Build configuration |
| `testplan` | No | — | Test plan name (if project uses test plans) |
| `filter` | No | — | Test filter — accepts relaxed formats (see below) |
| `coverage` | No | false | Enable code coverage collection |
| `for` | No | `agent` | `agent` returns slim JSON (≤10 fields); `human` returns the full text report |
| `rerunFailed` | No | false | Rerun only the last run's failures with its project, scheme, simulator, plan, configuration and env (unless given); skips the build when nothing changed. MCP form of `xcforge test rerun-failed` |
| `gate` | No | false | Subtract IDs in `.xcforge/known-failures.yaml` when computing `succeeded`. Raw failure list unchanged |

**Test IDs:** one format everywhere: `Target/Suite/test()` for Swift Testing,
`Target/Class/testMethod` for XCTest. `list_tests`, failure lists, `.xcforge/last-failures.json`
and `known-failures.yaml` all use it, and `filter` accepts it as is. Shorter forms work too:
- `Suite/test()` or `Suite` → the target is added when the scheme or test plan has one test target
  (with several, pass the target)
- `Target/Suite/test()` → passed through. xcforge writes the `test()()` spelling xcodebuild needs
  for Swift Testing; pass the plain form

**Filter typo suggestions:** If the filter doesn't match any test ID, xcforge runs a Levenshtein fuzzy match and surfaces "Did you mean: ...?" suggestions in the result.

Use `list_tests` to discover available identifiers if unsure.

**Run options** (`test_sim` and `build_and_test`; CLI flags on `test run`, `build-test`, `test rerun-failed`):

| Parameter | CLI | Description |
|-----------|-----|-------------|
| `timeoutSeconds` | `--timeout-seconds` | Total limit for the run |
| `env` | `--env KEY=VALUE` | Environment for the tests. Keys are prefixed with `TEST_RUNNER_` (Xcode strips it inside tests) |
| `skipBuild` | `--no-build` | Test the last build-for-testing without building. `rerun-failed` does this on its own when no file changed since that build; `--build` forces a build |
| `retries` | `--retries N` | Retry each failing test up to N times. A test that fails then passes is reported under `flaky` |
| `iterations` | `--iterations N` | Run each test N times |
| `untilFailure` | `--until-failure` | With `iterations`, stop at the first failure |
| `parallel` | `--parallel` / `--no-parallel` | Turn parallel testing on or off (default: the scheme's setting) |
| `testTimeoutSeconds` | `--test-timeout` | Per-test time allowance; a test running longer fails |
| `includeConsole` | `--include-console` | Add each failing test's last 40 console lines to its failure |

`retries` can't be combined with `iterations` or `untilFailure`.

**Test build scope:** build-for-testing uses the test plan, and a filter whose IDs all name a
test target builds only those targets. The build uses the same flags as `build_compile`, so
switching between them doesn't rebuild everything.

**Failure output:** each failure lists every message with `file:line` and, for parameterized or
repeated tests, the argument or repetition it came from. Failures with the same message are grouped
("N tests, same message"). Text output shows 20 failures and says how many more there are;
`test_failures` lists them all. When the build or the test runner fails before any test reports,
the result says so (`reason` in agent JSON) and `rerun-failed` refuses instead of rerunning nothing.

**Returns:**
- Total/passed/failed/skipped counts
- Duration
- Per-failure: full test ID, each message with file:line, attachments
- Flaky tests (failed, then passed on retry)
- Failure screenshot paths (auto-exported from xcresult)
- xcresult path (reusable with `test_failures` and `test_coverage`)
- Device info (name, OS version)

---

## test_failures

Get detailed failure information with optional console output per failed test.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `xcresult_path` | No* | — | Path to .xcresult bundle |
| `project` | No* | Auto-detect | Read this project's last test run |
| `include_console` | No | false | Include console output captured during each failed test |

*Without `xcresult_path`, reads the project's last test run (`test_sim`, `build_and_test`, `xcforge test run`). It never runs tests; with no recorded run it says so. When that run's build-for-testing failed, it returns the compile errors with file and line instead of failures.

**Returns per failure:**
- Test class and method name
- Error message
- File path and line number
- Failure screenshot path
- Console output (if `include_console: true`) — shows print/NSLog during that test

---

## test_coverage

Get code coverage per file, sorted by coverage percentage.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `project` | No | Auto-detect | Path to .xcodeproj or .xcworkspace |
| `scheme` | No | Auto-detect | Scheme name |
| `simulator` | No | Auto-detect | Simulator name or UDID |
| `configuration` | No | Debug | Build configuration |
| `min_coverage` | No | 100 | Only show files below this threshold (0-100). Default 100 = show all files. |
| `file` | No | — | Drill into a specific file: shows per-function coverage + execution counts (e.g., `LoginViewModel.swift`) |
| `xcresult_path` | No | — | Reuse existing .xcresult bundle (must have been built with coverage enabled) |

**Returns:** Overall coverage percentage, per-target coverage, per-file coverage sorted ascending (lowest coverage first). Files below `min_coverage` are highlighted.

**Note:** Either provide `xcresult_path` to reuse existing results, or `project`/`scheme` to run tests with coverage enabled.

---

## build_and_diagnose

Build and return structured errors/warnings from xcresult. Unlike `build_sim`, this is optimized for diagnosing build failures — it always parses the xcresult even on success to surface warnings.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `project` | No | Auto-detect | Path to .xcodeproj or .xcworkspace |
| `scheme` | No | Auto-detect | Scheme name |
| `simulator` | No | Auto-detect | Simulator name or UDID |
| `configuration` | No | Debug | Build configuration |

**Returns:** Build status (success/failure), structured errors with file:line, structured warnings with file:line, xcresult path.

---

## build_and_test

Build then test in one call. Stops on a build failure with structured diagnostics. Takes the same run options as `test_sim`.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `project` | No | Auto-detect | Path to .xcodeproj or .xcworkspace |
| `scheme` | No | Auto-detect | Scheme name |
| `simulator` | No | Auto-detect (booted) | Simulator name or UDID |
| `configuration` | No | Debug | Build configuration |
| `testplan` | No | — | Test plan name |
| `filter` | No | — | Test filter — accepts relaxed formats (auto-resolves target prefix) |
| `coverage` | No | false | Enable code coverage collection |
| `for` | No | `agent` | `agent` returns slim JSON (≤10 fields); `human` returns the full text report |
| `gate` | No | false | Subtract IDs in `.xcforge/known-failures.yaml` when computing `succeeded`. Raw failure list unchanged |

**Behavior:**
1. Builds with structured diagnostics (Phase 1)
2. If build fails → returns build errors with file:line, **tests are NOT run**
3. If build succeeds → runs tests (Phase 2), returns pass/fail summary

**Returns:** Phase indicator (`build` or `test`), build elapsed time, build diagnostics (on failure), test execution result (on success).

**Failure persistence:** On a failing run, failure IDs and the run settings (project, test plan, configuration, env) are saved to `.xcforge/last-failures.json` (cleared on green). `xcforge test rerun-failed` (or `test_sim` with `rerunFailed: true`) replays exactly those IDs with the same settings, and skips the build when nothing changed.

---

## list_tests

List available test identifiers for a scheme. Use to discover the correct filter format before running `test_sim` or `build_and_test`.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `project` | No | Auto-detect | Path to .xcodeproj or .xcworkspace |
| `scheme` | No | Auto-detect | Scheme name |
| `simulator` | No | Auto-detect (booted) | Simulator name or UDID |

**Returns:** List of test identifiers in `Target/Suite/test()` / `Target/Class/method` format, grouped by target and class. Includes counts of targets, classes, and test methods.

**Note:** Requires a build-for-testing step (does not run tests). First call may take time to build.

---

## test_plan_inspect

Parse and summarize a `.xctestplan` file without building, resolving packages, launching a simulator, or enumerating compiled tests. Reports timeout allowances, target execution ordering, declared selections, tag filters and disabled targets (`skipped: true` or legacy `enabled: false`).

This is the safe inspection tool in an editing loop where native builds are forbidden. `list_tests` / `xcforge test list` can compile the app to enumerate tests and requires permission for native execution. Static selections and tag filters do not prove an executed test count; use the qualification run's results for that.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `plan` | **Yes** | — | Test plan name, with or without `.xctestplan` extension |
| `project` | No | Auto-detect | Path to .xcodeproj or .xcworkspace |

**Returns:** Test plan name, version, default options (coverage, sanitizers), configurations list, test targets with parallelizable flag and skipped-test counts. Searches `xcshareddata/xctestplans/` and recursively under the project directory.

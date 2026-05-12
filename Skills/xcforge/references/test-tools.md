# Test Tools (7 tools)

All test tools parse `.xcresult` bundles for structured results — no raw xcodebuild output parsing.

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
| `for` | No | `human` | Output audience: `human` preserves full JSON; `agent` returns a slim ≤10-field projection |
| `gate` | No | false | Subtract IDs in `.xcforge/known-failures.yaml` when computing `succeeded`. Raw failure list unchanged |

**Filter auto-resolution:** The test target prefix is auto-resolved when omitted. All these formats work:
- `testMethodName` → auto-prefixes `TestTarget/testMethodName`
- `TestClass/testMethodName` → auto-prefixes `TestTarget/TestClass/testMethodName`
- `TestTarget/TestClass/testMethodName` → passed through as-is

**Filter typo suggestions:** If the filter doesn't match any test ID, xcforge runs a Levenshtein fuzzy match and surfaces "Did you mean: ...?" suggestions in the result.

Use `list_tests` to discover available identifiers if unsure.

**Returns:**
- Total/passed/failed/skipped counts
- Duration
- Per-failure: test name, error message, file:line
- Failure screenshot paths (auto-exported from xcresult)
- xcresult path (reusable with `test_failures` and `test_coverage`)
- Device info (name, OS version)

---

## test_failures

Get detailed failure information with optional console output per failed test.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `xcresult_path` | No* | — | Path to .xcresult bundle |
| `project` | No* | Auto-detect | Alternative: re-derive from project |
| `scheme` | No* | Auto-detect | Used with project |
| `simulator` | No* | Auto-detect | Used with project |
| `include_console` | No | false | Include console output captured during each failed test |

*Provide either `xcresult_path` OR `project`/`scheme`/`simulator`. The xcresult_path from a previous `test_sim` call is preferred.

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

Build then test in one call. Short-circuits on build failure with structured diagnostics. **Preferred over separate `build_and_diagnose` + `test_sim` calls.**

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `project` | No | Auto-detect | Path to .xcodeproj or .xcworkspace |
| `scheme` | No | Auto-detect | Scheme name |
| `simulator` | No | Auto-detect (booted) | Simulator name or UDID |
| `configuration` | No | Debug | Build configuration |
| `testplan` | No | — | Test plan name |
| `filter` | No | — | Test filter — accepts relaxed formats (auto-resolves target prefix) |
| `coverage` | No | false | Enable code coverage collection |
| `env` | No | — | Array of `KEY=VALUE` strings. Each key is auto-prefixed with `TEST_RUNNER_` before xcodebuild runs (Xcode strips the prefix inside tests). `TEST_RUNNER_XCFORGE_REPO_ROOT` is always injected. |
| `for` | No | `human` | Output audience: `human` preserves full JSON; `agent` returns a slim ≤10-field projection |
| `gate` | No | false | Subtract IDs in `.xcforge/known-failures.yaml` when computing `succeeded`. Raw failure list unchanged |

**Behavior:**
1. Builds with structured diagnostics (Phase 1)
2. If build fails → returns build errors with file:line, **tests are NOT run**
3. If build succeeds → runs tests (Phase 2), returns pass/fail summary

**Returns:** Phase indicator (`build` or `test`), build elapsed time, build diagnostics (on failure), test execution result (on success).

**Failure persistence:** On a failing run, failure IDs are saved to `.xcforge/last-failures.json` (cleared on green). Use `xcforge test rerun-failed` to replay exactly those IDs.

---

## list_tests

List available test identifiers for a scheme. Use to discover the correct filter format before running `test_sim` or `build_and_test`.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `project` | No | Auto-detect | Path to .xcodeproj or .xcworkspace |
| `scheme` | No | Auto-detect | Scheme name |
| `simulator` | No | Auto-detect (booted) | Simulator name or UDID |

**Returns:** List of test identifiers in `Target/Class/method` format, grouped by target and class. Includes counts of targets, classes, and test methods.

**Note:** Requires a build-for-testing step (does not run tests). First call may take time to build.

---

## test_plan_inspect

Parse and summarize a `.xctestplan` file without running tests.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `plan` | **Yes** | — | Test plan name, with or without `.xctestplan` extension |
| `project` | No | Auto-detect | Path to .xcodeproj or .xcworkspace |

**Returns:** Test plan name, version, default options (coverage, sanitizers), configurations list, test targets with parallelizable flag and skipped-test counts. Searches `xcshareddata/xctestplans/` and recursively under the project directory.

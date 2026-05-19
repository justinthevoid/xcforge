# xcforge CLI Commands

xcforge operates in two modes:
- **No arguments** → MCP server mode (stdio transport, 106 tools)
- **With arguments** → CLI mode (ArgumentParser-based terminal commands)

## Mode Detection

```bash
xcforge                    # MCP server mode
xcforge build ...          # CLI mode — 19 command groups
xcforge test ...           # CLI mode
xcforge sim ...            # CLI mode
xcforge device ...         # CLI mode
xcforge spm ...            # CLI mode
xcforge log ...            # CLI mode
xcforge console ...        # CLI mode
xcforge screenshot ...     # CLI mode
xcforge ui ...             # CLI mode
xcforge git ...            # CLI mode
xcforge accessibility ...  # CLI mode
xcforge defaults ...       # CLI mode
xcforge diagnose ...       # CLI mode
xcforge plan ...           # CLI mode
xcforge pose ...           # CLI mode
xcforge bless ...          # CLI mode
xcforge debug ...          # CLI mode
```

---

## xcforge build

Build, clean, and inspect Xcode projects. Six subcommands — `run` is the default.

### build run (default subcommand)

Build, install, and launch an iOS app on a simulator. Chains the full pipeline: build → boot sim → install → launch. This is the **Cmd+R equivalent**. With `--diagnose`, runs build-only with structured diagnostics (skips the pipeline).

```bash
xcforge build                                    # Same as `xcforge build run`
xcforge build --scheme MyApp --simulator "iPhone 16 Pro"
xcforge build --configuration Release
xcforge build --diagnose                         # Build-only with structured diagnostics
xcforge build --json                             # Machine-readable JSON output (includes pipeline phase statuses)
```

| Flag | Description |
|------|-------------|
| `--project <path>` | Path to .xcodeproj or .xcworkspace. Auto-detected if omitted |
| `--scheme <name>` | Xcode scheme name. Auto-detected if omitted |
| `--simulator <name\|udid>` | Simulator name or UDID. Auto-detected from booted simulator |
| `--configuration <config>` | Build configuration (Debug/Release). Default: Debug |
| `--diagnose` | Build-only with structured diagnostics (skips boot/install/launch) |
| `--json` | Machine-readable JSON output |

**Pipeline behavior:** On build success, automatically boots the simulator (if not already booted), installs the app, and launches it. On build failure, stops immediately with build errors. Persists `bundleId` and `appPath` to `defaults.json` so subsequent `sim install` / `sim launch` calls auto-detect across process boundaries.

**JSON output:** With `--json`, emits a `BuildRunResult` with `build`, `boot`, `install`, `launch` phase statuses plus `appPid` and `appRunning` fields.

### build diagnose

Show structured diagnostics from the last build's xcresult bundle. Useful for inspecting errors and warnings after a build without re-building.

```bash
xcforge build diagnose                           # Auto-detect most recent xcresult
xcforge build diagnose --xcresult /path/to/result.xcresult
xcforge build diagnose --errors-only             # Suppress warnings
xcforge build diagnose --json
```

| Flag | Description |
|------|-------------|
| `--xcresult <path>` | Path to .xcresult bundle. Auto-detected from /tmp if omitted |
| `--errors-only` | Show only errors, suppressing warnings |
| `--json` | Machine-readable JSON output |

### build compile

Fast compile-only build without simulator boot/install/launch. Reuses the standard build infrastructure.

```bash
xcforge build compile                              # Compile-only, auto-detect everything
xcforge build compile --project MyApp.xcodeproj --scheme MyApp
xcforge build compile --configuration Release
xcforge build compile --long                       # 1800s timeout instead of 180s
xcforge build compile --json
```

| Flag | Description |
|------|-------------|
| `--project <path>` | Path to .xcodeproj or .xcworkspace. Auto-detected if omitted |
| `--scheme <name>` | Xcode scheme name. Auto-detected if omitted |
| `--simulator <name\|udid>` | Simulator name or UDID (for SDK selection). Auto-detected if omitted |
| `--configuration <config>` | Build configuration (Debug/Release). Default: Debug |
| `--long` | Use 1800s timeout instead of default 180s |
| `--json` | Machine-readable JSON output |

**Use case:** Rapid code iteration without deployment latency. Does not boot simulator or install app.

### build clean

Clean Xcode build artifacts for a project/scheme.

```bash
xcforge build clean
xcforge build clean --project MyApp.xcodeproj --scheme MyApp
xcforge build clean --json
```

### build discover

Find .xcodeproj and .xcworkspace files in a directory.

```bash
xcforge build discover                           # Search current directory
xcforge build discover --path /path/to/projects
xcforge build discover --json
```

### build schemes

List available schemes for a project.

```bash
xcforge build schemes
xcforge build schemes --project MyApp.xcodeproj
xcforge build schemes --json
```

**Exit code:** 0 on success, 1 on failure.

---

## xcforge test

Run tests, inspect failures, and report coverage. Three subcommands — `run` is the default.

### test run (default subcommand)

Run xcodebuild test on simulator. Same logic as the `test_sim` MCP tool.

```bash
xcforge test                                     # Same as `xcforge test run`
xcforge test run                                 # Auto-detect everything
xcforge test --scheme MyApp --filter "MyTests/testLogin"
xcforge test --testplan AllTests
xcforge test --coverage                          # Enable code coverage collection
xcforge test --for agent                         # Slim ≤10-field JSON output for agents
xcforge test --gate                              # Subtract known-failures.yaml from pass/fail
xcforge test --json                              # Machine-readable JSON output
```

| Flag | Description |
|------|-------------|
| `--project <path>` | Path to .xcodeproj or .xcworkspace. Auto-detected if omitted |
| `--scheme <name>` | Xcode scheme name. Auto-detected if omitted |
| `--simulator <name\|udid>` | Simulator name or UDID. Auto-detected from booted simulator |
| `--configuration <config>` | Build configuration (Debug/Release). Default: Debug |
| `--testplan <name>` | Test plan name |
| `--filter <pattern>` | Test filter — accepts `testMethod`, `Class/testMethod`, or `Target/Class/testMethod` (target auto-resolved). Typos surface "Did you mean: ...?" suggestions |
| `--coverage` | Enable code coverage collection |
| `--for <audience>` | Output audience: `human` (default) or `agent`. `agent` implies `--json` with a slim shape |
| `--gate` | Subtract IDs in `.xcforge/known-failures.yaml` from `succeeded` count |
| `--json` | Machine-readable JSON output |

**Output:** Pass/fail/skip/expected-failure counts, elapsed time, device info, failure summaries with test names, screenshot paths. xcresult path for follow-up commands.

**Exit code:** 0 when all tests pass, 1 when any test fails.

### test rerun-failed

Rerun only the tests that failed in the most recent run. Reads failure IDs from `.xcforge/last-failures.json` (written automatically by `test run` and `build-test`).

```bash
xcforge test rerun-failed
xcforge test rerun-failed --scheme MyApp --simulator "iPhone 16 Pro"
xcforge test rerun-failed --for agent --gate
xcforge test rerun-failed --json
```

| Flag | Description |
|------|-------------|
| `--project <path>` | Auto-detected if omitted |
| `--scheme <name>` | Auto-detected if omitted |
| `--simulator <name\|udid>` | Auto-detected if omitted |
| `--configuration <config>` | Build configuration. Default: Debug |
| `--testplan <name>` | Test plan name |
| `--long` | Use 1800s timeout instead of 180s |
| `--for <audience>` | `human` (default) or `agent` |
| `--gate` | Apply known-failures gate to the rerun result |
| `--json` | Machine-readable JSON output |

**Exit code:** 2 if no prior failures are recorded. 0 if rerun passes, 1 if any fail.

### test plan inspect

Parse and summarize a `.xctestplan` file without running tests.

```bash
xcforge test plan inspect --plan AllTests
xcforge test plan inspect --plan AllTests --project MyApp.xcodeproj
xcforge test plan inspect --plan AllTests --json
```

| Flag | Description |
|------|-------------|
| `--plan <name>` | **Required** — test plan name, with or without `.xctestplan` extension |
| `--project <path>` | Auto-detected if omitted |
| `--json` | Machine-readable JSON output |

**Output:** Test plan name, version, default options, configurations, test targets with parallelizable flag and skipped-test counts.

### test failures

Extract failed tests with error messages, console output, and screenshots. Same logic as the `test_failures` MCP tool. Provide `--xcresult-path` to analyze an existing result, or omit to run tests first.

```bash
xcforge test failures --xcresult-path /tmp/xcf-test-1234.xcresult
xcforge test failures --include-console          # Include print/NSLog output per failed test
xcforge test failures --json
```

| Flag | Description |
|------|-------------|
| `--xcresult-path <path>` | Path to existing .xcresult bundle. Skips running tests |
| `--project <path>` | Auto-detected if omitted |
| `--scheme <name>` | Auto-detected if omitted |
| `--simulator <name\|udid>` | Auto-detected if omitted |
| `--include-console` | Include console output (print/NSLog) for each failed test |
| `--json` | Machine-readable JSON output |

**Output:** Per-failure: test name, identifier, error message, screenshot path, console output. Summary screenshot list.

**Exit code:** 0 when no failures, 1 when failures exist.

### test coverage

Show code coverage report. Without `--file`: per-file overview. With `--file`: per-function detail. Same logic as the `test_coverage` MCP tool.

```bash
xcforge test coverage                            # Overview — per-target/file coverage %
xcforge test coverage --xcresult-path /tmp/xcf-test-1234.xcresult
xcforge test coverage --min-coverage 80          # Only show files below 80%
xcforge test coverage --file LoginViewModel.swift  # Per-function drill-down
xcforge test coverage --json
```

| Flag | Description |
|------|-------------|
| `--file <name>` | Drill into a specific file for per-function coverage |
| `--xcresult-path <path>` | Path to existing .xcresult bundle (must have coverage enabled) |
| `--project <path>` | Auto-detected if omitted |
| `--scheme <name>` | Auto-detected if omitted |
| `--simulator <name\|udid>` | Auto-detected if omitted |
| `--min-coverage <percent>` | Only show files below this coverage %. Default: 100 (show all) |
| `--json` | Machine-readable JSON output |

**Output (overview):** Overall coverage %, per-target coverage, per-file coverage sorted ascending.
**Output (--file):** File coverage %, per-function coverage with line numbers, execution counts, UNTESTED markers, untested function summary.

### test list

List available test identifiers (Target/Class/method) for a scheme. Use to discover the correct filter format. Same logic as the `list_tests` MCP tool.

```bash
xcforge test list                                # List all tests
xcforge test list --scheme MyApp                 # Specific scheme
xcforge test list --json                         # Machine-readable JSON
```

| Flag | Description |
|------|-------------|
| `--project <path>` | Auto-detected if omitted |
| `--scheme <name>` | Auto-detected if omitted |
| `--simulator <name\|udid>` | Auto-detected if omitted |
| `--json` | Machine-readable JSON output |

**Output:** Test identifiers grouped by target and class. Includes filter usage examples.

---

## xcforge build-test

Build then test in one step. Short-circuits on build failure with structured diagnostics. Same logic as the `build_and_test` MCP tool. **Preferred for TDD workflows.**

```bash
xcforge build-test                               # Build + test all
xcforge build-test --filter "MyTests/testFoo"    # Build + run specific test
xcforge build-test --coverage                    # With code coverage
xcforge build-test --env BLESS_BASELINE=1        # Inject TEST_RUNNER_BLESS_BASELINE=1 into test process
xcforge build-test --for agent                   # Slim ≤10-field JSON (agent-safe output)
xcforge build-test --gate                        # Subtract known-failures.yaml from pass/fail
xcforge build-test --json                        # Machine-readable JSON
```

| Flag | Description |
|------|-------------|
| `--project <path>` | Auto-detected if omitted |
| `--scheme <name>` | Auto-detected if omitted |
| `--simulator <name\|udid>` | Auto-detected if omitted |
| `--configuration <config>` | Build configuration (Debug/Release). Default: Debug |
| `--testplan <name>` | Test plan name |
| `--filter <pattern>` | Test filter — accepts relaxed formats (auto-resolves target prefix). Typos surface "Did you mean: ...?" suggestions |
| `--coverage` | Enable code coverage collection |
| `--env <KEY=VALUE>` | Repeatable. Each key is auto-prefixed with `TEST_RUNNER_` before xcodebuild. `TEST_RUNNER_XCFORGE_REPO_ROOT` is always injected; override via `--env XCFORGE_REPO_ROOT=...` |
| `--for <audience>` | `human` (default) or `agent`. `agent` implies `--json` with a slim shape |
| `--gate` | Subtract IDs in `.xcforge/known-failures.yaml` from `succeeded` count |
| `--json` | Machine-readable JSON output |

**Output on build failure:** Build elapsed time, structured errors with file:line, warnings. Tests are NOT run.
**Output on test failure:** Build OK time, test pass/fail counts, failure details, screenshot paths, xcresult path.
**Exit code:** 0 when build and all tests pass, 1 otherwise.

---

## xcforge sim

Manage iOS simulators. 18 subcommands — `list` is the default.

```bash
xcforge sim                                      # Same as `xcforge sim list`
xcforge sim list                                 # List all simulators with state/UDID
xcforge sim list --filter iPhone                 # Filter by name/state
xcforge sim info                                 # Get display metrics for booted simulator
xcforge sim info --simulator "iPhone 16 Pro"     # Get metrics for specific simulator
xcforge sim boot "iPhone 16 Pro"                 # Boot a simulator
xcforge sim shutdown "iPhone 16 Pro"             # Shutdown (or "all")
xcforge sim install --app-path /path/to/App.app  # Install app (auto-detects sim)
xcforge sim launch --bundle-id com.app.id        # Launch app (auto-detects sim)
xcforge sim terminate --bundle-id com.app.id     # Terminate app
xcforge sim clone "iPhone 16 Pro" --name "Clone" # Clone simulator
xcforge sim erase "iPhone 16 Pro"                # Erase to factory state
xcforge sim delete "Clone"                       # Permanently delete
xcforge sim orientation LANDSCAPE                # Set orientation via WDA
xcforge sim record-start                         # Start video recording
xcforge sim record-start --path /tmp/demo.mov    # Custom output path
xcforge sim record-stop                          # Stop recording, get file path
xcforge sim location --latitude 37.7749 --longitude -122.4194  # Set GPS
xcforge sim location-reset                       # Clear GPS override
xcforge sim appearance --appearance dark         # Set light/dark mode
xcforge sim statusbar --time "9:41" --battery-level 100  # Override status bar
xcforge sim statusbar-clear                      # Restore default status bar
```

All subcommands support `--json`. `install`, `launch`, `terminate` auto-detect simulator and bundle ID from session state.

---

## xcforge device

Manage physical iOS/iPadOS devices via devicectl. 7 subcommands — `list` is the default.

```bash
xcforge device                                   # Same as `xcforge device list`
xcforge device list                              # List connected devices
xcforge device list --filter iPhone              # Filter by name/UDID/OS
xcforge device info "iPhone"                     # Detailed device info
xcforge device install /path/to/App.app --device "iPhone"  # Install app
xcforge device uninstall com.app.id --device "iPhone"      # Uninstall app
xcforge device launch com.app.id --device "iPhone"         # Launch app
xcforge device launch com.app.id --device "iPhone" --console --timeout 30  # With console
xcforge device terminate com.app.id --device "iPhone"      # Terminate app
xcforge device apps --device "iPhone"                      # List installed apps
xcforge device apps --device "iPhone" --include-system     # Include system apps
```

All subcommands support `--json`.

---

## xcforge spm

Swift package management. 5 subcommands — `build` is the default.

```bash
xcforge spm build                                # Build package in current dir
xcforge spm build --configuration release        # Release build
xcforge spm build --path /path/to/package        # Custom path
xcforge spm test                                 # Run all tests
xcforge spm test --filter "MyTests/testFoo"      # Filter tests
xcforge spm test --parallel                      # Parallel execution
xcforge spm run                                  # Run single executable target
xcforge spm run mytool -- --verbose              # Run named target with args
xcforge spm list                                 # Show dependency tree (JSON)
xcforge spm clean                                # Clean build artifacts
```

All subcommands support `--json`. `--path` defaults to current directory.

---

## xcforge log

Stream, read, and wait on simulator logs. Four subcommands — `read` is the default.

```bash
xcforge log start                                # Start capture (smart mode, debug level)
xcforge log start --mode app                     # App-only logs + crashes
xcforge log start --mode verbose                 # Unfiltered system logs
xcforge log start --process MyApp                # Filter by process name
xcforge log start --subsystem com.myapp          # Filter by subsystem
xcforge log read                                 # Read with topic filtering (app + crashes)
xcforge log read --include network               # Add network topic
xcforge log read --include lifecycle --last 50   # Last 50 lifecycle + app lines
xcforge log read --clear                         # Clear buffer after reading
xcforge log stop                                 # Stop capture
xcforge log wait --pattern "error.*timeout"      # Wait for regex pattern
xcforge log wait --pattern "launched" --timeout 10
```

All subcommands support `--json`.

---

## xcforge console

Launch, read, and stop app console output capture (print/NSLog). Three subcommands — `read` is the default.

```bash
xcforge console launch                           # Launch app with console capture
xcforge console launch --bundle-id com.app.id    # Explicit bundle ID
xcforge console launch --args "--verbose"         # Pass launch args to app
xcforge console read                             # Read stdout + stderr
xcforge console read --stream stdout --last 20   # Last 20 stdout lines
xcforge console read --clear                     # Clear buffer after reading
xcforge console stop                             # Stop capture and terminate app
```

All subcommands support `--json`. Auto-detects simulator and bundle ID from session state.

---

## xcforge screenshot

Capture simulator screenshots and manage visual baselines. Three subcommands — `capture` is the default.

```bash
xcforge screenshot                               # Same as `xcforge screenshot capture`
xcforge screenshot capture                       # Capture to /tmp/xcforge-screenshot.png
xcforge screenshot capture --format jpeg --output /path/to/file.jpeg
xcforge screenshot capture --grid                # Include point-coordinate grid overlay
xcforge screenshot baseline --name login-screen  # Save as named baseline
xcforge screenshot baseline --name login-screen --baseline-dir ./baselines
xcforge screenshot compare --name login-screen   # Pixel diff against baseline
xcforge screenshot compare --name login-screen --threshold 1.0
```

All subcommands support `--json`. `--format` defaults to png. `--threshold` defaults to 0.5%. `--grid` overlays 50pt minor grid lines and 100pt labeled divisions for coordinate verification.

`screenshot capture` also accepts `--wait-for <signal>` / `--timeout <sec>` (same grammar as `wait-ready`/`pose`): gate the capture on a real signal instead of capturing whatever is on screen. Warn-only — a missed gate prints a warning and captures anyway, it never fails the command. `--timeout 0` skips the gate (pass-through) and captures immediately. The JSON result carries an `appForeground` field (`true`/`false`) whenever WDA can resolve the foreground bundle; it is **null/omitted only** when WDA is unreachable or the foreground bundle is unresolvable (never a false `false`). It is additive (`encodeIfPresent`), so existing JSON consumers that ignore unknown keys are unaffected.

```bash
xcforge screenshot capture --output /tmp/s.png --wait-for a11y:home.title
xcforge screenshot capture --wait-for "launch-complete" --timeout 25 --json
```

---

## xcforge wait-ready

Standalone launch-readiness gate. Blocks until the screen is *actually* ready, gating on a real signal instead of a blind sleep. Script-friendly: **exits non-zero on timeout**, so `xcforge wait-ready --for a11y:home.title && xcforge screenshot capture` composes correctly.

```bash
xcforge wait-ready                                      # default: --for launch-complete, 20s
xcforge wait-ready --for a11y:home.newspaperCard        # element-presence gate
xcforge wait-ready --for "launch-complete,text:Welcome" # all must hold
xcforge wait-ready --for a11y:x --timeout 30 --poll-ms 100
xcforge wait-ready --for a11y:x --json
```

| Flag | Description |
|------|-------------|
| `--for <signal>` | Signal(s), comma-separated, **all must hold**: `launch-complete` (app foreground, WDA-derived), `a11y:<accessibilityId>` (element present — the real "right screen is up"), `text:<substring>` (any label/value contains it). Default: `launch-complete`. |
| `--timeout <sec>` | Ceiling. Capture-equivalent fires the instant the signal holds, so a high ceiling costs nothing on the fast path. `0` skips the gate (pass-through): the command reports `ready` and **exits 0**, so `wait-ready --timeout 0 && …` composes. Default `20`. |
| `--poll-ms <ms>` | Poll cadence. Default `150` (mirrors the proven `pollForActiveBundleId` contract). |
| `--simulator <name\|udid>` | Scope AXP/WDA queries. Auto-detected if omitted. |
| `--json` | Emit `{ ready, mode, elapsedMs, satisfied, signals, reason }`. |

**Detection order:** AXP first (reads Simulator.app's accessibility tree directly — **no WDA session required**), WDA fallback (`findElement` / `verifyActiveBundleId`), then a reported degraded wait. `mode` (`axp` \| `wda` \| `degraded`) tells an agent whether it got a real gate or a degraded sleep — `degraded` always prints a one-line `reason` (never silently degrade). `a11y:`/`text:` are the strong signals; `launch-complete` only proves the app is foreground (true at the launch splash, *before* a deep-link nav push). MCP tool: `wait_ready` (params `simulator`, `for`, `timeout`).

---

## xcforge ui

UI automation via WebDriverAgent. 17 subcommands — `status` is the default.

```bash
xcforge ui status                                # Check WDA health
xcforge ui session                               # Create WDA session
xcforge ui session --bundle-id com.app.id        # Bind session to app — verifies CFBundleIdentifier
xcforge ui ls                                    # Flat element list — auto picks WDA when sim is booted
xcforge ui ls --source wda                       # Force WDA (iOS app tree); use this if sheets aren't visible
xcforge ui ls --source axp                       # Force macOS Accessibility (Simulator.app chrome)
xcforge ui ls --scope home.drawer.root           # Restrict to a11y-id and its descendants
xcforge ui find --using "accessibility id" --value "Save"
xcforge ui find --using "accessibility id" --value "Save" --scroll
xcforge ui find-all --using "class name" --value "XCUIElementTypeButton"
xcforge ui tap-by-id home.drawer.cancel          # Atomic find + tap by a11y-id
xcforge ui tap-by --using "accessibility id" --value "Save"
xcforge ui click --element-id <id>
xcforge ui tap --x 200 --y 400                  # Tap at point coordinates
xcforge ui tap-pixel --x 1080 --y 2400          # Tap at pixel coordinates
xcforge ui double-tap --x 200 --y 400
xcforge ui long-press --x 200 --y 400 --duration-ms 2000
xcforge ui swipe --start-x 200 --start-y 600 --end-x 200 --end-y 200
xcforge ui pinch --center-x 200 --center-y 400 --scale 2.0
xcforge ui drag --from-x 100 --from-y 200 --to-x 300 --to-y 400
xcforge ui type --text "hello world"
xcforge ui type --text "hello" --element-id <id> --clear-first
xcforge ui get-text --element-id <id>
xcforge ui source                                # Full view hierarchy (JSON)
xcforge ui source --format xml
xcforge ui alert --action accept_all             # Handle all alerts
xcforge ui alert --action dismiss --button-label "Cancel"
```

**WDA session binding.** `ui session --bundle-id <id>` binds the WDA session to a
specific app. This is the right hammer when WDA queries (`find`, `tap-by-id`,
class-chain) can't reach SwiftUI sheets, alerts, or `fullScreenCover` — those
mount in a secondary window owned by the app, and only sessions bound to the
app's bundle id walk every window. `xcforge ui *` commands auto-create a session,
and the bound bundle id is now persisted across recreates (mid-call retry,
WDA restart). `ui session --bundle-id` verifies binding via `GET /session/<sid>`
and exits non-zero if WDA reports a different `CFBundleIdentifier`.

**Structured session errors + bounded auto-heal.** A failing `ui session` no
longer emits the opaque `Session creation failed: ExitCode(rawValue: 1)`. The
result now carries a structured envelope: `error: "wda_session_create_failed"`,
an enumerated `cause` (`wda_runner_not_running`, `wda_runner_build_failed`,
`no_booted_simulator`, `bundle_not_installed`, `session_bind_rejected`,
`unknown`), a human `detail`, and a copy-pasteable `remediation`. On a
**recoverable** cause (runner not running / build failed) it attempts **exactly
one** bounded rebuild+relaunch+rebind via the existing WDA orchestrator and
reports `recovered: true` (or fails with `cause: wda_runner_build_failed` + the
exact repair command). The CLI still exits non-zero with the readable cause.

| Flag | Description |
|------|-------------|
| `--no-autoheal` | Disable the bounded auto-heal — preserve today's fail-fast for debugging. The structured error is still emitted. |
| `--relaunch-app` | Allow auto-heal to relaunch the user app (off by default — the agent may have intentional app state; runner repair is safe, app relaunch is not). |

**`appForeground` on interaction results.** `ui tap-by-id`, `ui tap-by`,
`ui click`, `ui find`, and `screenshot capture` JSON include `appForeground`
(`true`/`false`) **whenever WDA can resolve the foreground bundle** — so an
agent can tell from a command result that the app it thinks it is driving is
actually backgrounded, without inferring it from a screenshot. It is
**null/omitted only** when WDA is unreachable or the foreground bundle is
unresolvable (never a false `false`). The field is additive (`encodeIfPresent`;
old consumers ignore unknown keys), keeping existing JSON shapes
backward-compatible.

**ui ls source selection.** `--source auto` (default) picks WDA when any iOS sim
is booted, AXP otherwise. Use `--source wda` to force the iOS app's tree when
auto-detection misfires; use `--source axp` for macOS workflows. AXP returns
Simulator.app's menubar/dock chrome — almost never what you want when
automating an iOS app.

All subcommands support `--json`.

---

## xcforge git

Git operations for a repository. Five subcommands — `status` is the default.

```bash
xcforge git                                      # Same as `xcforge git status`
xcforge git status                               # Porcelain status (current dir)
xcforge git status --path /path/to/repo
xcforge git diff                                 # Unstaged changes
xcforge git diff --staged                        # Staged changes
xcforge git diff --file src/MyFile.swift
xcforge git log                                  # Last 10 commits (oneline)
xcforge git log --count 20 --no-oneline          # Detailed format
xcforge git commit --message "fix: bug"          # Commit staged changes
xcforge git commit --message "feat: new" --add-all
xcforge git branch                               # List branches
xcforge git branch --action create --name feature/x
xcforge git branch --action switch --name main
```

All subcommands support `--json`. `--path` defaults to current directory.

---

## xcforge defaults

Manage persisted workflow defaults (project, scheme, simulator). Defaults are used by both MCP tools and CLI commands when explicit parameters are omitted.

### show (default subcommand)
```bash
xcforge defaults           # Same as `xcforge defaults show`
xcforge defaults show      # Display current persisted defaults
```

### set
```bash
xcforge defaults set --project /path/to/MyApp.xcodeproj
xcforge defaults set --scheme MyApp
xcforge defaults set --simulator "iPhone 16 Pro"
xcforge defaults set --project MyApp.xcodeproj --scheme MyApp --simulator "iPhone 16 Pro"
```

| Flag | Description |
|------|-------------|
| `--project <path>` | Default .xcodeproj or .xcworkspace path |
| `--scheme <name>` | Default scheme name |
| `--simulator <name\|udid>` | Default simulator name or UDID |

### clear
```bash
xcforge defaults clear     # Remove all persisted defaults
```

---

## xcforge diagnose

Structured diagnosis workflows for CI/CD and debugging. 10 subcommands mapping to workflow phases. Each subcommand outputs human-readable terminal UI by default, or structured JSON with `--json`.

### diagnose start

Initialize a diagnosis run with resolved context (project, scheme, simulator).

```bash
xcforge diagnose start
xcforge diagnose start --project MyApp.xcodeproj --scheme MyApp --simulator "iPhone 16 Pro"
xcforge diagnose start --reuse-run-id abc123
xcforge diagnose start --configuration Release
xcforge diagnose start --json
```

| Flag | Required | Description |
|------|----------|-------------|
| `--project <path>` | No | Auto-detected if omitted |
| `--scheme <name>` | No | Auto-detected if omitted |
| `--simulator <name\|udid>` | No | Auto-detected if omitted |
| `--reuse-run-id <id>` | No | Reuse context from a previous run |
| `--configuration <config>` | No | Build configuration (Debug/Release) |
| `--json` | No | Machine-readable JSON output |

**Returns:** Run ID + resolved context (schema version, workflow, phase, status).

### diagnose build

Diagnose build for an active run. If `--run-id` is omitted, auto-resolves to the newest active run (or newest recent one).

```bash
xcforge diagnose build                           # Auto-resolve run ID
xcforge diagnose build --run-id <id>
xcforge diagnose build --json
```

### diagnose test

Diagnose test run for an active run. If `--run-id` is omitted, auto-resolves to the newest active run.

```bash
xcforge diagnose test                            # Auto-resolve run ID
xcforge diagnose test --run-id <id>
xcforge diagnose test --json
```

### diagnose runtime

Launch app and capture runtime signals (crashes, memory pressure, logs). If `--run-id` is omitted, auto-resolves to the newest active run.

```bash
xcforge diagnose runtime                         # Auto-resolve run ID
xcforge diagnose runtime --run-id <id> --capture-screenshot
xcforge diagnose runtime --json
```

### diagnose status

Inspect status of an active or recent run. Omit `--run-id` to use the newest.

```bash
xcforge diagnose status
xcforge diagnose status --run-id <id>
xcforge diagnose status --json
```

### diagnose evidence

Inspect all available evidence (screenshots, logs, crashes) for a run.

```bash
xcforge diagnose evidence
xcforge diagnose evidence --run-id <id>
xcforge diagnose evidence --json
```

### diagnose inspect

Consolidated troubleshooting view — correlates action timeline, evidence, and terminal classification.

```bash
xcforge diagnose inspect
xcforge diagnose inspect --run-id <id>
xcforge diagnose inspect --json
```

### diagnose verify

Rerun validation with optional overrides. If `--run-id` is omitted, auto-resolves to the newest active run.

```bash
xcforge diagnose verify                          # Auto-resolve run ID
xcforge diagnose verify --run-id <id>
xcforge diagnose verify --run-id <id> --scheme MyAppFixed
xcforge diagnose verify --run-id <id> --simulator "iPhone SE"
xcforge diagnose verify --json
```

| Flag | Required | Description |
|------|----------|-------------|
| `--run-id <id>` | No | Run to re-verify. Auto-resolves to newest active/recent if omitted |
| `--project <path>` | No | Override project |
| `--scheme <name>` | No | Override scheme |
| `--simulator <name\|udid>` | No | Override simulator |
| `--configuration <config>` | No | Override build config |
| `--json` | No | Machine-readable output |

### diagnose compare

Compare original result vs latest rerun. Use `--compact` for agent-friendly output with only outcome, changed evidence, and unchanged blockers.

```bash
xcforge diagnose compare
xcforge diagnose compare --run-id <id>
xcforge diagnose compare --compact               # Agent-friendly: outcome + changed evidence only
xcforge diagnose compare --json
```

### diagnose result

Return final proof-oriented result for the run.

```bash
xcforge diagnose result
xcforge diagnose result --run-id <id>
xcforge diagnose result --json
```

---

## xcforge accessibility

Check Dynamic Type and localization layout compliance. Two subcommands — `dynamic-type` is the default.

### accessibility dynamic-type (default subcommand)

Render the current screen across Dynamic Type content size categories and detect truncation.

```bash
xcforge accessibility                        # Same as `xcforge accessibility dynamic-type`
xcforge accessibility dynamic-type --sizes all
xcforge accessibility dynamic-type --sizes "XS,XXXL,AccessibilityXXXL"
xcforge accessibility dynamic-type --threshold 3.0 --settle-time 2.0
xcforge accessibility dynamic-type --json
```

| Flag | Description |
|------|-------------|
| `--simulator <name\|udid>` | Simulator name or UDID. Auto-detected from booted simulator |
| `--sizes <list>` | Comma-separated size categories. Use 'all' for all 12. Default: XS,L,XXXL,AccessibilityXXXL |
| `--threshold <percent>` | Max allowed diff % from base size. Default: 5.0 |
| `--settle-time <seconds>` | Wait time after changing size. Default: 1.5 |
| `--json` | Machine-readable JSON output |

Size categories can be short names (XS, L, XXXL, AccessibilityXXXL) or full names (UICTContentSizeCategoryXS).

### accessibility localization

Render the current screen across locales including RTL languages.

```bash
xcforge accessibility localization --bundle-id com.app.MyApp
xcforge accessibility localization --locales "en,de,ja,ar,he"
xcforge accessibility localization --locales all
xcforge accessibility localization --threshold 15.0 --settle-time 4.0
xcforge accessibility localization --json
```

| Flag | Description |
|------|-------------|
| `--simulator <name\|udid>` | Simulator name or UDID. Auto-detected from booted simulator |
| `--bundle-id <id>` | App bundle identifier. Auto-detected from last build |
| `--locales <list>` | Comma-separated locale identifiers. Use 'all' for 10 common. Default: en,de,ja,ar,he |
| `--threshold <percent>` | Max allowed diff % from base locale. Default: 10.0 |
| `--settle-time <seconds>` | Wait time after relaunching with new locale. Default: 3.0 |
| `--json` | Machine-readable JSON output |

---

## xcforge plan

Execute multi-step UI automation plans. Two subcommands.

### plan run

Execute a plan from a JSON file or stdin.

```bash
xcforge plan run --file login-flow.json
xcforge plan run --file plan.json --error-strategy continue --timeout 60
xcforge plan run --file plan.json --json
cat plan.json | xcforge plan run --stdin
```

| Flag | Description |
|------|-------------|
| `--file <path>` | Path to JSON file containing plan steps array |
| `--stdin` | Read plan JSON from stdin |
| `--error-strategy <str>` | `abort_with_screenshot` (default), `abort`, `continue` |
| `--timeout <seconds>` | Max execution time. Default: 120 |
| `--json` | Machine-readable JSON output |

### plan decide

Resume a suspended plan with a decision.

```bash
xcforge plan decide --session-id <UUID> --decision accept
xcforge plan decide --session-id <UUID> --decision skip --json
xcforge plan decide --session-id <UUID> --decision abort
```

| Flag | Description |
|------|-------------|
| `--session-id <uuid>` | Session ID from suspended plan run |
| `--decision <str>` | `accept`, `dismiss`, `skip`, `abort`, or freeform |
| `--json` | Machine-readable JSON output |

---

## xcforge pose

Launch an app into a named visual state for rapid design iteration. Internally runs build → install → launch with custom arguments, optionally followed by screenshot.

```bash
xcforge pose dark-theme                          # Build + install + launch with -pose dark-theme
xcforge pose onboarding-step-2                   # Another pose
xcforge pose dark-theme --project MyApp.xcodeproj --scheme MyApp
xcforge pose dark-theme --configuration Release
xcforge pose dark-theme --screenshot /tmp/pose.png  # Capture (waits 1.5s for launch zoom to settle)
xcforge pose dark-theme --screenshot /tmp/pose.png --screenshot-delay 0  # Immediate capture (legacy)
xcforge pose dark-theme --key "--debug-state"    # Custom argument key
xcforge pose dark-theme --key=-NookPose          # `=` form required for values starting with '-'
xcforge pose dark-theme --json
```

| Flag | Description |
|------|-------------|
| `<name>` | **Required** — Pose name to pass to the app |
| `--project <path>` | Path to .xcodeproj or .xcworkspace. Auto-detected if omitted |
| `--scheme <name>` | Xcode scheme name. Auto-detected if omitted |
| `--simulator <name\|udid>` | Simulator name or UDID. Auto-detected if omitted |
| `--configuration <config>` | Build configuration (Debug/Release). Default: Debug |
| `--key <str>` | Argument key to prepend to pose name. Default: `-pose`. Use `--key=-myValue` for values starting with `-` (bare `--key -myValue` is parsed as a missing value). |
| `--screenshot <path>` | Optional file path to capture screenshot after launch |
| `--screenshot-delay <sec>` | Seconds to wait after launch before capturing, so the iOS launch zoom can settle. Default `1.5`; pass `0` for legacy immediate-capture. **Unchanged** when `--wait-for` is not passed. |
| `--wait-for <signal>` | Readiness signal(s), comma-separated (all must hold): `launch-complete`, `a11y:<id>`, `text:<substring>`. Replaces the `--screenshot-delay` poll/sleep with a real element-presence gate (AXP-first, WDA fallback). Capture fires the instant the signal holds — stop racing cold launch onto the splash/Home. Warn-only: never fails the pose. |
| `--timeout <sec>` | Ceiling for `--wait-for`. Default `20`. A high ceiling is free on the fast path. |
| `--json` | Machine-readable JSON output |

```bash
xcforge pose daily-calendar --screenshot /tmp/p.png --wait-for a11y:dailyCalendar.title
xcforge pose home --screenshot /tmp/p.png --wait-for "launch-complete,text:Welcome" --timeout 30
```

**Returns:** Build status, install confirmation, launch status, app PID. If `--screenshot` provided, also returns image data. With `--wait-for`, an unsatisfied gate adds a warning naming the readiness `mode` (`axp` \| `wda` \| `degraded`).

See the [Pose & Visual Iteration](pose.md) reference for app-side routing patterns and visual iteration workflows.

---

## xcforge bless

Save a visual baseline, run tests, compare visual output, and suggest a commit message — all in one call.

```bash
xcforge bless --baseline login-screen --tests "UITests/LoginTests"
xcforge bless --baseline home-dark --tests "SnapshotTests/HomeTests" --project MyApp.xcodeproj
```

| Flag | Description |
|------|-------------|
| `--baseline <name>` | **Required** — Name for the visual baseline |
| `--tests <filter>` | **Required** — Test filter passed to `build-test` (e.g., `MyTarget/MyTests`) |
| `--project <path>` | Auto-detected if omitted |
| `--scheme <name>` | Auto-detected if omitted |
| `--simulator <name\|udid>` | Auto-detected if omitted |

**Steps performed:** save baseline → run tests → compare visual → suggest `[bless] <slug>` commit message.

**Exit code:** 0 when all tests pass and diff is within threshold, 1 otherwise.

---

## Typical CLI Workflows

### TDD Loop
```bash
# Set defaults once
xcforge defaults set --project MyApp.xcodeproj --scheme MyApp --simulator "iPhone 16 Pro"

# Build
xcforge build

# Run tests
xcforge test

# Filter to specific tests
xcforge test --filter "LoginTests/testValidCredentials"

# Agent-optimized output
xcforge test --for agent --gate

# Rerun only failures
xcforge test rerun-failed

# Inspect failures with console output
xcforge test failures --include-console

# Check coverage
xcforge test coverage --min-coverage 80
xcforge test coverage --file LoginViewModel.swift

# Bless a visual baseline + run tests in one call
xcforge bless --baseline login-screen --tests "UITests/LoginTests"
```

### Simulator + App Workflow
```bash
# List and boot
xcforge sim list --filter iPhone
xcforge sim boot "iPhone 16 Pro"

# Build, install, launch (full pipeline)
xcforge build run                                # Builds + boots + installs + launches

# Capture logs while using app
xcforge log start --mode app
# use the app...
xcforge log read
xcforge log read --include network
xcforge log stop

# Screenshot for visual check
xcforge screenshot capture --output ./screenshot.png
```

### UI Automation Workflow
```bash
# Build and launch (full pipeline)
xcforge build run

# Handle permission dialogs
xcforge ui alert --action accept_all

# Find and interact with elements
xcforge ui find --using "accessibility id" --value "emailField"
xcforge ui type --text "user@example.com" --element-id <id>
xcforge ui find --using "accessibility id" --value "Login" --scroll
xcforge ui click --element-id <id>

# Verify result
xcforge screenshot capture
xcforge ui source --format xml
```

### Visual Regression Workflow
```bash
# Save baselines
xcforge screenshot baseline --name login-screen
xcforge screenshot baseline --name home-screen

# Make changes, then compare
xcforge screenshot compare --name login-screen --threshold 1.0
```

### Structured Diagnosis
```bash
xcforge diagnose start                           # → Run ID: abc123
xcforge diagnose build                           # Auto-resolves to active run
xcforge diagnose test
xcforge diagnose runtime --capture-screenshot
xcforge diagnose inspect
xcforge diagnose verify                          # After fix
xcforge diagnose compare --compact               # Agent-friendly summary
xcforge diagnose result
```

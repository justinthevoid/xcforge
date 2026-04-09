# xcforge CLI Commands

xcforge operates in two modes:
- **No arguments** → MCP server mode (stdio transport, 102 tools)
- **With arguments** → CLI mode (ArgumentParser-based terminal commands)

## Mode Detection

```bash
xcforge                    # MCP server mode
xcforge build ...          # CLI mode — 16 command groups
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
```

---

## xcforge build

Build, clean, and inspect Xcode projects. Five subcommands — `run` is the default.

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
xcforge test --json                              # Machine-readable JSON output
```

| Flag | Description |
|------|-------------|
| `--project <path>` | Path to .xcodeproj or .xcworkspace. Auto-detected if omitted |
| `--scheme <name>` | Xcode scheme name. Auto-detected if omitted |
| `--simulator <name\|udid>` | Simulator name or UDID. Auto-detected from booted simulator |
| `--configuration <config>` | Build configuration (Debug/Release). Default: Debug |
| `--testplan <name>` | Test plan name |
| `--filter <pattern>` | Test filter — accepts `testMethod`, `Class/testMethod`, or `Target/Class/testMethod` (target auto-resolved) |
| `--coverage` | Enable code coverage collection |
| `--json` | Machine-readable JSON output |

**Output:** Pass/fail/skip/expected-failure counts, elapsed time, device info, failure summaries with test names, screenshot paths. xcresult path for follow-up commands.

**Exit code:** 0 when all tests pass, 1 when any test fails.

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
xcforge build-test --json                        # Machine-readable JSON
```

| Flag | Description |
|------|-------------|
| `--project <path>` | Auto-detected if omitted |
| `--scheme <name>` | Auto-detected if omitted |
| `--simulator <name\|udid>` | Auto-detected if omitted |
| `--configuration <config>` | Build configuration (Debug/Release). Default: Debug |
| `--testplan <name>` | Test plan name |
| `--filter <pattern>` | Test filter — accepts relaxed formats (auto-resolves target prefix) |
| `--coverage` | Enable code coverage collection |
| `--json` | Machine-readable JSON output |

**Output on build failure:** Build elapsed time, structured errors with file:line, warnings. Tests are NOT run.
**Output on test failure:** Build OK time, test pass/fail counts, failure details, screenshot paths, xcresult path.
**Exit code:** 0 when build and all tests pass, 1 otherwise.

---

## xcforge sim

Manage iOS simulators. 17 subcommands — `list` is the default.

```bash
xcforge sim                                      # Same as `xcforge sim list`
xcforge sim list                                 # List all simulators with state/UDID
xcforge sim list --filter iPhone                 # Filter by name/state
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
xcforge screenshot baseline --name login-screen  # Save as named baseline
xcforge screenshot baseline --name login-screen --baseline-dir ./baselines
xcforge screenshot compare --name login-screen   # Pixel diff against baseline
xcforge screenshot compare --name login-screen --threshold 1.0
```

All subcommands support `--json`. `--format` defaults to png. `--threshold` defaults to 0.5%.

---

## xcforge ui

UI automation via WebDriverAgent. 16 subcommands — `status` is the default.

```bash
xcforge ui status                                # Check WDA health
xcforge ui session                               # Create WDA session
xcforge ui session --bundle-id com.app.id        # Session for specific app
xcforge ui find --using "accessibility id" --value "Save"
xcforge ui find --using "accessibility id" --value "Save" --scroll
xcforge ui find-all --using "class name" --value "XCUIElementTypeButton"
xcforge ui click --element-id <id>
xcforge ui tap --x 200 --y 400
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

# Inspect failures with console output
xcforge test failures --include-console

# Check coverage
xcforge test coverage --min-coverage 80
xcforge test coverage --file LoginViewModel.swift
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

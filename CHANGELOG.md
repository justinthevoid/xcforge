# Changelog

All notable changes to xcforge will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- **Shared-Mac options for every xcodebuild call:** `--derived-data-path`, `--result-bundle-path`, repeatable `--xcodebuild-arg`, `--lock`, `--lock-wait` and `--min-free-gb` on `build compile|run|clean`, `build-test` and `test run|failures|list|rerun-failed`, with matching MCP arguments, env vars and `.xcforge.yaml` keys (`derivedDataPath`, `buildLock`, `artifactDir`, `minFreeGB`). See `Skills/xcforge/references/shared-mac.md`
- **Build lock with a first-come, first-served queue.** Takes the same `flock` as macOS `lockf(1)`, so it queues next to existing `lockf` wrappers. `xcforge lock status` / `build_lock_status` show the holder, the queue and wait times
- `--isolated-sim` / `isolatedSimulator` on `build-test`/`build_and_test` and `test run`/`test_sim`: run on a fresh simulator created for the run and deleted afterwards
- Preflight warnings for low disk and heavy swap before a build
- **Idle timeout for builds and test runs.** xcodebuild is killed after 600s with no output (`--idle-timeout`, `idleTimeoutSeconds`, `XCFORGE_IDLE_TIMEOUT`, `.xcforge.yaml idleTimeout`; 0 disables), so a hung runner is caught without cutting off a slow cold build. Failures say whether the idle or total limit fired (`failureReason: timeout_idle|timeout_total`)
- `test-without-building` is retried once when the test runner never started ("Test runner hung before establishing connection", "Early unexpected exit…", "Failed to launch…" with no test begun)
- `test list --testplan` / `list_tests testplan`: lists via `-test-enumeration-format json`, which includes Swift Testing tests and reports how many the scheme or plan disables
- `test_plan_inspect` shows skipped tests, selected-only targets and every tag filter in the plan, and warns when a multi-tag filter may require all tags
- **UI automation on physical devices.** `xcforge wda start|status|stop` and MCP `wda_start`/`wda_stop` build xcforgeWDA for the device, sign it with your team (`--team`, `XCFORGE_WDA_TEAM`), launch it with `test-without-building`, find it over the CoreDevice tunnel, and record its URL in `~/.xcforge/wda/`. `XCFORGE_DEVICE=<udid>` points `xcforge ui` commands at it. Locked device, UI Automation off, Developer Mode off, pairing and signing failures each get a one-line explanation
- `device screenshot` / `device_screenshot` (devicectl capture, falling back to the device's WDA)
- `device launch --url <deep-link> --env KEY=VALUE --arg A` and matching `url`/`env` on `device_launch`
- **MCP progress notifications.** When a `tools/call` carries a `progressToken`, xcforge sends `notifications/progress` every 10s with the elapsed time and the latest output line, so clients that time out silent requests keep waiting for long builds and tests
- Each build and test tool result ends with `project: <absolute path>`, so a build of the wrong checkout or worktree is visible
- `.xcforge.yaml` problems (unknown keys with a "did you mean", unparseable values) are listed by `set_defaults show` / `defaults show` and once at the end of the first tool result that uses the file
- **Xcode 27 Device Hub support.** xcforge opens Device Hub when the selected Xcode has no Simulator.app, and screen capture, the accessibility bridge and window scripting accept either app
- **Test run options:** `retries`, `iterations`, `untilFailure`, `parallel`, `testTimeoutSeconds`, `skipBuild`, `includeConsole`, `env` and `timeoutSeconds` on `test_sim` and `build_and_test`, with matching flags (`--retries`, `--iterations`, `--until-failure`, `--parallel/--no-parallel`, `--test-timeout`, `--no-build`, `--include-console`, `--env`, `--timeout-seconds`) on `test run`, `build-test` and `test rerun-failed`
- Tests that fail and then pass on retry are listed as flaky (`flaky` in agent JSON)
- `test rerun-failed` reuses the recorded project, test plan, configuration and env, and skips build-for-testing when no source file changed since the last one (`--build` forces it)
- **Launches report a crash at startup.** `launch_app`, `build_run_sim`, `sim launch` and `build run` check the app is still running 2s after launch; when it isn't, they fail with the exception, reason, crashed thread's top frames and the `.ips` report path
- Launch arguments, environment and a deep link: `args`, `env` (KEY=VALUE), `url` and `terminate` on `launch_app` and `build_run_sim`; `--arg`, `--env`, `--url` and `--no-terminate` on `sim launch` and `build run`; `--env` on `console launch`
- `open_url` / `sim openurl` open a URL or deep link on a simulator
- `clean` / `build clean` take `configuration` and `derivedData: true` / `--derived-data`, which deletes this project's DerivedData folder (and only that one)
- **Every UI tool takes `simulator`, and each simulator has its own WebDriverAgent** on its own port (8100 up, saved in `~/.xcforge/wda/simulator-ports.json`), so with two simulators booted the screenshot and the taps hit the same one. `XCFORGE_SIMULATOR` does the same for CLI `ui` commands
- **Actions can wait for the result:** `wait_for`, `until_gone` and `timeout` on taps, swipes, typing and `find_element`, instead of sleeps
- `find_element` reports how many elements matched, with each one's label and frame, and takes `index`
- `type_text` types into the focused field; `key` sends return, delete, tab and other named keys, `dismiss_keyboard` hides the keyboard, and `secure` keeps the text out of the result (`ui type --key`, `--dismiss-keyboard`, `--secure`)
- `alert_action` (accept/dismiss) on `wda_create_session` and `XCFORGE_ALERT_ACTION` let permission alerts be handled automatically; "not found" errors mention a visible alert
- `screenshot` takes `crop` (x,y,width,height in device points) and `max_dimension` (longest side in pixels, with how many points one pixel covers); `screenshot capture --crop`, `--max-dimension`
- Simulator setup tools: `sim_content_size`, `sim_locale`, `app_container`, `sim_push` and `sim_privacy` (grant/revoke/reset), and `sim content-size|locale|container|push|privacy`. Setters report the value they replaced

- **`build typecheck <target>` / `build_typecheck`** compiles one target for the simulator (its own scheme when it has one, else `-target` in the project that defines it), reusing the workspace's DerivedData
- **`--from-snapshot` / `fromSnapshot`** on `build compile` and `build typecheck` builds a snapshot of the working tree (a git worktree per repo under `~/.xcforge/snapshots`, `XCFORGE_SNAPSHOT_DIR`), so edits other agents make mid-build don't break it. Errors name the real files
- **`lsp setup` / `lsp_setup`** writes `buildServer.json` with xcode-build-server and points its `build_root` at the DerivedData xcforge builds into, so SourceKit-LSP stops reporting "No such module"
- `--jobs` / `jobs` (also `XCFORGE_JOBS`, `.xcforge.yaml jobs`) passes `-jobs N` to compiling xcodebuild calls and `-j N` to SwiftPM
- `--all-errors` / `allErrors` builds in a separate diagnostic DerivedData slot (`diagnosticDerivedDataPath`, `XCFORGE_DIAGNOSTIC_DERIVED_DATA_PATH`; default a per-project folder beside Xcode's) and keeps going after errors, leaving the main cache alone
- **SwiftPM tools find the package:** `path`, then `.xcforge.yaml packagePath`, then the current folder, then the only `Package.swift` in the repo. `swift_package_build`/`swift_package_test` results list compiler errors with file:line, failing tests (XCTest and Swift Testing) and test counts, keeping only the end of the raw output when nothing parses. They take the build lock and the idle timeout

- `test_sim` takes `rerunFailed`: the MCP form of `test rerun-failed`, reusing the last run's settings and skipping the build when nothing changed
- **`XCFORGE_TOOL_GROUPS` and `.xcforge.yaml toolGroups`** pick the tool groups the server lists at start (`+diagnose`, `-git`, `build,test,ui`, `all`), and `tool_groups` changes now send `notifications/tools/list_changed`
- Read-only tools carry `readOnlyHint`, so clients can run them without asking
- `xcforge --version`
- `plan decide` works from the CLI: `plan run` saves a suspended plan to `~/.xcforge/plan-sessions/` for an hour, and the time spent waiting for the decision doesn't count against the plan's timeout

### Changed
- **Merged tools.** `tap` replaces `click_element`, `tap_by_id`, `tap_by`, `tap_coordinates`, `double_tap`, `long_press`, `ui_tap_pixel` and `indigo_tap`; `swipe` takes `hid` (was `indigo_swipe`), `get_source` takes `format: list` (was `list_elements`), `find_element` takes `all` (was `find_elements`), and `screenshot` takes `device` (was `device_screenshot`). The old names are no longer listed but still work for one release, with a note naming the replacement
- **The diagnose workflow tools are off by default** (`XCFORGE_TOOL_GROUPS=+diagnose` or `tool_groups` turns them on); calling one while off says how. The server lists 104 tools instead of 118
- **Every argument is listed in camelCase** (`includeConsole`, `waitFor`, `elementId`); snake_case spellings are still accepted
- **Build and test tools return compact JSON by default over MCP** (`build_compile`, `build_sim`, `build_typecheck`, `test_sim`, `build_and_test`): `ok`, `summary`, errors with full paths, the result bundle. `for: "human"` gives the text report. Diagnose and plan JSON are no longer indented
- `defaults set` finds the project before saving and exits non-zero when nothing was saved; it used to print success without writing in a fresh process
- A saved default simulator that no longer exists is ignored with a warning instead of failing the build
- Last build and test records are keyed on the absolute, symlink-resolved project path (a relative `App.xcodeproj` in two worktrees no longer shares one record) and written under a lock
- CLI JSON errors go to stdout like JSON results
- **One test ID format.** Results, `list_tests`, last-failures and known-failures all use `Target/Suite/test()` (Swift Testing) or `Target/Class/testMethod` (XCTest), and filters accept it as printed. The target is added to short IDs from the scheme's or test plan's test targets instead of guessed, and the `test()()` spelling xcodebuild needs is written for you
- Failures carry every message with file and line, the argument or repetition it came from, and their attachments; identical messages are grouped, and text output is capped at 20 failures with a count of the rest
- A test failure is no longer reported as "test target build failed". When the build or runner fails before any test reports, agent JSON says why (`reason`) and `rerun-failed` refuses instead of running nothing
- Agent JSON `failed` counts every failure, not only the ones listed
- Agent JSON includes the result bundle (`xcresult`) and, for a timed-out run, which limit fired and how to raise it (`reason`), even when some failures were read
- CLI `test run` shows a failed test build as compile errors with file and line, not as failing tests
- `test failures` / `test_failures` never run tests: without `xcresultPath` they read the project's last test run, say so when there is none, and return the compile errors when that run's build-for-testing failed (instead of the previous run's failures)
- build-for-testing uses the test plan and, for a filter whose IDs all name a test target, builds only those targets
- `build compile`, build-for-testing, `test` and `test list` pass the same build flags, so switching between them doesn't rebuild everything
- The hang watchdog samples at 300s and 540s instead of 60s and 120s, and a snapshot is only reported for a timeout or `diagnose`
- `build compile` / `build_compile` skip the `-showBuildSettings` call and no longer need a booted simulator (they compile for a booted one if any, else the newest iPhone simulator)
- Simulator names resolve the same way everywhere: exact name, the booted match first, else the newest OS; two matches on the same OS ask for a UDID. Prefix matches (`iPhone 16` → `iPhone 16 Pro`) are gone
- A filter that matches no test lists suggestions from the last build instead of building again
- `build run` exits non-zero when the app wasn't launched
- `build_run_sim` boots the simulator once the build succeeds (not alongside it), waits for the boot to finish before installing, and installs the scheme's application target from `-showBuildSettings -json` instead of whichever product was listed last or a `<scheme>.app` found anywhere in DerivedData
- **CLI log and console capture run in the background.** `log start` and `console launch` keep streaming to `~/.xcforge/capture/` after the command exits (`XCFORGE_CAPTURE_DIR` moves it), so `log read`, `log wait`, `console read` and the `stop` commands in later invocations see it. Before, the capture died with the `start` command
- `read_logs`, `read_app_console`, `log read` and `console read` return the newest 200 lines by default (`last: 0` for all) and say how many earlier lines were left out; over-long output keeps the end instead of the start
- `wait_for_log` no longer clears the buffer `read_logs` reads
- The `crashes` log topic matches error and fault lines; it used to match default-level (`Df`) lines, which is most of the log
- Auto-detect ignores the `project.xcworkspace` inside every `.xcodeproj`, picks the scheme named after the project (or the only non-test scheme) when there are several, and gives `xcodebuild -list` 60s instead of 15s
- `clean` cleans the configuration and simulator build folder xcforge builds into, and is limited by the idle timeout instead of a fixed 60s
- A new CLI process picks up the last build's bundle ID and app path, so `sim launch` and `sim install` work right after `build run` without passing them
- **Cancelling stops the build.** An MCP cancel, a client disconnect, Ctrl-C, SIGTERM or SIGHUP now stops the xcodebuild (or other command) xcforge started, together with every process it spawned. Timeouts kill the whole process tree too, so compiler and test-runner children no longer outlive the call and hold DerivedData ("database is locked" on the next run)
- Two MCP calls that would run xcodebuild on the same DerivedData folder (or the same project's default one) at once now run one after the other, first come first served
- An explicit `project` in another repo or worktree uses the `.xcforge.yaml` next to it, for both session defaults (scheme, simulator, test plan) and xcodebuild options (DerivedData, lock, idle timeout)
- `.xcforge.yaml` values may be quoted and may carry a trailing `# comment`
- **Unknown MCP arguments are an error** naming the closest real argument (`derived_data_path` → `derivedDataPath`) instead of being ignored
- **Auto-promotion is opt-in.** Repeated explicit values no longer silently become session defaults unless `.xcforge.yaml` sets `autoPromote: true`
- `--no-default-flags` / `defaultFlags: false` / `XCFORGE_DEFAULT_FLAGS=0` / `.xcforge.yaml defaultFlags: false` drop the flags xcforge adds to builds (`-skipMacroValidation`, `-parallelizeTargets`, `COMPILATION_CACHE_ENABLE_CACHING=YES`)
- `lldb_continue` / `debug continue` wait 30s by default and take `timeoutSeconds` / `--timeout` (was a fixed 10s); simulator app launch waits up to 60s (was 15s)
- `bless` no longer prints a suggested commit message
- Tool descriptions and the skill drop "preferred", "call this first" and marketing copy; pitfalls are stated as facts rather than rules
- UI tools no longer run simulator recovery (terminate, rebuild, redeploy) when WDA is on a physical device; they report `device_runner_not_reachable` and point at `wda start`
- xcforgeWDA's iOS deployment target is 15.0 (Xcode 27 no longer builds for 13)
- devicectl output is read from Xcode 27's `properties` dictionary as well as the older split keys; `device info` adds tunnel, pairing and Developer Mode state
- **Default total time limit for builds and tests is 1800s** (was 180s); `--long` / `long: true` raises it to 7200s. Hangs are caught by the idle timeout instead
- **Builds continue after the first error** (`-IDEBuildingContinueBuildingAfterErrors=YES`), so one run reports every error. Opt out with `--no-continue-after-errors` / `continueAfterErrors: false`
- Build errors are read from stdout as well as stderr (xcodebuild prints compiler diagnostics on stdout), duplicates are dropped, and up to 50 are shown
- A run where zero tests executed is a failure even without a filter, when xcforge could read the result summary
- `build-test` and `test rerun-failed` honour `.xcforge.yaml` `testPlan` and `configuration` like `test run` does
- Coverage lookups use `xccov --only-targets` when only a yes/no is needed, and fall back to per-target coverage instead of truncated JSON for very large reports
- **`simRecovery` defaults to `off` everywhere** (was `auto` for `build_and_test`, `build-test` and `bless`). `auto` now only reboots; erasing a simulator needs the new `erase` mode. Invalid values are an error instead of silently becoming `auto`. `build-test` gains `--sim-recovery`
- Result bundles and diagnostic snapshots get collision-free names (`xcf-<prefix>-<ts>-<pid>-<rand>`), so two sessions starting in the same second no longer delete each other's bundles. `XCFORGE_ARTIFACT_DIR` / `artifactDir` moves them out of `/tmp`
- `build diagnose`, `test failures` and `test coverage` read this project's last recorded result bundle instead of the newest bundle any session left in `/tmp`. `test failures` without `--xcresult-path` reuses that bundle instead of re-running the whole suite
- `list_elements` and `get_source` drop wrapper containers, hidden and off-screen elements, and add `value`, `disabled` and `selected`
- `get_source` and `list_elements` start WebDriverAgent when it isn't running, and fail clearly instead of reading the Simulator app's own accessibility tree
- Screenshots report the device's point size, not the Simulator window's, and the fallback writes a new file per capture instead of one shared `/tmp` file; CLI `screenshot capture` writes a new file unless `--output` is given

### Fixed
- With Xcode 27, `device list` (and anything resolving a phone by name) no longer lists simulators, which Device Hub's `devicectl` now includes, and the state column shows the tunnel state (connected, disconnected, unavailable) instead of `devicectl`'s display hint
- A timed-out `build-for-testing` is reported as a build failure instead of continuing to `test-without-building` against stale products
- `test_plan_inspect` finds plans inside `App.xcodeproj/xcshareddata/xctestplans` and decodes Xcode's string-form `skippedTests` and plans with missing sections
- A hung build's fallback no longer runs `pkill -x xcodebuild`, which killed every session's build on the Mac. Hang snapshots sample the xcodebuild matched by this run's result bundle path instead of the newest xcodebuild on the system
- WDA port cleanup only kills WebDriverAgent runner processes, uses the port from `WDA_BASE_URL`, skips remote WDA hosts, and calls `lsof` at its real path (`/usr/sbin/lsof`)
- A WebDriverAgent session recreated after a hiccup no longer relaunches the app (`forceAppLaunch: false`)
- Restarting xcforgeWDA reruns its last build with `test-without-building` instead of opening the runner app (which never starts the server), so recovery no longer falls through to a full rebuild; the runner is no longer stopped after an hour
- The accessibility-tree fast path is used only with exactly one simulator booted and no device attached, and reads that simulator's windows, not Simulator's menus
- Coordinate taps and swipes (`indigo_tap`, `indigo_swipe`, plan steps) account for landscape and upside-down orientation
- `accessibility_check`, `localization_check` and `multi_device_check` put back the text size, language and appearance they found instead of resetting to large, the first locale and light

## [1.6.1] - 2026-05-19

### Fixed
- **Cross-project bundle/app-path bleed.** Building App A then switching to App B's directory no longer launches or tests A's built product. `~/.xcforge/defaults.json` now uses a v2 envelope keyed by canonical project path; each project gets an isolated record, and builds write only into the active project's slot. The global "persisted project" fallback (the contamination source) is removed — project identity comes from explicit arg, `.xcforge.yaml`, or cwd auto-detect. `bundleId`/`appPath`/`buildScheme` only ever resolve from the active project's record
- `profile_switch` now clears the in-memory build-info caches and reloads the new project's record before returning — previously, switching profiles silently retained the previous project's `bundleId`/`appPath`, reintroducing the bleed
- Auto-promotion is no longer "sticky after the fact": `set_defaults` resets the matching streak counter so an old explicit value cannot immediately re-promote after you override it, and the streak is suppressed when `autoPromote: false`
- Explicit `timeoutSeconds: 0` / negative on `test_sim`/`build_and_test` no longer produces a 0-second watchdog; falls through to the configured default with a warning (matches the `.xcforge.yaml` parser's guard)
- `xcforge defaults clear` (without `--all`) now auto-resolves the active project before clearing instead of silently no-op'ing on disk while telling the user defaults were cleared
- `set_defaults` / `profile_switch` warn loudly when no active project is resolved instead of silently applying in-memory only

### Added
- `.xcforge.yaml` `testTimeout:` key — per-project default test timeout in seconds (positive integer). Precedence: explicit `timeoutSeconds` > `.xcforge.yaml testTimeout` > `--long`/180s default. Non-positive values are rejected on both paths with a warning
- `.xcforge.yaml` `autoPromote:` key (`true`/`false`, default `true`) — opt out of the 3-rep auto-promotion of explicit values to session defaults. Useful for repeated iterative test runs where stickiness is unwanted
- `xcforge defaults clear --all` — wipe every project's record (the per-project default `clear` only touches the active project's slot)
- `defaults show` now surfaces the active project key, `testTimeout`/`autoPromote` from `.xcforge.yaml` when set, and an explicit notice when any value was auto-promoted

### Changed
- On-disk `~/.xcforge/defaults.json` upgraded to a v2 envelope (`{version: 2, projects: {<canonical-path>: PersistedDefaults}}`). Old flat files with a `project:` field auto-migrate on first read; unrecognized or forward-version (`v3+`) files are backed up to `defaults.json.unrecognized-<timestamp>` instead of being overwritten
- Canonical project keys now case-fold on case-insensitive APFS volumes, NFC-normalize unicode, and resolve symlinks — `~/work/MyApp` reached via two casings or two symlink paths is now one record instead of two
- v1→v2 migration uses a two-phase POSIX lock (shared read decides format; exclusive re-acquired before the rewrite) so two concurrent processes can't race the migration write

## [1.6.0] - 2026-05-19

### Added
- `xcforge init` (CLI) — scaffold a documented, repo-scoped `.xcforge.yaml` at the git repo root (CWD if no repo); refuses to overwrite an existing file without `--force` (exits non-zero). CLI-only; no MCP `init` tool
- `.xcforge.yaml` `configuration:` key — build configuration for `build_sim`/`build_compile`/`build_run_sim`/`test_sim`/`build_and_test`/`build_and_diagnose` when no `configuration` argument is given
- `.xcforge.yaml` `testPlan:` key — default `.xctestplan` for `test_sim`/`build_and_test` when no `testplan` argument is given
- `xcforge wait-ready` (CLI) / `wait_ready` (MCP) — WDA-independent launch/element readiness probe (AXP-first → WDA fallback → reported degraded); stops racing cold-launch and deep-link navigation
- Additive `--wait-for` / `--timeout` flags on `pose` and `screenshot capture` (default pose/screenshot timing is unchanged when the new flags are not passed)
- `appForeground` (`Bool?`, derived from WDA's active `CFBundleIdentifier`; `null` when WDA is unreachable) added to `tap-by-id`/`tap-by`/`click`/`find`/`screenshot` results

### Changed
- **Repo config now outranks machine-global persisted defaults.** Parameter resolution order is now `explicit → in-session (set_defaults/profile_switch/auto-promoted) → .xcforge.yaml → ~/.xcforge/defaults.json → auto-detect`. Previously the machine-global `~/.xcforge/defaults.json` overrode a committed `.xcforge.yaml`, making the repo file effectively inert. `set_defaults`/`profile_switch` still take effect within the running session but no longer silently win over a repo file that sets the same field across restarts
- `configuration`/`testPlan` are repo-only — never written to `~/.xcforge/defaults.json` or named profiles (new `RepoConfig.Values` type, decoupled from the persisted model)
- `set_defaults action: clear` now states that a repo `.xcforge.yaml` still applies instead of claiming pure auto-detection
- `ui session` creation failures now emit a structured `error` / `cause` / `detail` / `remediation` envelope with a bounded one-shot auto-heal (`--no-autoheal` restores fail-fast, `--relaunch-app` is opt-in) instead of the opaque `Session creation failed: ExitCode(rawValue: 1)`

### Fixed
- `resolveBundleId`/`resolveAppPath` no longer return a stale bundle id / app path from a different scheme's build when the scheme has not been resolved yet this session — the build-scheme mismatch guard now consults the effective scheme (session → repo → persisted)
- Auto-bootstrapped WDA sessions stay bound to the app under test across recreates instead of routing queries to Springboard, so `pose` → readiness → screenshot loops no longer silently target the wrong app

## [1.5.0] - 2026-05-12

### Added
- `xcforge bless` — baseline + test + diff in one call (verb form of the bless workflow)
- Agent-trust test signal — terse agent-optimized test output, `xcforge test --gate` (subtract known-failures from the pass/fail signal without hiding the raw list), and `xcforge test rerun-failed` to replay exactly the last run's failing IDs
- `xcforge test plan inspect` — parse and summarize a `.xctestplan` (configurations, defaultOptions, test targets, skipped-test counts) without running tests
- `xcforge build-test --env KEY=VAL` — inject environment variables into the test process, with automatic `TEST_RUNNER_` prefixing

### Changed
- Test filter mismatches now return a "did you mean?" suggestion instead of a bare zero-match result
- Test git-hook invocations retry transient failures

## [1.4.6] - 2026-05-10

### Fixed
- `ui ls --source wda` no longer backgrounds the app after a `pose` — `WDAClient` learns the launched app's bundle id (from both the `pose` and generic `launch_app`/`build_run_sim` paths) and re-targets it on every implicit session creation; switching bundles invalidates the cached session so the next request rebinds
- `pose --screenshot-delay` is now a wallclock ceiling, not a fixed sleep — polls WDA's `verifyActiveBundleId` at ~150ms cadence and captures as soon as the launched bundle is foreground, falling back to sleeping the residual budget when WDA is unreachable; honors `Task.isCancelled`. Default raised 1.5s → 2.5s; `--screenshot-delay 0` preserves legacy immediate capture

## [1.4.3] - 2026-05-10

### Changed
- **Homebrew now ships a prebuilt arm64 binary plus the bundled `xcforgeWDA` fork** — install drops from ~2 min (build from source) to ~5s, and Xcode is no longer required at install time (still required at runtime when a UI-automation tool first builds the WebDriverAgent runner)
- `xcforgeWDA` fork vendored in-tree so the v1.4.2 SwiftUI-sheet visibility patches reach Homebrew users (the formula previously fell back to upstream Facebook WDA, which has none of the multi-window patches); see `xcforgeWDA/UPSTREAM.md`
- `AgentClient` resolves the WDA project from `/opt/homebrew/share/xcforge/xcforgeWDA` (and `/usr/local/share/xcforge/xcforgeWDA` for Intel) in addition to `$XCFORGE_WDA_DIR` and CWD-relative paths

## [1.4.2] - 2026-05-10

### Fixed
- WDA can now see and tap content inside SwiftUI `.sheet` windows. The vendored WDA fork traverses every application window when `windows.count > 1`: source dumps merge per-window snapshots under a synthetic Application root; element find retries each window when the keyWindow result is empty (with dedup); coordinate taps re-root on the topmost hittable window. All multi-window logic is gated on `windows.count > 1`, so single-window apps remain byte-identical

## [1.4.1] - 2026-05-09

### Fixed
- WDA can now see SwiftUI sheets, alerts, and `fullScreenCover` — `WDAClient` remembers `activeBundleId` across recreates so auto-bootstrapped sessions stay bound to the app under test
- `xcforge ui session --bundle-id <id>` verifies the binding via `GET /session/<sid>` and exits non-zero on mismatch instead of reporting silent success
- `xcforge ui ls` no longer returns Simulator.app's macOS chrome when an iOS sim is booted; new `--source {auto,wda,axp}` option (`auto` prefers WDA when a sim is booted)
- `xcforge pose --screenshot` no longer captures mid-launch animation; new `--screenshot-delay <sec>` option (default `1.5`, `0` = legacy immediate capture)
- Stale persisted defaults no longer fail the first run — `DefaultsStore.load()` drops `project`/`appPath` entries whose paths no longer exist so autodetect wins
- `pose --key` help documents the `--key=-myValue` form required for values starting with `-`

### Added
- `xcforge ui ls --source {auto,wda,axp}`
- `xcforge pose --screenshot-delay <sec>`

## [1.4.0] - 2026-05-09

### Added
- `build compile` (CLI) / `build_compile` (MCP) — fast compile-only build (~5s) with no install/launch
- `sim info` (CLI) / `sim_info` (MCP) — returns booted simulator screen size, pixel size, and scale
- `ui tap-pixel` (CLI) / `ui_tap_pixel` (MCP) — tap simulator UI using pixel coordinates (auto-converts to points via screen scale)
- `screenshot --grid` flag — overlays point-coordinate grid on captured PNG for visual iteration
- `pose <name>` (CLI) / `pose` (MCP) — build, install, and launch app with `<key> <name>` appended to the launch argv (default key `-pose`); apps with a debug router that reads `ProcessInfo.arguments` can deep-link into a screen
- Extended `executeLaunchApp` and `launchAppStructured` with optional launch arguments (default `nil` keeps all existing call sites unchanged)

### Hardened
- `fetchScreenInfo` rejects non-finite scale, scale below 0.5, and non-positive widths/heights to prevent silent (0,0) taps and runaway grid-overlay loops on corrupt simulator metadata
- `screenshot --grid` skips `mkdir` when `--output` has no parent directory; grid-overlay allocation failure now propagates to the existing ungridded fallback warning instead of silently returning the source image
- `pose` rejects empty/whitespace-only screen names early with a clear error
- `ui tap-pixel` error on missing screen scale now suggests falling back to `ui tap` with point coordinates

## [1.3.2] - 2026-04-12

### Fixed
- `indigo_tap` and `indigo_swipe` no longer crash the MCP server when called — unsafe `UnsafeMutablePointer<NSError?>` arguments were being passed as `AnyObject` through `NSObject.perform()`, causing memory corruption in CoreSimulator's private API
- Same crash fixed in `CoreSimCapture` (used by screenshot/capture tools) which shared the identical pattern

## [1.3.1] - 2026-04-10

### Fixed
- Surface test-target build errors in test pipeline responses instead of silently returning zero-count empty results
- `buildFailed` flag and `buildDiagnostics` added to `TestExecution` to distinguish "build failed" from "no tests matched"
- `test_sim` MCP handler now detects and reports test-target compilation failures with structured diagnostics

## [1.3.0] - 2026-04-09

### Fixed
- Swift Testing filter workaround: append `()` to preserve method identifiers stripped by xcodebuild
- Test filter returning zero matches now correctly treated as failure instead of false success
- Prevent double-prepending test target prefix when first component already matches a known target

## [1.2.0] - 2026-04-09

### Added
- `build run` full pipeline: build + boot + install + launch in a single command
- Structured build diagnostics always extracted from xcresult bundles
- Agent-friendly diagnose CLI output for automated workflows

### Fixed
- Consistent `BuildRunResult` shape for build-failure JSON paths
- Hardened build run pipeline JSON output and persistence edge cases

### Changed
- Unified run-ID resolution; fixed false build regression on warning increase
- Updated skill references and website docs for build-run pipeline and diagnose improvements

## [1.1.1] - 2026-04-08

### Fixed
- JSON encoders now use `.withoutEscapingSlashes` for cleaner output
- Added missing `runAsyncJSON` helper and silenced unused-variable warnings

### Changed
- Overhauled website: redesigned homepage, improved SEO, accessibility hardening
- Refreshed Starlight documentation site for CLI and MCP tools
- Simplified web build pipeline with Playwright e2e test setup

## [1.1.0] - 2026-04-04

### Added
- LLDB debugger integration: 8 MCP tools and CLI commands for attaching, evaluating expressions, setting breakpoints, reading memory, and inspecting stack frames
- xcforge Claude Code skill installable via `npx @anthropic-ai/claude-code/skills`

### Fixed
- `shouldOutputJSON` adopted across all command families — JSON output now consistently routes errors to stderr
- Validation guard errors in `PlanDecide` and `UIDrag` now route through `shouldOutputJSON`

### Changed
- Suggest `xcforge build clean` automatically on infrastructure failure patterns
- Raised `outputLimit` cap for `xccov full-report` to handle large coverage output
- Improved MCP tool descriptions and server metadata

## [1.0.0] - 2026-04-04

### Added
- 102 MCP tools across 17 categories
- 16 CLI command groups mirroring MCP tools
- Build and test with structured xcresult parsing
- UI automation via WebDriverAgent + native AX bridge (AXPBridge)
- Framebuffer screenshots via CoreSimulator IOSurface (~300ms)
- 4-layer log filtering with 8 topic categories
- Physical device support via devicectl
- Swift Package Manager tools
- Accessibility auditing tools
- Visual regression with pixel-diff baselines
- Multi-device visual checks (Dark Mode, Landscape, iPad)
- 10-step diagnosis workflows
- Plan execution engine with assertions
- Repo-level `.xcforge.yaml` configuration
- Session profiles and persistent defaults
- Dual-mode binary: MCP server (no args) or CLI (with args)

# Changelog

All notable changes to xcforge will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

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

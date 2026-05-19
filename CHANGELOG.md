# Changelog

All notable changes to xcforge will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.6.0] - 2026-05-19

### Added
- `xcforge init` (CLI) — scaffold a documented, repo-scoped `.xcforge.yaml` at the git repo root (CWD if no repo); refuses to overwrite an existing file without `--force` (exits non-zero). CLI-only; no MCP `init` tool
- `.xcforge.yaml` `configuration:` key — build configuration for `build_sim`/`build_compile`/`build_run_sim`/`test_sim`/`build_and_test`/`build_and_diagnose` when no `configuration` argument is given
- `.xcforge.yaml` `testPlan:` key — default `.xctestplan` for `test_sim`/`build_and_test` when no `testplan` argument is given

### Changed
- **Repo config now outranks machine-global persisted defaults.** Parameter resolution order is now `explicit → in-session (set_defaults/profile_switch/auto-promoted) → .xcforge.yaml → ~/.xcforge/defaults.json → auto-detect`. Previously the machine-global `~/.xcforge/defaults.json` overrode a committed `.xcforge.yaml`, making the repo file effectively inert. `set_defaults`/`profile_switch` still take effect within the running session but no longer silently win over a repo file that sets the same field across restarts
- `configuration`/`testPlan` are repo-only — never written to `~/.xcforge/defaults.json` or named profiles (new `RepoConfig.Values` type, decoupled from the persisted model)
- `set_defaults action: clear` now states that a repo `.xcforge.yaml` still applies instead of claiming pure auto-detection

### Fixed
- `resolveBundleId`/`resolveAppPath` no longer return a stale bundle id / app path from a different scheme's build when the scheme has not been resolved yet this session — the build-scheme mismatch guard now consults the effective scheme (session → repo → persisted)

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

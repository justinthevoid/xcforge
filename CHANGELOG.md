# Changelog

All notable changes to xcforge will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

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

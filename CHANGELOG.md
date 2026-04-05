# Changelog

All notable changes to xcforge will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

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
- 95 MCP tools across 15 categories
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

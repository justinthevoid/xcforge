# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test Commands

```bash
swift build                  # Debug build
swift build -c release       # Release build (~8 MB stripped)
swift test                   # Run all tests
swift test --filter TestName # Run a single test suite
swift run xcforge             # Start MCP server (stdio JSON-RPC)
swift run xcforge build --help # CLI mode
```

**Formatting** (CI enforces strict lint):
```bash
swift-format format --in-place --recursive Sources/ Tests/  # Fix
swift format lint --strict --recursive Sources/ Tests/       # Check (matches CI)
```

**Web site** (separate workspace in `Web/`, uses Bun — not npm):
```bash
cd Web && bun install && bun run build   # Full build with validation
bun run dev                               # Local dev at localhost:4321
bun run lint && bun run format            # Biome lint/format
```

## Architecture

**Dual-mode single binary**: no args → MCP server (stdio JSON-RPC); with args → CLI (ArgumentParser). Mode detection in `Sources/XCForgeCLI/Main.swift`.

**Two targets** (see `Package.swift`):
- `XCForgeKit` — shared library containing all 102+ MCP tools
- `XCForgeCLI` — CLI layer wrapping the library with ArgumentParser commands

### Tool Provider System

Tools are organized into **providers** that implement `ProviderProtocol` and self-register in `ProviderRegistry`. Each provider owns its tool definitions + dispatch logic. There is no central switch statement.

Key providers in `Sources/XCForgeKit/Tools/`: `BuildProvider`, `TestProvider`, `SimulatorProvider`, `InteractionProvider`, `LogProvider`, `DeviceProvider`, `DebuggerProvider`, `VisualTools`, `AccessibilityTools`, `GitProvider`, `SwiftPackageProvider`, `DiagnoseTools`, `PlanTools`, `MultiDeviceTools`, `ConsoleProvider`, `CaptureProvider`.

### Dependency Injection

All external I/O flows through `Environment` (defined in `XCForgeKit/Support/`), which carries injectable dependencies: `ShellExecutor` for subprocess execution, file operations, session state. Tests mock these — never call `Process` directly, use `ProcessRunner`.

### CLI ↔ MCP Naming Convention

MCP tools use snake_case (`build_sim`, `ui_tap`). CLI commands mirror them as subcommands (`xcforge build`, `xcforge ui tap`). Each CLI command group in `Sources/XCForgeCLI/Commands/` has a matching provider.

### Multi-Step Workflows

- **Diagnosis workflows** (`XCForgeKit/Workflow/`): 10 chained steps with evidence collection
- **Plan execution** (`XCForgeKit/Plan/`): step binding + assertion engine via `RunEngine`

## Code Conventions

- **Swift 6.0 strict concurrency** — no `@unchecked Sendable` without justification
- **async/await only** — no completion handler callbacks
- **Formatting**: swift-format, 120 char lines, 2-space indent (see `.swift-format`)
- **Commit style**: conventional commits (`feat:`, `fix:`, `refactor:`, `test:`, `docs:`)
- **Tool responses**: structured and concise — agents pay per token

## Adding a New Tool

1. Create/extend a provider in `Sources/XCForgeKit/Tools/`
2. Register it in `ProviderRegistry`
3. Add a matching CLI command in `Sources/XCForgeCLI/Commands/`
4. Add tests in `Tests/XCForgeKitTests/`
5. Update skill reference in `.claude/skills/xcforge/references/`

## Dependencies

Swift: `modelcontextprotocol/swift-sdk` (MCP types), `apple/swift-log`, `apple/swift-argument-parser`. Linked framework: `ScreenCaptureKit`. No external runtime dependencies beyond Xcode/Swift.

## Web Site

Astro Starlight + Svelte, deployed to Cloudflare Workers. Linted with Biome (not ESLint). E2E tests via Playwright. All commands use `bun` (not `npm`).

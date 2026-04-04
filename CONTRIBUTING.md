# Contributing to xcforge

Thanks for your interest in contributing. This guide covers everything you need to get started.

## Getting Started

### Prerequisites

- macOS 13+
- Xcode 15+
- Swift 6.0+

### Building

```bash
git clone https://github.com/justinthevoid/xcforge.git
cd xcforge
swift build
lefthook install   # sets up pre-push formatting check
```

### Running Tests

```bash
swift test
```

### Running Locally

```bash
swift run xcforge build --help    # CLI mode
swift run xcforge                 # MCP server mode (expects stdio JSON-RPC)
```

## Project Structure

```
Sources/
  XCForgeKit/          # Shared library — all 95 tools live here
    Tools/             # Tool providers (BuildProvider, TestProvider, etc.)
    Clients/           # WDA client, AXPBridge, CoreSimulator, IndigoHID
    Support/           # ProcessRunner, ProjectResolver, extensions
    Workflow/          # Diagnosis workflow steps
    Plan/              # Plan execution engine
    Persistence/       # DefaultsStore, RunStore
    Contracts/         # Workflow data contracts
  XCForgeCLI/          # CLI layer — ArgumentParser commands
    Commands/          # One subfolder per command group (Build/, Test/, Sim/, etc.)
    Support/           # Shared CLI helpers
Tests/
  XCForgeKitTests/     # Unit and integration tests
```

## How to Contribute

### Reporting Bugs

Open an issue with:
- What you expected to happen
- What actually happened
- Steps to reproduce
- macOS version, Xcode version, and xcforge version (`xcforge --version`)

### Suggesting Features

Open an issue describing the use case. Explain what you're trying to do, not just what you want xcforge to add. Context helps us design the right solution.

### Submitting Pull Requests

1. Fork the repo and create a branch from `main`
2. Make your changes
3. Add or update tests if applicable
4. Run `swift test` and make sure everything passes
5. Run `swift build -c release` to verify the release build compiles
6. Open a PR with a clear description of what changed and why

#### PR Guidelines

- Keep PRs focused — one feature or fix per PR
- Follow the existing code style (see below)
- Update tool documentation in `.claude/skills/xcforge/references/` if you add or change tools
- Add tests for new tools or non-trivial logic changes

### Formatting

xcforge uses [swift-format](https://github.com/swiftlang/swift-format) for consistent code style. A [lefthook](https://github.com/evilmartians/lefthook) pre-push hook runs `swift-format lint` automatically — if it fails, fix with:

```bash
swift-format format --in-place --recursive Sources/ Tests/
```

Install both via Homebrew: `brew install swift-format lefthook`

### Code Style

- Swift 6.0 strict concurrency — no `@unchecked Sendable` without justification
- Prefer `async/await` over callbacks
- Use `ProcessRunner` for subprocess execution, not `Process` directly
- Tool providers implement `ProviderProtocol` and register via `ProviderRegistry`
- CLI commands mirror MCP tool names — `build_sim` MCP tool = `xcforge build` CLI command
- Keep tool responses structured and concise — agents pay per token

### Commit Messages

Use conventional commit style:

```
feat: add new_tool_name tool
fix: handle empty xcresult bundles in test_failures
refactor: extract common sim resolution into SimResolver
docs: update CLI command reference
test: add coverage for DefaultsStore locking
```

## Adding a New Tool

1. Create or extend a provider in `Sources/XCForgeKit/Tools/`
2. Implement the tool method and register it in `ProviderRegistry`
3. Add a matching CLI command in `Sources/XCForgeCLI/Commands/`
4. Add tests in `Tests/XCForgeKitTests/`
5. Update the skill reference in `.claude/skills/xcforge/references/`

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

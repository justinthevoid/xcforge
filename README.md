# xcforge

<p align="center"><img src="xcforge.png" alt="xcforge" width="100%"></p>

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/platform-macOS_13%2B-blue)](#requirements)
[![Swift 6.0](https://img.shields.io/badge/Swift-6.0-orange)](https://swift.org)
[![MCP](https://img.shields.io/badge/MCP-compatible-8A2BE2)](https://modelcontextprotocol.io)
[![Homebrew](https://img.shields.io/badge/homebrew-tap-FBB040?logo=homebrew&logoColor=white)](https://github.com/justinthevoid/homebrew-tap)
[![GitHub release](https://img.shields.io/github/v/release/justinthevoid/xcforge)](https://github.com/justinthevoid/xcforge/releases)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

An MCP server and CLI for iOS development — build, test, automate, and diagnose from any AI agent or terminal.

**103 MCP tools. 17 CLI command groups. Single native binary (~8 MB stripped, ~18 MB with debug symbols). Zero external runtime dependencies.**

---

## Install

### Homebrew (recommended)

```bash
brew tap justinthevoid/tap && brew install xcforge
```

### Claude Code (one-liner)

```bash
claude mcp add xcforge -- xcforge
```

This registers xcforge as an MCP server in your current project. Run it after installing via Homebrew.

### From source

```bash
git clone https://github.com/justinthevoid/xcforge.git
cd xcforge && swift build -c release
cp .build/release/XCForgeCLI /usr/local/bin/xcforge
```

## Uninstall

### Homebrew

```bash
brew uninstall xcforge
brew untap justinthevoid/tap   # optional: remove the tap
```

### From source

```bash
rm /usr/local/bin/xcforge
```

### Remove MCP configuration

After uninstalling the binary, remove the `"xcforge"` entry from your MCP client config file (see [Configure](#configure) for file locations).

For Claude Code:

```bash
claude mcp remove xcforge
```

---

## Configure

Add xcforge to your MCP client. Each client has a different config format and file location.

### Claude Code

The fastest way is the CLI command shown above under [Install](#install). To configure manually, add to `.mcp.json` in your project root (or `~/.claude/.mcp.json` for global):

```json
{
  "mcpServers": {
    "xcforge": {
      "command": "xcforge",
      "args": [],
      "type": "stdio"
    }
  }
}
```

### Claude Desktop

File: `~/Library/Application Support/Claude/claude_desktop_config.json`

```json
{
  "mcpServers": {
    "xcforge": {
      "command": "/opt/homebrew/bin/xcforge",
      "args": []
    }
  }
}
```

> **Note:** Claude Desktop does not inherit your shell PATH. Use the full Homebrew path — `/opt/homebrew/bin/xcforge` on Apple Silicon, `/usr/local/bin/xcforge` on Intel.

### Cursor

File: `.cursor/mcp.json` in your project root (or `~/.cursor/mcp.json` for global)

```json
{
  "mcpServers": {
    "xcforge": {
      "command": "/opt/homebrew/bin/xcforge",
      "args": []
    }
  }
}
```

> **Note:** Same PATH caveat as Claude Desktop — use the absolute path. Restart Cursor after changes.

### VS Code (GitHub Copilot)

File: `.vscode/mcp.json` in your project root

```json
{
  "servers": {
    "xcforge": {
      "command": "xcforge",
      "args": [],
      "type": "stdio"
    }
  }
}
```

> **Note:** VS Code uses `"servers"` not `"mcpServers"`. Requires the GitHub Copilot extension with agent mode enabled. VS Code typically resolves PATH from your shell, so the bare command works.

### Windsurf

File: `~/.codeium/windsurf/mcp_config.json`

```json
{
  "mcpServers": {
    "xcforge": {
      "command": "/opt/homebrew/bin/xcforge",
      "args": []
    }
  }
}
```

> **Note:** Full path recommended. Restart Windsurf after editing.

### Zed

File: `~/.config/zed/settings.json` (or `.zed/settings.json` per-project)

```json
{
  "context_servers": {
    "xcforge": {
      "command": {
        "path": "/opt/homebrew/bin/xcforge",
        "args": []
      },
      "settings": {}
    }
  }
}
```

> **Note:** Zed uses `"context_servers"` with a nested `"command.path"` — different from every other client.

### Config quick reference

| Client         | Config key        | File location                                                     | Needs absolute path? |
| -------------- | ----------------- | ----------------------------------------------------------------- | -------------------- |
| Claude Code    | `mcpServers`      | `.mcp.json`                                                       | No                   |
| Claude Desktop | `mcpServers`      | `~/Library/Application Support/Claude/claude_desktop_config.json` | Yes                  |
| Cursor         | `mcpServers`      | `.cursor/mcp.json`                                                | Yes                  |
| VS Code        | `servers`         | `.vscode/mcp.json`                                                | No                   |
| Windsurf       | `mcpServers`      | `~/.codeium/windsurf/mcp_config.json`                             | Yes                  |
| Zed            | `context_servers` | `~/.config/zed/settings.json`                                     | Yes                  |

---

## Claude Code Skill

xcforge includes a Claude Code skill that loads the full tool reference into context when you're working on iOS tasks. Install it globally with:

```bash
npx skills justinthevoid/xcforge
```

Once installed, Claude will automatically load the right reference files when you use xcforge tools — exact parameters, return values, and usage patterns for each category (build, test, simulator, UI automation, logs, LLDB, diagnosis, and more).

---

## Two Modes, Same Tools

```bash
xcforge                          # MCP server (stdio JSON-RPC, 95 tools)
xcforge build --scheme MyApp     # CLI mode (16 command groups)
```

Every tool available over MCP has a matching CLI command. Every CLI command supports `--json`.

---

## Tools Overview

| Category              | Count | Highlights                                                                                        |
| --------------------- | ----- | ------------------------------------------------------------------------------------------------- |
| **Build**             | 5     | `build_sim`, `build_run_sim` (build + boot + install + launch), `clean`, project/scheme discovery |
| **Test**              | 6     | `test_sim` with xcresult parsing, `test_failures` with screenshots, `test_coverage`, `list_tests` |
| **Simulator**         | 17    | Full lifecycle + video recording, location simulation, dark mode toggle, status bar override      |
| **Physical Devices**  | 7     | Via `devicectl` — list, install, launch, screenshot, pair                                         |
| **UI Automation**     | 19    | WebDriverAgent + native AX bridge — find, tap, swipe, drag, type, alerts, hierarchy               |
| **Screenshots**       | 2     | Framebuffer capture (0.3s), point-space coordinate alignment                                      |
| **Visual Regression** | 2     | Pixel-diff baselines, multi-device checks (Dark Mode, Landscape, iPad)                            |
| **Logs**              | 4     | 4-layer filtered capture, 8 topic categories, regex wait                                          |
| **Console**           | 3     | stdout/stderr capture for launched apps                                                           |
| **SPM**               | 5     | Resolve, update, show deps, reset, clean                                                          |
| **Accessibility**     | 5     | Audit labels, traits, VoiceOver order, contrast                                                   |
| **Git**               | 5     | Status, diff, log, commit, branch                                                                 |
| **LLDB Debugger**     | 8     | Attach, breakpoints, inspect variables, backtrace, step/continue, arbitrary commands              |
| **Diagnosis**         | 10    | Multi-step workflows: build, run, inspect, capture evidence, compare, verify                      |
| **Plan Execution**    | 2     | Scripted multi-step automation with assertions                                                    |
| **Session**           | 3     | Persistent defaults, `.xcforge.yaml` repo config, session profiles                                |

---

## Key Capabilities

### Structured Test Results

Test output is parsed from `.xcresult` bundles — the structured format Xcode generates internally — not from raw xcodebuild stdout/stderr.

A single `test_sim` call returns: pass/fail counts, failure messages with source location, exported failure screenshots, and the xcresult path for deeper inspection via `test_failures` or `test_coverage`.

### Fast Screenshots

The `screenshot` tool reads the simulator framebuffer via CoreSimulator's IOSurface API, falling back to ScreenCaptureKit, then simctl. Typical latency is ~300ms.

### UI Automation Without Appium

xcforge communicates directly with WebDriverAgent over HTTP and supplements it with a native Accessibility API bridge (AXPBridge). This means:

- `find_element` with `scroll: true` auto-scrolls using 3 fallback strategies
- `handle_alert` searches across SpringBoard, ContactsUI, and the active app — `accept_all` clears multiple permission dialogs in one call
- `drag_and_drop` works with element IDs, not just coordinates
- `get_source` returns the full view hierarchy in ~20ms

### Topic-Filtered Logs

`start_log_capture` streams os_log through 4 filter layers:

1. **Noise exclusion** — strips 15 known noisy processes at the stream level
2. **Capture modes** — `smart` (broad + topic-ready), `app` (tight, auto-detected bundle), `verbose`
3. **Topic filtering** — `read_logs` classifies lines into 8 topics (app, crashes, network, lifecycle, springboard, widgets, background, system) and shows only app + crashes by default
4. **Deduplication** — collapses repeated lines

The response includes a topic menu with counts, so the agent can pull in specific topics on demand without re-querying.

### Interactive LLDB Debugger

8 tools for attaching LLDB to running simulator processes, setting breakpoints, inspecting variables, viewing stack traces, and stepping through code. Sessions persist for 30 minutes, so you can attach once and run multiple debugging operations. CLI commands are one-shot (attach → operation → detach). Includes:

- Session management: `lldb_attach` (by bundle ID or PID), `lldb_detach`
- Breakpoints: set by file+line or function name, remove by ID
- Inspection: evaluate expressions at the current frame, view stack traces
- Execution control: continue, step over, step into, step out (with 10-second timeout)
- Raw passthrough: run arbitrary LLDB commands

Use alongside logs and screenshots for systematic root-cause analysis.

### Diagnosis Workflows

10 tools that chain together into structured diagnostic pipelines — start a session, build, launch, capture runtime signals, collect evidence (screenshots, logs, accessibility state), compare against previous runs, and verify fixes. Designed for agents to systematically debug issues across multiple iterations.

### Physical Device Support

7 tools wrapping Apple's `devicectl` for real devices — list connected devices, install/launch/terminate apps, take screenshots, and manage pairing.

---

## CLI Examples

```bash
xcforge build                                    # Build (auto-detects project, scheme, sim)
xcforge build --scheme MyApp --simulator "iPhone 16 Pro"
xcforge test --scheme MyApp --json               # Run tests, JSON output
xcforge test failures --xcresult /path/to.xcresult
xcforge test coverage --min-coverage 80
xcforge sim list                                 # List simulators
xcforge sim boot "iPhone 16 Pro"
xcforge ui find --aid "loginButton"              # Find by accessibility ID
xcforge ui tap --element el-0                    # Tap element
xcforge screenshot                               # Screenshot to stdout
xcforge log start                                # Start log capture
xcforge log read --include network               # Read with topic filter
xcforge spm resolve                              # Resolve packages
xcforge device list                              # Connected physical devices
xcforge debug attach --bundle-id com.example.App    # Attach debugger
xcforge debug breakpoint set --bundle-id com.example.App --file ViewController.swift --line 42
xcforge debug inspect --bundle-id com.example.App --expression "self.count"
xcforge debug backtrace --bundle-id com.example.App # Show stack trace
xcforge debug continue --bundle-id com.example.App --mode step-over
xcforge diagnose start --scheme MyApp            # Start diagnosis session
```

---

## Alternatives

There are several iOS-focused MCP servers worth knowing about:

| Server                                                               | Stars | Scope     | Build   | Test | UI Automation | Screenshots | Visual Regression | Accessibility | Physical Devices | SPM | Git | Logs |
| -------------------------------------------------------------------- | ----- | --------- | ------- | ---- | ------------- | ----------- | ----------------- | ------------- | ---------------- | --- | --- | ---- |
| **xcforge**                                                          | —     | 95 tools  | Yes     | Yes  | Yes           | Yes         | Yes               | Yes           | Yes              | Yes | Yes | Yes  |
| [XcodeBuildMCP](https://github.com/getsentry/XcodeBuildMCP)          | ~5k   | ~15 tools | Yes     | Yes  | Partial       | No          | No                | No            | No               | No  | No  | No   |
| [ios-simulator-mcp](https://github.com/joshuayoes/ios-simulator-mcp) | ~1.8k | ~10 tools | No      | No   | Yes           | Yes         | No                | No            | No               | No  | No  | No   |
| [xcode-mcp-server](https://github.com/r-huijts/xcode-mcp-server)     | ~370  | ~8 tools  | Partial | No   | No            | No          | No                | No            | No               | No  | No  | No   |
| [iosef](https://github.com/riwsky/iosef)                             | <10   | ~5 tools  | No      | No   | Yes           | No          | No                | No            | No               | No  | No  | No   |
| [Appium MCP](https://github.com/nicholasgcoles/appium-mcp-server)    | <50   | ~10 tools | No      | No   | Yes           | Yes         | No                | No            | Partial          | No  | No  | No   |

- **[XcodeBuildMCP](https://github.com/getsentry/XcodeBuildMCP)** — The most popular iOS MCP server. Backed by Sentry. Covers build, test, and simulator management well. If you only need build/run workflows, it's a solid choice.
- **[ios-simulator-mcp](https://github.com/joshuayoes/ios-simulator-mcp)** — Focused on simulator UI interaction — screenshots, taps, swipes, accessibility tree. Good if you only need simulator automation.
- **[xcode-mcp-server](https://github.com/r-huijts/xcode-mcp-server)** — Early MCP server for Xcode project management. Basic integration — no simulator automation, testing, or device support.
- **[iosef](https://github.com/riwsky/iosef)** — Agent-optimized simulator CLI with clean ergonomics. Narrow scope but thoughtful design. Swift native.
- **[Appium MCP](https://github.com/nicholasgcoles/appium-mcp-server)** — Cross-platform (iOS + Android) via the Appium ecosystem. Requires Node.js + Java + Appium server — heavier dependency chain.

**Where xcforge fits:** It combines build, test, UI automation, log analysis, visual regression, device support, SPM, accessibility auditing, and multi-step diagnosis in a single zero-dependency binary. The trade-off is iOS-only — no Android, watchOS, or visionOS.

---

## Requirements

- macOS 13+
- Xcode 15+
- Swift 6.0+ (source builds only)
- WebDriverAgent on simulator (UI automation only)

---

## Web Baseline (Story 1.1)

The Web workspace is isolated under `Web/` and uses Astro Starlight plus Svelte with Bun-only package/script usage and Biome-only lint/format checks.

```bash
cd Web
bun install
bun run typecheck
bun run lint
bun run validate
```

Local route assumptions after `bun run dev`:

- Marketing route: `http://localhost:4321/`
- Docs route: `http://localhost:4321/docs`
- Docs depth route: `http://localhost:4321/docs/getting-started`

If setup fails, run:

```bash
cd Web
bun run doctor
```

Remediation steps are documented in `Web/README.md`.

---

## Support

If xcforge saves you time, consider supporting development:

[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-ffdd00?style=flat&logo=buy-me-a-coffee&logoColor=black)](https://buymeacoffee.com/justinthevoid)
[![Ko-fi](https://img.shields.io/badge/Ko--fi-FF5E5B?style=flat&logo=ko-fi&logoColor=white)](https://ko-fi.com/joltik)
[![GitHub Sponsors](https://img.shields.io/badge/GitHub%20Sponsors-ea4aaa?style=flat&logo=github-sponsors&logoColor=white)](https://github.com/sponsors/justinthevoid)

## License

MIT — see [LICENSE](LICENSE).

## Contributing

Issues and PRs welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).

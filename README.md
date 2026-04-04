# xcforge

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/platform-macOS_13%2B-blue)]()
[![Swift 6.0](https://img.shields.io/badge/Swift-6.0-orange)](https://swift.org)

An MCP server and CLI for iOS development — build, test, automate, and diagnose from any AI agent or terminal.

95 MCP tools. 16 CLI command groups. Single 8.5MB Swift binary. No runtime dependencies.

## Install

```bash
brew tap justinthevoid/xcforge && brew install xcforge
```

Or from source:

```bash
git clone https://github.com/justinthevoid/xcforge.git
cd xcforge && swift build -c release
cp .build/release/xcforge /usr/local/bin/
```

## Configure

Add to your MCP client config (Claude Code, Cursor, VS Code, Windsurf, etc.):

```json
{
  "mcpServers": {
    "xcforge": {
      "command": "xcforge"
    }
  }
}
```

Claude Code users: add to `~/.claude/.mcp.json` for global availability.

## Two Modes, Same Tools

```bash
xcforge                          # MCP server (stdio JSON-RPC, 95 tools)
xcforge build --scheme MyApp     # CLI mode (16 command groups)
```

Every tool available over MCP has a matching CLI command. Every CLI command supports `--json`.

## Tools Overview

| Category | Count | Highlights |
|---|---|---|
| **Build** | 5 | `build_sim`, `build_run_sim` (build + boot + install + launch), `clean`, project/scheme discovery |
| **Test** | 6 | `test_sim` with xcresult parsing, `test_failures` with screenshots, `test_coverage`, `list_tests` |
| **Simulator** | 17 | Full lifecycle + video recording, location simulation, dark mode toggle, status bar override |
| **Physical Devices** | 7 | Via `devicectl` — list, install, launch, screenshot, pair |
| **UI Automation** | 19 | WebDriverAgent + native AX bridge — find, tap, swipe, drag, type, alerts, hierarchy |
| **Screenshots** | 2 | Framebuffer capture (0.3s), point-space coordinate alignment |
| **Visual Regression** | 2 | Pixel-diff baselines, multi-device checks (Dark Mode, Landscape, iPad) |
| **Logs** | 4 | 4-layer filtered capture, 8 topic categories, regex wait |
| **Console** | 3 | stdout/stderr capture for launched apps |
| **SPM** | 5 | Resolve, update, show deps, reset, clean |
| **Accessibility** | 5 | Audit labels, traits, VoiceOver order, contrast |
| **Git** | 5 | Status, diff, log, commit, branch |
| **Diagnosis** | 10 | Multi-step workflows: build, run, inspect, capture evidence, compare, verify |
| **Plan Execution** | 2 | Scripted multi-step automation with assertions |
| **Session** | 3 | Persistent defaults, `.xcforge.yaml` repo config, session profiles |

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

### Diagnosis Workflows

10 tools that chain together into structured diagnostic pipelines — start a session, build, launch, capture runtime signals, collect evidence (screenshots, logs, accessibility state), compare against previous runs, and verify fixes. Designed for agents to systematically debug issues across multiple iterations.

### Physical Device Support

7 tools wrapping Apple's `devicectl` for real devices — list connected devices, install/launch/terminate apps, take screenshots, and manage pairing.

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
xcforge diagnose start --scheme MyApp            # Start diagnosis session
```

## Alternatives

There are several iOS-focused MCP servers worth knowing about:

- **[XcodeBuildMCP](https://github.com/getsentry/XcodeBuildMCP)** — Xcode build + simulator management. Mature, well-supported. Covers build/run workflows and project introspection.
- **[iosef](https://github.com/riwsky/iosef)** — Agent-optimized simulator CLI. Clean design, coordinate-aligned screenshots, accessibility tree inspection. Swift native.
- **[Appium MCP](https://github.com/appium/appium-mcp)** — Cross-platform mobile automation (iOS + Android). AI-powered element finding. Requires Node.js + Java + Appium server.

xcforge occupies a different niche: it combines build, test, UI automation, log analysis, visual regression, device support, SPM, accessibility auditing, and multi-step diagnosis in a single binary. The trade-off is iOS-only — no Android, watchOS, or visionOS.

## Requirements

- macOS 13+
- Xcode 15+
- Swift 6.0+ (source builds only)
- WebDriverAgent on simulator (UI automation only)

## Support

If xcforge saves you time, consider supporting development:

[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-ffdd00?style=flat&logo=buy-me-a-coffee&logoColor=black)](https://buymeacoffee.com/justinthevoid)
[![Ko-fi](https://img.shields.io/badge/Ko--fi-FF5E5B?style=flat&logo=ko-fi&logoColor=white)](https://ko-fi.com/joltik)
[![GitHub Sponsors](https://img.shields.io/badge/GitHub%20Sponsors-ea4aaa?style=flat&logo=github-sponsors&logoColor=white)](https://github.com/sponsors/justinthevoid)

## License

MIT — see [LICENSE](LICENSE).

## Contributing

Issues and PRs welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).

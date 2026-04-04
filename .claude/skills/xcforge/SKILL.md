---
name: xcforge
description: Complete reference for xcforge — 67 MCP tools + 67 CLI commands for iOS development. Covers build, test, simulator, UI automation, screenshots, logs, git, visual regression, accessibility, localization, diagnosis workflows, plan execution, and full CLI parity across 13 command groups. Use when working with iOS simulators, Xcode builds, UI testing, TDD workflows, or any xcforge tool.
---

# xcforge — iOS Development MCP Server & CLI

xcforge is a native Swift MCP server and CLI for iOS development. 67 MCP tools, 67 CLI commands across 13 groups, 8.5MB binary, zero runtime dependencies. It provides build, test, simulator management, UI automation via WebDriverAgent, ultra-fast screenshots, smart log filtering, visual regression, multi-device checks, accessibility/localization layout checks, structured diagnosis workflows, and server-side plan execution for multi-step UI automation. Every MCP tool has a CLI equivalent.

**Key advantages over alternatives:**
- Screenshots in 0.3s (44x faster) via CoreSimulator IOSurface API
- Structured xcresult parsing — pass/fail counts, failure file:line, failure screenshots
- One-call alert batching (`accept_all`) handles 3+ permission dialogs
- Topic-filtered logs — 90% fewer tokens, 8 topics with line counts
- Element-to-element drag & drop in 1 call
- Auto-scroll to off-screen elements (3-tier fallback)
- View hierarchy in ~20ms (750x faster)

## Reference Loading Guide

**Load reference files when using or advising on any xcforge tool.** Each reference covers one tool category with exact parameters, return values, and usage patterns.

| Reference | Load When |
|-----------|-----------|
| **[Build Tools](references/build-tools.md)** | Building, running, cleaning, discovering projects, listing schemes |
| **[Test Tools](references/test-tools.md)** | Running tests, analyzing failures, checking code coverage, build diagnostics |
| **[Simulator Tools](references/simulator-tools.md)** | Managing simulators — boot, shutdown, install, launch, clone, erase, delete, orientation |
| **[UI Automation](references/ui-automation.md)** | Finding/clicking elements, alerts, typing, gestures, drag & drop, view hierarchy |
| **[Screenshot & Visual](references/screenshot-visual.md)** | Taking screenshots, saving baselines, comparing visual regressions, multi-device checks |
| **[Accessibility & Localization](references/cli-commands.md#xcforge-accessibility)** | Dynamic Type size checks, localization layout checks, RTL rendering validation |
| **[Log & Console](references/log-console.md)** | Capturing logs, topic filtering, waiting for patterns, stdout/stderr capture |
| **[Git Tools](references/git-tools.md)** | Git status, diff, log, commit, branch operations |
| **[Diagnosis Workflows](references/diagnosis-workflows.md)** | Running structured diagnosis: start, build, test, runtime, status, evidence, inspect, verify, compare, result |
| **[Plan Execution](references/plan-execution.md)** | Multi-step UI automation plans: run_plan, run_plan_decide, step types, variable binding, verification, suspend/resume |
| **[Auto-Detection & Defaults](references/auto-detection.md)** | Understanding parameter resolution, setting defaults, session state |
| **[CLI Commands](references/cli-commands.md)** | Using xcforge from terminal: all 12 command groups (`build`, `test`, `sim`, `log`, `console`, `screenshot`, `ui`, `git`, `accessibility`, `defaults`, `diagnose`, `plan`) |

## Auto-Detection — How Parameters Resolve

All tools that accept `project`, `scheme`, `simulator`, `bundle_id`, or `app_path` follow this resolution order:

1. **Explicit parameter** — highest priority
2. **Session default** — set via `set_defaults` tool or `xcforge defaults set` CLI
3. **Auto-detect** — scans working directory for .xcodeproj/.xcworkspace, queries xcodebuild for schemes, finds booted simulator
4. **Error with options** — lists available choices if detection fails

**Auto-promotion:** 3 consecutive calls with the same explicit value auto-promotes it to a session default.

Most tools work with zero parameters for single-project repos with one booted simulator.

## Common Workflows

### Build & Launch (Cmd+R equivalent)
```
build_run_sim()  → builds + boots + installs + launches in parallel (~9s faster)
```

### Test → Fix → Verify (MCP)
```
build_and_test()                              → build + test in one call (preferred)
build_and_test(filter: "testFoo")             → build + run specific test (auto-resolves target)
test_failures(include_console: true)          → error messages + file:line + console
# fix the code...
build_and_test(filter: "testFoo")             → verify fix
```

### Discover Tests → Run Specific Test (MCP)
```
list_tests()                                  → enumerate Target/Class/method identifiers
test_sim(filter: "MyClass/testFoo")           → run specific test (auto-resolves target)
```

### TDD Loop (CLI)
```bash
xcforge build-test                            → build + test in one step (preferred)
xcforge build-test --filter "testFoo"         → build + run specific test
xcforge test list                             → list all test identifiers
xcforge test --filter "MyTests/testFoo"       → run specific test (auto-resolves target)
xcforge test failures --include-console       → drill into failures
xcforge test coverage --file Foo.swift        → per-function coverage
xcforge build --diagnose                      → structured build diagnostics
```

### UI Automation Flow
```
build_run_sim()                               → app running in simulator
handle_alert(action: "accept_all")            → dismiss permission dialogs
find_element(using: "accessibility id", value: "Save", scroll: true)
click_element(element_id: "...")
screenshot()                                  → verify result
```

### Multi-Step UI Plan (1 call replaces 15+ round-trips)
```
run_plan(steps: [
  {"find": "Login", "as": "$loginBtn"},
  {"click": "$loginBtn"},
  {"waitFor": "Welcome", "timeout": 5},
  {"verify": {"screenContains": "Dashboard"}},
  {"screenshot": "after_login"}
])
# If a judge step suspends:
run_plan_decide(session_id: "...", decision: "accept")
```

### Multi-Step UI Plan (CLI)
```bash
xcforge plan run --file login-flow.json               → execute plan from file
xcforge plan run --file login-flow.json --json         → structured JSON output
xcforge plan decide --session-id UUID --decision skip  → resume suspended plan
```

### Debug with Logs
```
start_log_capture(mode: "smart")
# reproduce the issue...
read_logs()                                   → app + crashes + topic menu
read_logs(include: ["network"])               → add network topic
wait_for_log(pattern: "error.*timeout", timeout: 10)
```

### Visual Regression
```
screenshot() → save_visual_baseline(name: "login-screen")
# make changes...
compare_visual(name: "login-screen")          → pixel diff + match %
```

### Multi-Device Check
```
multi_device_check(
  app_path: "/path/to/App.app",
  simulators: "iPhone 16,iPad Pro 13-inch (M4)",
  dark_mode: true, landscape: true
)
```

## Common Mistakes

1. **Starting log capture after the event** — `start_log_capture` only captures from the moment it's called. Start capture BEFORE reproducing the issue.

2. **Not using `accept_all` after fresh install** — First app launch shows 2-3 permission dialogs. Call `handle_alert(action: "accept_all")` right after `launch_app` or `build_run_sim`.

3. **Manual swipe loops to find elements** — Use `find_element(scroll: true)` instead. It handles auto-scrolling with 3-tier fallback (scrollToVisible, calculated drag, iterative with stall detection).

4. **Using `get_source` for every element lookup** — `find_element` is faster and more reliable. Use `get_source` only when you need the full hierarchy for analysis.

5. **Ignoring topic menu in `read_logs`** — The topic menu shows line counts. Use `include` to add specific topics rather than reading everything.

6. **Not setting defaults for repeated operations** — Call `set_defaults(project: "...", scheme: "...", simulator: "...")` at the start of a session to avoid repeating parameters.

7. **Using `test_sim` then parsing output for failures** — Use `test_failures` for detailed failure info with file:line and screenshots. `test_sim` gives the summary; `test_failures` gives the details.

8. **Forgetting WDA session** — UI automation tools require WebDriverAgent running on the simulator. If `wda_status` fails, WDA needs to be started. `build_run_sim` does NOT start WDA automatically.

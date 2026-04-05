# LLDB Debugger Integration

Attach to running simulator processes and debug interactively — inspect variables, set breakpoints, step through code, and view stack traces.

**Availability:** MCP server (persistent sessions) and CLI (one-shot commands)
**Platforms:** Simulator processes only (iOS 26.0+ in Xcode 15+)
**Requirements:** Xcode installed (`xcrun lldb` available)

---

## Core Design

**Session-based debugging (MCP):** Call `lldb_attach` once to get a `sessionId`, then use it with all other tools. Sessions persist for 30 minutes of inactivity and are keyed by UUID. When you're done, call `lldb_detach` to clean up.

**One-shot debugging (CLI):** Each `xcforge debug` command attaches → runs one operation → detaches automatically. No session ID needed for CLI commands.

---

## MCP Tools (8 total)

### lldb_attach

**Attach LLDB to a running simulator process.**

```
Inputs:
  bundleId   (string, optional) -- App bundle ID (e.g. com.example.App)
  pid        (integer, optional) -- Process ID
  
  Note: Provide either bundleId or pid, not both.

Outputs:
  {
    "sessionId": "uuid-string",
    "pid": 12345,
    "status": "stopped"
  }
  
Errors:
  "App not running on booted simulator" (bundleId not found)
  "Process ID not found" (pid doesn't exist)
  "Attach failed: ..." (LLDB attach error)
```

**Usage pattern (MCP):**

```
1. lldb_attach with bundleId: "com.example.App"
   → sessionId = "8f3c-..."
   
2. [Run any other tools with sessionId = "8f3c-..."]
3. lldb_detach with sessionId: "8f3c-..."
```

---

### lldb_detach

**Detach from a session and clean up the LLDB subprocess.**

```
Inputs:
  sessionId  (string, required) -- Session ID from lldb_attach

Outputs:
  {
    "detached": true
  }
  
Errors:
  None (silently succeeds even if session is already gone)
```

---

### lldb_set_breakpoint

**Set a breakpoint by source file+line or by function name.**

```
Inputs:
  sessionId  (string, required) -- Session ID from lldb_attach
  file       (string, optional) -- Source file name (e.g. Foo.swift)
  line       (integer, optional) -- Line number (used with file)
  function   (string, optional) -- Function/method name (e.g. -[FooVC viewDidLoad])
  
  Note: Provide either (file + line) or function, not both.

Outputs:
  {
    "breakpointId": 1,
    "resolved": true      // false if file not found in binary
  }
  
Errors:
  "Session not found or expired"
  "Invalid input: ... (newlines not allowed)"
  "No breakpoint created — check file path or function name"
```

**Example:**

File+line breakpoint:
```
Input:  sessionId="8f3c-...", file="ViewController.swift", line=42
Output: { "breakpointId": 1, "resolved": true }
```

Function breakpoint (Objective-C):
```
Input:  sessionId="8f3c-...", function="-[LoginVC viewDidLoad]"
Output: { "breakpointId": 2, "resolved": true }
```

Function breakpoint (Swift):
```
Input:  sessionId="8f3c-...", function="MyApp.ViewController.handleTap()"
Output: { "breakpointId": 3, "resolved": true }
```

---

### lldb_remove_breakpoint

**Remove a breakpoint by ID.**

```
Inputs:
  sessionId     (string, required) -- Session ID from lldb_attach
  breakpointId  (integer, required) -- Breakpoint ID from lldb_set_breakpoint

Outputs:
  {
    "removed": true
  }
  
Errors:
  "Breakpoint ID N not found"
  "Session not found or expired"
```

---

### lldb_inspect_variable

**Evaluate an expression in the current stack frame. Process must be stopped.**

```
Inputs:
  sessionId   (string, required) -- Session ID from lldb_attach
  expression  (string, required) -- Expression to evaluate (e.g. self.count)

Outputs:
  {
    "expression": "self.count",
    "type": "Int",
    "value": "42",
    "summary": "42 values"    // Optional summary from LLDB
  }
  
Errors:
  "Process is not stopped at a frame"
  "Session not found or expired"
  "Expression error: ..." (invalid expression or evaluation failed)
```

**Example:**

```
Input:  sessionId="8f3c-...", expression="self.items.count"
Output: {
  "expression": "self.items.count",
  "type": "Int",
  "value": "5",
  "summary": "5"
}
```

---

### lldb_backtrace

**Get the stack trace for the current or specified thread. Process must be stopped.**

```
Inputs:
  sessionId    (string, required) -- Session ID from lldb_attach
  threadIndex  (integer, optional) -- Thread index (default 0)

Outputs:
  [
    {
      "frameIndex": 0,
      "address": "0x1005a8c4c",
      "symbol": "MyApp.ViewController.handleTap()",
      "file": "ViewController.swift",
      "line": 42
    },
    {
      "frameIndex": 1,
      "address": "0x10059a0c8",
      "symbol": "UIKit.UIButton.sendAction(...)",
      "file": null,
      "line": null
    }
    // ... more frames ...
  ]
  
Errors:
  "Process is running (not stopped at a frame)"
  "Session not found or expired"
```

---

### lldb_continue

**Resume, step over, step into, or step out of the current frame. Timeout: 10 seconds.**

```
Inputs:
  sessionId  (string, required) -- Session ID from lldb_attach
  mode       (string, optional) -- Execution mode (default: "continue")
             Valid: "continue", "step_over", "step_into", "step_out"

Outputs:
  {
    "stopReason": "breakpoint",    // or "step", "signal", etc.
    "threadIndex": 0,
    "frameIndex": 0
  }
  
Errors:
  "Process is running (already executing)"
  "Timeout: Process did not stop within 10 seconds"
  "Session not found or expired"
```

**Mode explanation:**

| Mode | LLDB Command | Behavior |
|------|-------------|----------|
| `continue` | `continue` | Resume until next breakpoint or end |
| `step_over` | `next` | Execute current line, stop at next line (skip function calls) |
| `step_into` | `step` | Execute current line, stop inside function calls |
| `step_out` | `finish` | Execute until current function returns |

**Example (hit a breakpoint, then step):**

```
1. lldb_continue with mode="step_over"
   → { "stopReason": "step", "threadIndex": 0, "frameIndex": 0 }
   
2. lldb_continue with mode="step_into"
   → { "stopReason": "step", "threadIndex": 0, "frameIndex": 0 }
```

---

### lldb_run_command

**Run an arbitrary LLDB command and get raw output. Advanced use only.**

```
Inputs:
  sessionId  (string, required) -- Session ID from lldb_attach
  command    (string, required) -- Raw LLDB command (e.g. "memory read 0x...")

Outputs:
  {
    "output": "<raw LLDB output>"
  }
  
Errors:
  "Invalid input: newlines not allowed in command"
  "Session not found or expired"
```

**Example (read process memory):**

```
Input:  sessionId="8f3c-...", command="memory read 0x104c8a000 0x104c8a100"
Output: {
  "output": "0x104c8a000: 00 01 02 03 04 05 06 07 08 09 0a 0b 0c 0d 0e 0f ................"
}
```

---

## CLI Commands (8 total)

All CLI commands are one-shot (attach → operation → detach). Simulator must be booted.

### debug attach

```bash
xcforge debug attach [--pid N | --bundle-id X] [--json]
```

Attach and create a persistent MCP session (CLI shows session ID for later use).

```
$ xcforge debug attach --bundle-id com.example.App
Attached to com.example.App (PID 1234)
Session ID: 8f3c-4d1f-...

$ xcforge debug attach --pid 5678 --json
{
  "sessionId": "8f3c-4d1f-...",
  "pid": 5678,
  "status": "stopped"
}
```

---

### debug detach

```bash
xcforge debug detach --session <id> [--json]
```

Detach from a session (created by MCP `lldb_attach` or CLI `debug attach`).

```
$ xcforge debug detach --session 8f3c-4d1f-...
Detached from session 8f3c-4d1f-...

$ xcforge debug detach --session 8f3c-4d1f-... --json
{
  "detached": true
}
```

---

### debug backtrace

```bash
xcforge debug backtrace [--pid N | --bundle-id X] [--thread N] [--json]
```

One-shot: show stack trace without attaching a persistent session.

```
$ xcforge debug backtrace --bundle-id com.example.App
Frame 0: -[LoginVC handleTap] (LoginViewController.swift:42)
Frame 1: -[UIButton sendAction:to:forEvent:] (UIKit)
Frame 2: -[UIApplication sendAction:to:from:forEvent:] (UIKit)

$ xcforge debug backtrace --bundle-id com.example.App --json
[
  {
    "frameIndex": 0,
    "address": "0x1005a8c4c",
    "symbol": "MyApp.LoginVC.handleTap()",
    "file": "LoginViewController.swift",
    "line": 42
  },
  ...
]
```

---

### debug inspect

```bash
xcforge debug inspect [--pid N | --bundle-id X] --expression <expr> [--json]
```

One-shot: evaluate an expression in the current frame.

```
$ xcforge debug inspect --bundle-id com.example.App --expression "self.count"
self.count = 42 (Int)

$ xcforge debug inspect --bundle-id com.example.App --expression "self.count" --json
{
  "expression": "self.count",
  "type": "Int",
  "value": "42",
  "summary": "42"
}
```

---

### debug breakpoint set

```bash
xcforge debug breakpoint set [--pid N | --bundle-id X] [--file F --line N | --function FN] [--json]
```

One-shot: set a breakpoint without creating a persistent session.

```
$ xcforge debug breakpoint set --bundle-id com.example.App --file LoginVC.swift --line 42
Breakpoint 1: file = 'LoginVC.swift', line = 42, locations = 1

$ xcforge debug breakpoint set --bundle-id com.example.App --function "LoginVC.handleTap()" --json
{
  "breakpointId": 1,
  "resolved": true
}
```

---

### debug breakpoint remove

```bash
xcforge debug breakpoint remove [--pid N | --bundle-id X] --breakpoint-id N [--json]
```

One-shot: remove a breakpoint.

```
$ xcforge debug breakpoint remove --bundle-id com.example.App --breakpoint-id 1
Removed breakpoint 1

$ xcforge debug breakpoint remove --bundle-id com.example.App --breakpoint-id 1 --json
{
  "removed": true
}
```

---

### debug continue

```bash
xcforge debug continue [--pid N | --bundle-id X] [--mode continue|step-over|step-into|step-out] [--json]
```

One-shot: resume, step over, step into, or step out.

```
$ xcforge debug continue --bundle-id com.example.App --mode step-over
Stopped at frame 0: -[LoginVC handleTap] (LoginVC.swift:43)
Stop reason: step

$ xcforge debug continue --bundle-id com.example.App --mode step-into --json
{
  "stopReason": "step",
  "threadIndex": 0,
  "frameIndex": 0
}
```

---

### debug run

```bash
xcforge debug run [--pid N | --bundle-id X] --command <lldb-cmd> [--json]
```

One-shot: execute an arbitrary LLDB command.

```
$ xcforge debug run --bundle-id com.example.App --command "memory read 0x104c8a000"
0x104c8a000: 48 8b 05 35 6f 00 00 48 8b c8 48 ff 25 34 6f 00 00

$ xcforge debug run --bundle-id com.example.App --command "p self.model.name" --json
{
  "output": "(String) \"User 123\""
}
```

---

## Workflow Examples

### Example 1: Debug a Crash (MCP)

```
1. lldb_attach(bundleId: "com.example.App")
   → { sessionId: "abc-123-...", pid: 2345, status: "stopped" }

2. lldb_set_breakpoint(sessionId, file: "AppDelegate.swift", line: 15)
   → { breakpointId: 1, resolved: true }

3. lldb_continue(sessionId, mode: "continue")
   → { stopReason: "breakpoint", threadIndex: 0, frameIndex: 0 }

4. lldb_backtrace(sessionId)
   → [
       { frameIndex: 0, symbol: "AppDelegate.application(...)", file: "AppDelegate.swift", line: 15 },
       { frameIndex: 1, symbol: "UIApplication.main(...)", file: null, line: null }
     ]

5. lldb_inspect_variable(sessionId, expression: "self.count")
   → { expression: "self.count", type: "Int", value: "0" }

6. lldb_detach(sessionId)
   → { detached: true }
```

### Example 2: Inspect State at Breakpoint (CLI)

```bash
# Set a breakpoint and examine the frame
xcforge debug breakpoint set --bundle-id com.example.App --file LoginVC.swift --line 42

# Now the app is stopped. Inspect a variable
xcforge debug inspect --bundle-id com.example.App --expression "self.user?.email"

# View the stack
xcforge debug backtrace --bundle-id com.example.App

# Step to the next line
xcforge debug continue --bundle-id com.example.App --mode step-over
```

### Example 3: Watch Loop (MCP with polling)

Monitor a counter by stepping repeatedly:

```
1. Attach and set breakpoint at the loop body
2. lldb_continue(mode: "continue") — stops at breakpoint
3. lldb_inspect_variable(expression: "i")
4. lldb_continue(mode: "step_over") — advance one line
5. Repeat steps 3–4 until done
6. lldb_detach
```

---

## Common Pitfalls

**Session expired:** If you don't call a tool for 30+ minutes, the session is cleaned up. Call `lldb_attach` again.

**Process not stopped:** Tools like `lldb_inspect_variable`, `lldb_backtrace` require the process to be paused at a breakpoint or after a step. If you call them while the process is running, they fail with "not stopped".

**Unresolved breakpoint:** If you set a breakpoint by function name and it shows `resolved: false`, the function may not be in the binary (e.g. Swift name mangling issue, or the function is inlined). Try file+line instead.

**Bundle ID vs PID:** Use `bundleId` if the app is visible in the booted simulator; use `pid` if you already know the process ID (via `ps aux` or from system logs).

**CLI one-shot semantics:** Each `xcforge debug` command creates a fresh attach, runs the operation, and detaches. If you need to inspect multiple frames or variables, use MCP with a persistent session instead.

---

## Connection to Diagnosis Workflows

The LLDB tools integrate with `diagnose` workflows:

```
1. xcforge diagnose start --scheme MyApp
   → Creates a diagnosis session, builds, and launches the app

2. [App hits a breakpoint or crashes]

3. lldb_attach(bundleId: "com.example.App")
   → Attach debugger to understand the state

4. [Inspect variables, view backtrace, step through code]

5. xcforge diagnose verify --criteria <check>
   → Confirm the fix
```

---

## See Also

- [Logs & Console](log-console.md) — Capture app logs while debugging
- [Diagnosis Workflows](diagnosis-workflows.md) — Multi-step debugging pipelines
- [Auto-Detection](auto-detection.md) — Session profiles for repeated debug workflows

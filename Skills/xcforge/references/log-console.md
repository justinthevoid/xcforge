# Log & Console Tools (7 tools)

## Log Capture (4 tools)

xcforge's log system uses 4 filter layers to reduce noise by 90%:

1. **Stream-side noise exclusion** — 15 known noise processes removed before buffering (79% I/O reduction)
2. **3 capture modes** — smart (default), app, verbose
3. **Read-time topic filtering** — 8 topics with line counts, agent picks what matters
4. **Buffer deduplication** — 60 identical heartbeat lines become 2 entries

### start_log_capture

Start capturing OS logs from the simulator.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `simulator` | No | Auto-detect (booted) | Simulator name or UDID |
| `mode` | No | `smart` | Capture mode (see below) |
| `process` | No | — | Filter by process name (efficient server-side in logd). Bypasses mode logic. |
| `subsystem` | No | — | Filter by subsystem, e.g. `com.myapp`. Bypasses mode logic. |
| `predicate` | No | — | Custom NSPredicate filter. Bypasses mode logic. |
| `level` | No | `debug` | Log level: `default`, `info`, `debug` |

**Capture modes:**
- **`smart`** (default) — Broad stream with topic filtering enabled. Best for general debugging — captures everything, then `read_logs` filters by topic.
- **`app`** — Tight stream, auto-detected bundle ID + process name. Lower volume. Best for production monitoring or when you only care about your app.
- **`verbose`** — Unfiltered. Full `log stream`. Very high volume — use sparingly.

**Custom predicate example:**
```
start_log_capture(subsystem: "com.apple.SwiftUI")
```

**Important:** Start capture BEFORE reproducing the issue. Logs are not retroactive.

---

### stop_log_capture

Stop log capture and clear the buffer.

No parameters.

---

### read_logs

Read buffered logs with topic filtering. Returns a topic menu showing available data.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `include` | No | `["app", "crashes"]` | Array of topic names to include |
| `last` | No | — | Only return last N lines (applied after topic filtering) |
| `clear` | No | false | Clear buffer after reading |

**Response format:**
```
--- 230 buffered, 42 shown [app, crashes] ---
Topics: app(35) crashes(2) | network(87) lifecycle(12) springboard(8) widgets(0) background(3) system(83)
Hint: include=["network"] to add SSL/TLS + background transfer logs
---
[42 filtered log lines]
```

**8 Topics:**

| Topic | Always On | Matches | Use Case |
|-------|-----------|---------|----------|
| `app` | Yes | subsystem == bundleId OR process == appName | Your app's os_log, print(), NSLog() |
| `crashes` | Yes | Fault-level logs from any process | Crash detection |
| `network` | No | trustd, nsurlsessiond | SSL/TLS certificates, background transfers |
| `lifecycle` | No | runningboardd, com.apple.runningboard.* | Jetsam, memory pressure, app kills |
| `springboard` | No | SpringBoard process | Push notifications, app state changes |
| `widgets` | No | chronod | WidgetKit timeline, refresh budget |
| `background` | No | com.apple.xpc.activity.* | BGTaskScheduler, background fetch |
| `system` | No | Everything else | WARNING: high volume, use only when needed |

**Workflow:** Call `read_logs()` first to see the topic menu, then call again with specific topics based on line counts.

---

### wait_for_log

Wait for a specific log pattern with timeout. Eliminates sleep() hacks.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `pattern` | **Yes** | — | Regex pattern to match |
| `timeout` | No | 30 | Timeout in seconds |
| `simulator` | No | Auto-detect | Simulator (used if log capture not already running) |
| `subsystem` | No | — | Filter by subsystem (used if log capture not already running) |

**Returns:** The matching log line, or timeout error.

**Use case:** Wait for "app launched" signal, wait for network request completion, wait for crash after specific action.

---

## Console Capture (3 tools)

Console tools capture stdout/stderr (print(), NSLog()) by launching the app through xcforge's process wrapper. Different from log capture which uses Apple's `log stream`.

### launch_app_console

Launch app with stdout/stderr capture enabled.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `simulator` | No | Auto-detect (booted) | Simulator name or UDID |
| `bundle_id` | No | Auto-detect (last build) | App bundle identifier |
| `args` | No | — | Space-separated launch arguments string |

**Note:** This replaces a running instance of the app. Cannot use alongside `launch_app`.

---

### read_app_console

Read buffered console output.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `last` | No | — | Only return last N lines per stream |
| `clear` | No | false | Clear buffer after reading |
| `stream` | No | `both` | Which stream: `stdout`, `stderr`, or `both` |

---

### stop_app_console

Stop console capture and terminate the app.

No parameters.

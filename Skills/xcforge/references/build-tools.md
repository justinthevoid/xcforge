# Build Tools (6 tools)

> **Defaults note:** the `Default` column shows the *fallback*. `project`,
> `scheme`, `simulator`, and `configuration` are resolved through the parameter
> precedence chain — a committed `.xcforge.yaml` (`configuration:` /
> `scheme:` / …) overrides the listed fallback when the parameter is omitted.
> See [auto-detection.md](auto-detection.md).

## build_compile

Compile-only build: no boot, install or launch, and no extra build-settings lookup. Needs no booted simulator: without one configured or booted it compiles for the newest available iPhone simulator.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `project` | No | Auto-detect | Path to .xcodeproj or .xcworkspace |
| `scheme` | No | Auto-detect | Scheme name |
| `simulator` | No | Auto-detect (booted) | Simulator name or UDID (for SDK selection) |
| `configuration` | No | Debug | Build configuration (Debug/Release) |
| `long` | No | false | Raise the total time limit from 1800s to 7200s |

**Returns:** Bundle ID, app path, build duration, warnings count. On failure: structured errors with file:line from xcresult.

**Use case:** Rapid iteration on code without deployment latency. Does not boot simulator or install app.

**Build flags applied:** `parallelizeTargets`, `COMPILATION_CACHE_ENABLE_CACHING=YES` for speed.

---

## build_sim

Build for iOS Simulator. Returns structured errors from xcresult (not raw xcodebuild stderr). Caches bundle ID and app path for subsequent tools.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `project` | No | Auto-detect | Path to .xcodeproj or .xcworkspace |
| `scheme` | No | Auto-detect | Scheme name |
| `simulator` | No | Auto-detect (booted) | Simulator name or UDID |
| `configuration` | No | Debug | Build configuration (Debug/Release) |

**Returns:** Bundle ID, app path, build duration, warnings count. On failure: structured errors with file:line from xcresult.

**Build flags applied:** `parallelizeTargets`, `COMPILATION_CACHE_ENABLE_CACHING=YES` for speed.

---

## build_run_sim

Build, boot, install and launch in one call (Xcode's Cmd+R). The simulator boots once the build succeeds; the app installed is the scheme's application target (from `-showBuildSettings -json`), not an extension or framework.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `project` | No | Auto-detect | Path to .xcodeproj or .xcworkspace |
| `scheme` | No | Auto-detect | Scheme name |
| `simulator` | No | Auto-detect (booted) | Simulator name or UDID |
| `configuration` | No | Debug | Build configuration |
| `args` | No | — | Launch arguments for the app |
| `env` | No | — | Environment for the app, `KEY=VALUE` strings |
| `url` | No | — | URL or deep link to open once the app is running |

**Returns:** Bundle ID, app path, PID, timings. On failure: structured build errors, or, when the app dies within 2s of launch, `App running: false` with the exception, reason, top frames of the crashed thread and the crash report path.

---

## clean

Clean the scheme's simulator build products for a configuration. `derivedData: true` also deletes this project's DerivedData folder, found from its `BUILD_ROOT` (never the whole DerivedData directory); that is the fix for "database is locked" or a stale index.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `project` | No | Auto-detect | Path to .xcodeproj or .xcworkspace |
| `scheme` | No | Auto-detect | Scheme name |
| `configuration` | No | Debug | Build configuration |
| `derivedData` | No | false | Also delete this project's DerivedData folder |

---

## discover_projects

Find .xcodeproj and .xcworkspace files in a directory tree.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `path` | **Yes** | — | Directory to search |

**Returns:** List of project/workspace paths found.

---

## list_schemes

List available schemes for a project.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `project` | No | Auto-detect | Path to .xcodeproj or .xcworkspace |

**Returns:** Array of scheme names.

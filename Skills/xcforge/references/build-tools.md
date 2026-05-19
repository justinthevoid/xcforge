# Build Tools (6 tools)

> **Defaults note:** the `Default` column shows the *fallback*. `project`,
> `scheme`, `simulator`, and `configuration` are resolved through the parameter
> precedence chain — a committed `.xcforge.yaml` (`configuration:` /
> `scheme:` / …) overrides the listed fallback when the parameter is omitted.
> See [auto-detection.md](auto-detection.md).

## build_compile

Fast compile-only build without install or launch (~5s vs ~20s for full pipeline). Reuses the standard build infrastructure, skips the simulator boot/install/launch chain.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `project` | No | Auto-detect | Path to .xcodeproj or .xcworkspace |
| `scheme` | No | Auto-detect | Scheme name |
| `simulator` | No | Auto-detect (booted) | Simulator name or UDID (for SDK selection) |
| `configuration` | No | Debug | Build configuration (Debug/Release) |
| `long` | No | false | Use 1800s timeout instead of default 180s |

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

Build + boot + install + launch in one call. Runs a parallel 2-phase pipeline: build and boot happen simultaneously, then install and launch. ~9s faster than calling each tool sequentially.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `project` | No | Auto-detect | Path to .xcodeproj or .xcworkspace |
| `scheme` | No | Auto-detect | Scheme name |
| `simulator` | No | Auto-detect (booted) | Simulator name or UDID |
| `configuration` | No | Debug | Build configuration |

**Returns:** Bundle ID, app path, simulator UDID, build duration. On failure: structured build errors.

This is the **Cmd+R equivalent** — the single most common tool call for iOS development.

---

## clean

Clean build artifacts (DerivedData for the project).

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `project` | No | Auto-detect | Path to .xcodeproj or .xcworkspace |
| `scheme` | No | Auto-detect | Scheme name |

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

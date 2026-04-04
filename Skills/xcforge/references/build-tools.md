# Build Tools (5 tools)

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

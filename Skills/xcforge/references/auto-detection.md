# Auto-Detection, Session Defaults & Profiles

## Parameter Resolution Order

All tools that accept `project`, `scheme`, or `simulator` resolve values in this order:

1. **Explicit parameter** — value passed directly in the tool call (highest priority)
2. **In-session value** — set this session via `set_defaults`/`profile_switch`, auto-promoted (3× rule), or already resolved earlier this session
3. **Repo config** — `.xcforge.yaml` at the repo root (committed team config; see below)
4. **Persisted defaults** — machine-global `~/.xcforge/defaults.json`
5. **Auto-detect** — runtime detection (see below)
6. **Error with options** — if auto-detect fails, returns available choices

> **Repo config beats persisted defaults.** The committed `.xcforge.yaml` is the
> team's source of truth for *this* repo, so it outranks the personal
> machine-global `~/.xcforge/defaults.json` — the same model as git
> (`local` config beats `global`). `set_defaults`/`profile_switch` still take
> effect *within the running session* (step 2), but no longer silently stick
> across restarts when the repo file specifies the same field. `set_defaults
> action: show` labels each value's source (`repo-config` vs `persisted`).

> **`bundle_id` and `app_path` are not repo-config keys.** They resolve via
> explicit parameter → the cache from the last successful `build_sim`/
> `build_run_sim` only. They are never read from `.xcforge.yaml` or
> `~/.xcforge/defaults.json`, and `.xcforge.yaml` has no key for them.

## Repo-Level Config (`.xcforge.yaml`)

A committed, repo-scoped config file discovered by walking up from the working
directory to the `.git` boundary. Optional — its absence changes nothing.

Flat `key: value` syntax only (no YAML library — no nesting, no quoting). Lines
starting with `#` are comments. Unknown keys are warned and ignored; a malformed
file is warned and skipped (never crashes).

| Key | Effect | Persisted? |
|-----|--------|------------|
| `project` | Default `.xcodeproj`/`.xcworkspace`. Relative paths resolve from the file's directory. | shared with defaults model |
| `scheme` | Default scheme. | shared with defaults model |
| `simulator` | Default simulator name or UDID. | shared with defaults model |
| `configuration` | Build configuration for `build_sim`/`test_sim`/`build_and_test`/`build_and_diagnose` when no `--configuration`/`configuration` arg is given. Default `Debug`. | **repo-only — never written to `defaults.json` or profiles** |
| `testPlan` | Default `.xctestplan` for `test_sim`/`build_and_test` when no `--testplan`/`testplan` arg is given. | **repo-only — never written to `defaults.json` or profiles** |

`configuration` and `testPlan` are repo-only by design and never flow into the
machine-global persisted JSON or named profiles.

### `xcforge init` (CLI)

Scaffold a documented `.xcforge.yaml` at the repo root:

```bash
xcforge init            # write commented .xcforge.yaml with detected values
xcforge init --force    # overwrite an existing file
```

- Writes at the git repo root (CWD if there is no `.git`).
- Pre-fills detected `project`/`scheme`/`simulator`; undetected keys are emitted
  as commented placeholders so the file is valid as written.
- Refuses to overwrite an existing `.xcforge.yaml` unless `--force` (prints the
  existing path and exits non-zero).
- CLI-only — there is no MCP `init` tool.

## Auto-Detection Logic

### project
- Scans working directory for `.xcodeproj` and `.xcworkspace` files
- If exactly one found, uses it automatically
- If multiple found, returns the list and asks for selection
- Prefers `.xcworkspace` over `.xcodeproj` when both exist (CocoaPods, SPM workspace)

### scheme
- Queries `xcodebuild -list` for the resolved project
- If exactly one scheme, uses it
- If multiple, returns the list

### simulator
- Finds currently booted simulator via `simctl list devices`
- If exactly one booted, uses it
- If none booted, returns available simulators
- If multiple booted, uses the first one

### bundle_id
- Cached from the last successful `build_sim` or `build_run_sim` call
- Parsed from the build output (Info.plist of the built .app)

### app_path
- Cached from the last successful `build_sim` or `build_run_sim` call
- Points to the .app bundle in DerivedData

## Auto-Promotion

When the same explicit value is passed **3 consecutive times** for a parameter, xcforge auto-promotes it to a session default. This avoids the need to call `set_defaults` explicitly for repeated workflows.

Example: calling `build_sim(scheme: "MyApp")` 3 times in a row auto-saves "MyApp" as the default scheme.

## set_defaults (MCP tool)

Manage session defaults. Supports set, show, and clear actions.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `action` | No | `set` | Action: `set` (update defaults), `show` (display current), `clear` (remove all) |
| `project` | No | — | Default project path (used with `set` action) |
| `scheme` | No | — | Default scheme name (used with `set` action) |
| `simulator` | No | — | Default simulator name or UDID (used with `set` action) |

All parameters are optional — set only what you want to change.

**Persistence:** Defaults survive across MCP sessions. They're stored on disk at `~/.xcforge/defaults.json`. Note these are machine-global and ranked *below* a repo's committed `.xcforge.yaml` — for repo-scoped team defaults, prefer `xcforge init` and `.xcforge.yaml`.

**Best practice:** Call `set_defaults` at the start of a session to avoid repeating parameters:
```
set_defaults(project: "MyApp.xcodeproj", scheme: "MyApp", simulator: "iPhone 16 Pro")
build_sim()          # uses defaults
test_sim()           # uses defaults
screenshot()         # uses defaults
```

## Session Profiles (4 MCP tools)

Save and switch between named sets of defaults. Useful when working across multiple targets or device configurations.

### profile_save

Save current session defaults as a named profile.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `name` | **Yes** | — | Profile name (kebab-case, max 32 chars, e.g., `"iphone-debug"`) |

**Validation:** Names must be lowercase alphanumeric with hyphens only, cannot start or end with hyphens.

### profile_switch

Switch session defaults to a previously saved profile.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `name` | **Yes** | — | Profile name to activate |

**Returns:** Confirmation with profile contents, or error listing available profiles.

### profile_list

List all saved session profiles. No parameters.

### profile_delete

Delete a saved session profile.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `name` | **Yes** | — | Profile name to delete |

### Profile Workflow

```
set_defaults(project: "MyApp.xcodeproj", scheme: "MyApp", simulator: "iPhone 16 Pro")
profile_save(name: "iphone-debug")

set_defaults(simulator: "iPad Pro 13-inch (M4)")
profile_save(name: "ipad-debug")

profile_switch(name: "iphone-debug")    # instant context switch
profile_list()                          # see all saved profiles
```

## xcforge defaults (CLI)

Same functionality from the terminal:

```bash
xcforge defaults show                    # View current defaults
xcforge defaults set --scheme MyApp      # Set a default
xcforge defaults clear                   # Remove all defaults
```

See [CLI Commands](cli-commands.md) for full details.

**Note:** Session profiles (save/switch/list/delete) are MCP-only — there are no CLI equivalents.

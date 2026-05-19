# Auto-Detection, Session Defaults & Profiles

## Parameter Resolution Order

All tools that accept `project`, `scheme`, or `simulator` resolve values in this order:

1. **Explicit parameter** — value passed directly in the tool call (highest priority)
2. **In-session value** — set this session via `set_defaults`/`profile_switch`, auto-promoted (3× rule, unless `autoPromote: false`), or already resolved earlier this session
3. **Repo config** — `.xcforge.yaml` at the repo root (committed team config; see below)
4. **Persisted defaults (per active project)** — the active project's record in `~/.xcforge/defaults.json`
5. **Auto-detect** — runtime detection (see below)
6. **Error with options** — if auto-detect fails, returns available choices

> **Repo config beats persisted defaults.** The committed `.xcforge.yaml` is the
> team's source of truth for *this* repo, so it outranks the personal
> machine-global `~/.xcforge/defaults.json` — the same model as git
> (`local` config beats `global`). `set_defaults`/`profile_switch` still take
> effect *within the running session* (step 2), but no longer silently stick
> across restarts when the repo file specifies the same field. `set_defaults
> action: show` labels each value's source (`repo-config` vs `persisted`).

> **There is no global "persisted project" fallback.** Project identity is
> resolved from step 1, 3, or 5 — never from `defaults.json`. The persisted
> store is keyed by canonical project path (`version: 2` envelope), so once a
> project is identified, *that* project's record supplies its scheme/simulator
> fallback and remembered build products. Each project on the machine has its
> own isolated record; building App A no longer leaks its `bundleId`/`appPath`
> into a later session for App B.

> **`bundle_id` and `app_path` are not repo-config keys.** They resolve via
> explicit parameter → the cache from the last successful `build_sim`/
> `build_run_sim` for the **active project's record only**. They are never
> read from `.xcforge.yaml`, never from another project's record, and
> `.xcforge.yaml` has no key for them.

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
| `testTimeout` | Per-project default test timeout, positive integer seconds. Precedence: explicit `timeoutSeconds` > `testTimeout` > `--long`/180s default. Non-positive values rejected with warning. | **repo-only** |
| `autoPromote` | `true` (default) keeps the 3-rep auto-promotion. `false` disables it (streak counter held at zero) so explicit values stay explicit across repeated iterative runs. | **repo-only** |

`configuration`, `testPlan`, `testTimeout`, and `autoPromote` are repo-only by
design and never flow into the machine-global persisted JSON or named profiles.

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

**Opt out:** set `autoPromote: false` in `.xcforge.yaml`. The streak counter then stays at zero, so explicit values never get promoted — useful for iterative test loops where you want each call to stand on its own. Auto-promotion is also no longer sticky after the fact: `set_defaults` resets the matching field's streak so an old explicit value can't ambush a later run after you've overridden it.

## set_defaults (MCP tool)

Manage session defaults. Supports set, show, and clear actions.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `action` | No | `set` | Action: `set` (update defaults), `show` (display current), `clear` (remove all) |
| `project` | No | — | Default project path (used with `set` action) |
| `scheme` | No | — | Default scheme name (used with `set` action) |
| `simulator` | No | — | Default simulator name or UDID (used with `set` action) |

All parameters are optional — set only what you want to change.

**Persistence:** Defaults survive across MCP sessions in a `version: 2` envelope at `~/.xcforge/defaults.json` keyed by canonical project path — each project has its own isolated record so build products from App A can't leak into a session for App B. `set_defaults` writes into the **active project's record only**; if no project is resolved yet, it logs a warning and applies in-memory only. The store is machine-global and ranked *below* a repo's committed `.xcforge.yaml` — for repo-scoped team defaults, prefer `xcforge init` and `.xcforge.yaml`.

Old flat files (single record, no `version` field) auto-migrate on first read when they carry a `project:` field; unrecognized or forward-version (`v3+`) files are backed up to `defaults.json.unrecognized-<timestamp>` instead of being overwritten.

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
xcforge defaults show                    # Active project's record + repo-config keys
xcforge defaults set --scheme MyApp      # Set the active project's default scheme
xcforge defaults clear                   # Clear ONLY the active project's record
xcforge defaults clear --all             # Wipe every project's record on this machine
```

`clear` (no `--all`) auto-resolves the active project before clearing; if no project can be detected from cwd, it reports that and exits cleanly without touching disk.

See [CLI Commands](cli-commands.md) for full details.

**Note:** Session profiles (save/switch/list/delete) are MCP-only — there are no CLI equivalents.

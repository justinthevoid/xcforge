# Auto-Detection, Session Defaults & Profiles

## Parameter Resolution Order

All tools that accept `project`, `scheme`, `simulator`, `bundle_id`, or `app_path` resolve values in this order:

1. **Explicit parameter** — value passed directly in the tool call (highest priority)
2. **Session default** — persisted via `set_defaults` tool or `xcforge defaults set` CLI
3. **Auto-detect** — runtime detection (see below)
4. **Error with options** — if auto-detect fails, returns available choices

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

**Persistence:** Defaults survive across MCP sessions. They're stored on disk at `~/.xcforge/defaults.json`.

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

# Simulator Tools (17 tools)

## list_sims

List available iOS simulators with state and UDID.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `filter` | No | — | Filter by name substring (case-insensitive) |

**Returns:** Array of simulators with name, UDID, state (Booted/Shutdown), runtime (e.g., iOS 18.2).

---

## boot_sim

Boot a simulator.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `simulator` | **Yes** | — | Simulator name or UDID |

**Note:** If the simulator is already booted, this is a no-op (not an error).

---

## shutdown_sim

Shut down a running simulator.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `simulator` | **Yes** | — | Simulator name, UDID, or `"all"` to shut down all booted simulators |

---

## install_app

Install a .app bundle on a simulator.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `simulator` | No | Auto-detect (booted) | Simulator name or UDID |
| `app_path` | No | Auto-detect (last build) | Path to .app bundle |

**Auto-detection:** Uses the app path cached from the last `build_sim` or `build_run_sim` call.

---

## launch_app

Launch an installed app.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `simulator` | No | Auto-detect (booted) | Simulator name or UDID |
| `bundle_id` | No | Auto-detect (last build) | App bundle identifier |

---

## terminate_app

Terminate a running app.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `simulator` | No | Auto-detect (booted) | Simulator name or UDID |
| `bundle_id` | No | Auto-detect (last build) | App bundle identifier |

---

## clone_sim

Clone a simulator to snapshot its current state (apps, data, settings).

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `simulator` | **Yes** | — | Source simulator name or UDID |
| `name` | **Yes** | — | Name for the cloned simulator |

**Use case:** Create a pre-configured simulator with test data installed, then clone it for fresh test runs.

---

## erase_sim

Factory reset a simulator — removes all apps, data, and settings.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `simulator` | **Yes** | — | Simulator name, UDID, or `"all"` |

**Warning:** Destructive operation. Cannot be undone.

---

## delete_sim

Permanently delete a simulator device.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `simulator` | **Yes** | — | Simulator name or UDID |

**Warning:** Destructive and irreversible. The simulator must be shut down first.

---

## record_video_start

Start recording simulator screen to a .mov video file.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `simulator` | No | Auto-detect (booted) | Simulator name or UDID |
| `path` | No | `/tmp/xcforge-recording-<timestamp>.mov` | Output file path |

**Returns:** Output file path. Only one recording can be active at a time.

**Note:** Call `record_video_stop` to finish recording and finalize the file.

---

## record_video_stop

Stop an active video recording and return the file path.

No parameters.

**Returns:** File path of the completed recording, or error if no recording is active.

---

## set_sim_location

Set simulated GPS location on a simulator.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `simulator` | No | Auto-detect (booted) | Simulator name or UDID |
| `latitude` | **Yes** | — | Latitude coordinate (e.g., 37.7749) |
| `longitude` | **Yes** | — | Longitude coordinate (e.g., -122.4194) |

---

## reset_sim_location

Reset simulator location to default (removes any simulated GPS override).

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `simulator` | No | Auto-detect (booted) | Simulator name or UDID |

---

## set_sim_appearance

Set simulator appearance to light or dark mode.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `simulator` | No | Auto-detect (booted) | Simulator name or UDID |
| `appearance` | **Yes** | — | `light` or `dark` |

---

## sim_statusbar

Override simulator status bar values for clean screenshots.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `simulator` | No | Auto-detect (booted) | Simulator name or UDID |
| `time` | No | — | Time string to display (e.g., `"9:41"`) |
| `battery_level` | No | — | Battery level percentage (0-100) |
| `battery_state` | No | — | `charging`, `charged`, or `discharging` |
| `cellular_bars` | No | — | Cellular signal bars (0-4) |
| `wifi_bars` | No | — | WiFi signal bars (0-3) |
| `operator_name` | No | — | Carrier name to display |

At least one override parameter is required.

**Use case:** Set consistent status bar for App Store screenshots.

---

## sim_statusbar_clear

Clear all status bar overrides and restore default values.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `simulator` | No | Auto-detect (booted) | Simulator name or UDID |

---

## set_orientation

Set device orientation via WebDriverAgent.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `orientation` | **Yes** | — | One of: `PORTRAIT`, `LANDSCAPE`, `LANDSCAPE_LEFT`, `LANDSCAPE_RIGHT` |

**Requires:** WDA running on the simulator.

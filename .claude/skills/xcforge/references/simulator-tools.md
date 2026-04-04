# Simulator Tools (10 tools)

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

## set_orientation

Set device orientation via WebDriverAgent.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `orientation` | **Yes** | — | One of: `PORTRAIT`, `LANDSCAPE`, `LANDSCAPE_LEFT`, `LANDSCAPE_RIGHT` |

**Requires:** WDA running on the simulator.

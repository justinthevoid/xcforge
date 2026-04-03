# Device Tools (7 tools)

Physical iOS/iPadOS device management via `xcrun devicectl`. All tools require a connected device (USB or WiFi).

## list_devices

List connected physical iOS/iPadOS devices.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `filter` | No | — | Filter by name, UDID, or OS version (case-insensitive) |

**Returns:** Array of devices with name, UDID, OS version, state, connection type.

---

## device_info

Get detailed information about a connected physical device.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `device` | **Yes** | — | Device name, UDID, or serial number |

**Returns:** Name, OS version, UDID, model, platform, connection type.

---

## device_install

Install an .app bundle on a connected physical device.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `device` | **Yes** | — | Device name or UDID |
| `app_path` | **Yes** | — | Path to the .app bundle |

**Timeout:** 120 seconds.

**Returns:** Bundle ID of installed app.

---

## device_uninstall

Uninstall an app from a connected physical device by bundle ID.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `device` | **Yes** | — | Device name or UDID |
| `bundle_id` | **Yes** | — | Bundle identifier of the app to uninstall |

---

## device_launch

Launch an app on a connected physical device.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `device` | **Yes** | — | Device name or UDID |
| `bundle_id` | **Yes** | — | Bundle identifier of the app |
| `console` | No | false | Attach console and wait for app exit |
| `terminate_existing` | No | true | Terminate existing instance before launching |
| `timeout` | No | 30 | Console timeout in seconds |
| `arguments` | No | — | Array of arguments passed to the app |

**Returns:** Launch confirmation and optional console output (if `console: true`).

---

## device_terminate

Terminate a running process on a connected physical device.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `device` | **Yes** | — | Device name or UDID |
| `identifier` | **Yes** | — | Bundle ID or PID of the process to terminate |

---

## device_apps

List apps installed on a connected physical device.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `device` | **Yes** | — | Device name or UDID |
| `include_system` | No | false | Include system/built-in apps |
| `bundle_id` | No | — | Filter to a specific bundle ID |

**Returns:** Array of apps with bundle ID, name, and version.

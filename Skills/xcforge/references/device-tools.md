# Device Tools (10 tools)

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
| `url` | No | — | Deep link or universal link opened in the app at launch |
| `env` | No | — | Object of environment variables for the app |

CLI: `xcforge device launch <bundle-id> --device <udid> [--url myapp://x] [--env KEY=VALUE] [--arg A]`.

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

---

## device_screenshot

Save a PNG of the device screen. Uses `devicectl device capture screenshot` (Xcode 26.6 and later), then the device's WebDriverAgent when `wda_start` has one running.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `device` | **Yes** | — | Device name or UDID |
| `path` | No | artifact dir | Where to write the PNG |

CLI: `xcforge device screenshot --device <udid> [--output shot.png]`.

---

## wda_start / wda_stop (UI automation on a real device)

`wda_start` builds xcforgeWDA for the device, signs it with your team (`-allowProvisioningUpdates`), launches it with `xcodebuild test-without-building` in the background, and finds its URL (the CoreDevice tunnel address, else the URL WDA logs). The MCP session's UI tools (`find_element`, `click_element`, `type_text`, ...) then target the device. A runner that already answers is reused.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `device` | **Yes** | — | Device name or UDID |
| `team` | No | `XCFORGE_WDA_TEAM` | Development team ID for signing |
| `bundle_id` | No | `com.xcforge.wda.<team>.runner` | Runner bundle id |
| `port` | No | 8100 | Port WDA listens on |

CLI:

```bash
xcforge wda start --device <udid> --team ABCDE12345
export XCFORGE_DEVICE=<udid>     # ui commands now use the device's runner
xcforge ui tap --label "Sign In"
xcforge wda status
xcforge wda stop --device <udid>
```

Before starting, the device must be unlocked, in Developer Mode, and have **Settings > Developer > Enable UI Automation** on. Failures name which of these (or signing, pairing, an untrusted certificate) is the problem. UI tools never run simulator recovery against a device: when its runner stops answering they say so and point at `wda start`.

State lives in `~/.xcforge/wda/<udid>.json` (URL, runner pid, log path), so other sessions on the Mac reuse the same runner. The build goes through the shared build lock when one is configured.

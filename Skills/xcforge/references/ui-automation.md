# UI Automation Tools (13 tools)

All UI tools communicate directly with WebDriverAgent via HTTP — no Appium, no Node.js, no Python.

**Prerequisite:** WebDriverAgent must be running on the target simulator. Check with `wda_status`.

**Which screen.** Every UI tool takes `simulator` (name or UDID). Each simulator gets its own
WebDriverAgent on its own port (8100 up, saved in `~/.xcforge/wda/simulator-ports.json`), so with
two simulators booted the screenshot and the taps go to the same one. The last simulator named is
used when a call names none; until then calls go to the booted simulator. From the CLI, set
`XCFORGE_SIMULATOR=<name or UDID>` (`XCFORGE_DEVICE` for a phone).

**Waiting instead of sleeping.** Taps, swipes, typing and `handle_alert` take `waitFor` (an
accessibility id or label to appear), `untilGone` (one to disappear) and `timeout` (seconds,
default 10). The result says whether the wait held; a wait that times out marks the call as an error.

**Merged tools.** `tap` replaces eight tap tools, `swipe` takes `hid`, `get_source` takes
`format: list` (was `list_elements`), and `find_element` takes `all` (was `find_elements`). The old
names still work for one release and say what replaces them.

**Permission alerts.** `alert_action: accept|dismiss` on `wda_create_session` (or
`XCFORGE_ALERT_ACTION`) has WDA answer system alerts by itself. `sim_privacy grant` grants a
permission before the app asks. A "not found" error says when an alert is in the way.

## wda_status

Check if WebDriverAgent is running and reachable.

No parameters.

**Returns:** WDA status, session info, device info.

---

## wda_create_session

Create a new WDA session, optionally activating an app.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `bundle_id` | No | — | App to activate (optional) |
| `wda_url` | No | http://localhost:8100 | Custom WDA URL |
| `alert_action` | No | `none` | `accept` or `dismiss` system alerts automatically for this session |

A session xcforge recreates by itself (after a WDA hiccup or restart) never relaunches the app
(`forceAppLaunch: false`), so screen state and launch arguments survive.

**Bundle id binding (v1.4.1+).** When `bundle_id` is provided, `WDAClient` persists
it as the active bundle id and threads it through every subsequent recreate
(mid-call session-dead retry, WDA restart). Auto-bootstrapped sessions therefore
stay bound to the app under test rather than reverting to whatever app WDA picks.
The CLI form (`xcforge ui session --bundle-id <id>`) verifies the binding via
`GET /session/<sid>` and exits non-zero on a `CFBundleIdentifier` mismatch — silent
no-binds become explicit failures. Empty/whitespace bundle ids are rejected.

**WDA can't see SwiftUI sheets — improved in v1.4.1.** Earlier releases needed
the bundle-id binding above and still missed `.sheet` / `fullScreenCover`
content because `XCUIApplication.snapshotWithError:` only walks the keyWindow.
As of v1.4.1, WDA reads sheet-window content automatically for source dumps
and coordinate taps — `/source` (json/xml/description) merges per-window
snapshots when the app exposes more than one `UIWindow`, and coordinate
`/wda/tap` re-roots on the topmost hittable window. Element find retries the
sheet window only when the keyWindow query returns no matches, so an id that
exists in *both* windows resolves to the keyWindow element. If `ui ls` still
misses sheet elements, file a bug with `--source wda` output attached.

**Structured failure + bounded auto-heal.** A failed default-path
`wda_create_session` no longer returns the opaque
`Session creation failed: ExitCode(rawValue: 1)`. It returns a structured body:

- `error: "wda_session_create_failed"`
- `cause` — one of `wda_runner_not_running`, `wda_runner_build_failed`,
  `no_booted_simulator`, `bundle_not_installed`, `session_bind_rejected`,
  `unknown` (with raw stderr in `detail`)
- `detail` — human explanation
- `remediation` — a copy-pasteable command
- `recovered` — `true` if the bounded one-shot auto-heal succeeded
- `appForeground` — `true`/`false` whenever WDA can resolve the foreground
  bundle; null/omitted only when WDA is unreachable or the foreground bundle is
  unresolvable (never a false negative). Additive (`encodeIfPresent`)

Classification uses cheap state probes (booted simulator? `:8100` reachable?
`xcforgeWDA-deploy` DerivedData present?). On a recoverable runner cause it
attempts **exactly one** bounded rebuild+relaunch+rebind via the existing
`ensureWDARunning()` orchestrator (its policy is *not* widened — this is only a
one-shot wrapper at the `ui session` level, never inside the element-path
`ensureSession()`). A `session_bind_rejected` (WDA bound a different bundle than
requested) is **not** auto-recovered — the app/bundle is the problem, not the
runner — and fails fast with the structured detail. The CLI form
(`xcforge ui session`) supports `--no-autoheal` (preserve fail-fast) and
`--relaunch-app` (opt-in; auto-heal never relaunches the user app otherwise).

**`appForeground` on interaction results.** `tap_by_id`, `tap_by`,
`click_element`, `find_element`, and `screenshot` append/emit an
`appForeground` token (`true`/`false`) **whenever WDA can resolve the
foreground bundle** — derived from `verifyActiveBundleId()` vs the recorded
active bundle, **not** WDA `/status` (which reflects the WDA process, not the
target app). It is null/omitted only when WDA is unreachable or the foreground
bundle is unresolvable, so an agent never sees a false negative. The field is
additive (`encodeIfPresent`; old consumers ignore unknown keys).

---

## handle_alert

The smartest alert handler available. Handles system permission dialogs, ContactsUI dialogs, and in-app alerts.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `action` | **Yes** | — | `accept`, `dismiss`, `get_text`, `accept_all`, `dismiss_all` |
| `button_label` | No | Smart default | Specific button text to tap |

**3-tier alert search order:**
1. **Springboard** — system dialogs (Location, Camera, Notifications, Tracking)
2. **ContactsUI** — iOS 18+ Contacts "Limited Access" dialog (separate process)
3. **Active app** — in-app UIAlertController

**Smart button defaults:**
- Accept: Allow > Allow While Using App > OK > Continue > last button
- Dismiss: Don't Allow > Cancel > Not Now > first button

**Batch modes:** `accept_all` / `dismiss_all` loop server-side through all visible alerts. Returns details of every handled alert. One HTTP roundtrip instead of N.

**Best practice:** Call `handle_alert(action: "accept_all")` immediately after first app launch to clear all permission dialogs in one call.

---

## tap

Tap one target. Pass exactly one of `elementId`, `id`, `using` + `value`, or `x` + `y`.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `elementId` | One target | — | Element ID from `find_element` |
| `id` | One target | — | Accessibility id; found and tapped in one call, re-found and retried once if stale |
| `using` + `value` | One target | — | Any WDA query (`accessibility id`, `class name`, `predicate string`, `class chain`), same retry |
| `x` + `y` | One target | — | Point coordinates (screenshot pixels with `pixels: true`) |
| `count` | No | 1 | 2 double-taps. Needs `x`, `y` |
| `durationMs` | No | — | Hold this long (long press). Needs `x`, `y` |
| `pixels` | No | false | `x`, `y` are screenshot pixels, divided by the simulator's scale |
| `hid` | No | false | Native HID on a simulator (sub-5ms, bypasses WDA, falls back to it). Not yet supported on Xcode 27: WDA is used and the result says so |

Coordinates are in the interface's own points. With `hid`, WDA's orientation is read first so taps
land correctly in landscape and upside down (inferred mapping; check on a Mac).

**Replaces** (still callable for one release, with a note in the result): `click_element`
(`elementId`), `tap_by_id` (`id`), `tap_by` (`using`, `value`), `tap_coordinates` (`x`, `y`),
`double_tap` (`count: 2`), `long_press` (`durationMs`), `ui_tap_pixel` (`pixels: true`),
`indigo_tap` (`hid: true`).

---

## find_element

Find a single UI element. Supports auto-scrolling to off-screen elements.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `using` | **Yes** | — | Strategy: `"accessibility id"`, `"class name"`, `"predicate string"`, `"class chain"` |
| `value` | **Yes** | — | Search value matching the strategy |
| `scroll` | No | false | Enable auto-scroll to find off-screen elements |
| `direction` | No | auto | Scroll direction: `auto` (smart — detects boundaries, reverses automatically), `up`, `down`, `left`, `right` |
| `maxSwipes` | No | 10 | Maximum scroll attempts |
| `index` | No | 0 | Which match to use when several match |
| `timeout` | No | — | Seconds to wait for the element to appear |
| `untilGone` | No | false | Wait for the element to disappear instead |
| `all` | No | false | Return every match's element ID, rect, label and type (counting list items) |

When several elements match, the result says how many and lists up to 10 with their label and
frame, so you can pick one with `index` or tighten the query.

**Auto-scroll 3-tier fallback:**
1. `scrollToVisible` — WDA native scroll (works with UIKit)
2. Calculated drag — computed from screen geometry
3. Iterative swipe — with stall detection and automatic direction reversal

**Returns:** Element ID (use with `tap`, `get_text`, etc.), element rect, label, type.

### Strategy Guide

| Strategy | Example Value | Best For |
|----------|--------------|----------|
| `accessibility id` | `"Save"`, `"login_button"` | Elements with accessibility identifiers (most reliable) |
| `predicate string` | `"label == 'Submit' AND type == 'XCUIElementTypeButton'"` | Complex queries with multiple conditions |
| `class chain` | `"**/XCUIElementTypeCell[\`label CONTAINS 'Item'\`]"` | Hierarchical queries, table cells |
| `class name` | `"XCUIElementTypeButton"` | Find by element type (least specific) |

---

## swipe

Swipe from one point to another.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `startX` | **Yes** | — | Start X (points) |
| `startY` | **Yes** | — | Start Y (points) |
| `endX` | **Yes** | — | End X (points) |
| `endY` | **Yes** | — | End Y (points) |
| `durationMs` | No | 300 | Swipe duration in milliseconds |
| `hid` | No | false | Native HID on a simulator (sub-5ms per step, bypasses WDA, falls back to it). Not yet supported on Xcode 27: WDA is used and the result says so |

---

## pinch

Pinch/zoom gesture.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `center_x` | **Yes** | — | Center X coordinate |
| `center_y` | **Yes** | — | Center Y coordinate |
| `scale` | **Yes** | — | Scale factor: >1 = zoom in, <1 = zoom out |
| `duration_ms` | No | 500 | Gesture duration |

---

## drag_and_drop

Element-to-element or coordinate-based drag and drop. 1 call instead of 3.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `source_element` | No* | — | Source element ID |
| `from_x` | No* | — | Source X coordinate |
| `from_y` | No* | — | Source Y coordinate |
| `target_element` | No* | — | Target element ID |
| `to_x` | No* | — | Target X coordinate |
| `to_y` | No* | — | Target Y coordinate |
| `press_duration_ms` | No | 1000 | How long to press before dragging |
| `hold_duration_ms` | No | 300 | How long to hold over target before dropping |

*Provide either `source_element` OR `from_x`/`from_y` for source. Same for target. Can mix element and coordinate modes.

**Use cases:** Reorderable lists, Kanban boards, sliders, canvas objects.

---

## type_text

Type text into the focused element, or a specified one. Fails when nothing has focus and no
element is given (tap the field first).

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `text` | No | — | Text to type |
| `element_id` | No | Currently focused | Target element |
| `clear_first` | No | false | Clear existing text before typing |
| `key` | No | — | Named key to press after the text: `return`, `delete`, `tab`, `escape` |
| `dismiss_keyboard` | No | false | Hide the keyboard afterwards |
| `secure` | No | auto | Keep the text out of the result (automatic for secure fields) |

---

## get_text

Get text content of an element.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `element_id` | **Yes** | — | Element ID |

---

## get_source

The on-screen view hierarchy. Starts WebDriverAgent when it isn't running.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `format` | No | json | `list`, `json`, `xml` or `description` |
| `scope` | No | — | `format: list` only: a11y-id to restrict the listing to, with its descendants |
| `source` | No | `auto` | `format: list` only: `auto` (WDA when a simulator is booted, else AXP), `wda`, `axp` |

**`format: list`** (CLI: `xcforge ui ls`) is the cheap one: one line per element,
`<a11y-id> | <label> | <type> | <x>,<y>,<w>,<h>`, then ` | value=…`, ` | disabled` and ` | selected`
when they apply. Wrapper containers with nothing to say, hidden elements and off-screen elements are
left out; output is cut at an element boundary at 50KB.

**Source policy.** `auto` uses WDA (starting it when needed) whenever a simulator is booted or
WDA points at a phone, with no fallback: a failure is reported rather than answered from the
Simulator app's own accessibility tree. The macOS accessibility tree (`axp`) reads only the
simulator's windows and is used as a shortcut only when exactly one simulator is booted and no
phone is attached.

The other formats return the entire tree; use them sparingly.

---

## clipboard_get

Read the device clipboard (pasteboard) content via WDA.

No parameters.

**Returns:** String content of the clipboard.

**Requires:** WDA running on the simulator.

---

## clipboard_set

Write text to the device clipboard (pasteboard) via WDA.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `text` | **Yes** | — | Text to copy to clipboard |

**Requires:** WDA running on the simulator.

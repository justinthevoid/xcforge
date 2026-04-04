# UI Automation Tools (19 tools)

All UI tools communicate directly with WebDriverAgent via HTTP — no Appium, no Node.js, no Python.

**Prerequisite:** WebDriverAgent must be running on the target simulator. Check with `wda_status`.

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

## find_element

Find a single UI element. Supports auto-scrolling to off-screen elements.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `using` | **Yes** | — | Strategy: `"accessibility id"`, `"class name"`, `"predicate string"`, `"class chain"` |
| `value` | **Yes** | — | Search value matching the strategy |
| `scroll` | No | false | Enable auto-scroll to find off-screen elements |
| `direction` | No | auto | Scroll direction: `auto` (smart — detects boundaries, reverses automatically), `up`, `down`, `left`, `right` |
| `max_swipes` | No | 10 | Maximum scroll attempts |

**Auto-scroll 3-tier fallback:**
1. `scrollToVisible` — WDA native scroll (works with UIKit)
2. Calculated drag — computed from screen geometry
3. Iterative swipe — with stall detection and automatic direction reversal

**Returns:** Element ID (use with `click_element`, `get_text`, etc.), element rect, label, type.

### Strategy Guide

| Strategy | Example Value | Best For |
|----------|--------------|----------|
| `accessibility id` | `"Save"`, `"login_button"` | Elements with accessibility identifiers (most reliable) |
| `predicate string` | `"label == 'Submit' AND type == 'XCUIElementTypeButton'"` | Complex queries with multiple conditions |
| `class chain` | `"**/XCUIElementTypeCell[\`label CONTAINS 'Item'\`]"` | Hierarchical queries, table cells |
| `class name` | `"XCUIElementTypeButton"` | Find by element type (least specific) |

---

## find_elements

Find multiple matching elements.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `using` | **Yes** | — | Same strategies as `find_element` |
| `value` | **Yes** | — | Search value |

**Returns:** Array of element IDs with rects, labels, types.

---

## click_element

Tap a UI element by ID.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `element_id` | **Yes** | — | Element ID from `find_element`/`find_elements` |

---

## tap_coordinates

Tap at specific screen coordinates.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `x` | **Yes** | — | X coordinate |
| `y` | **Yes** | — | Y coordinate |

---

## double_tap

Double-tap at coordinates.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `x` | **Yes** | — | X coordinate |
| `y` | **Yes** | — | Y coordinate |

---

## long_press

Long-press at coordinates with optional duration.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `x` | **Yes** | — | X coordinate |
| `y` | **Yes** | — | Y coordinate |
| `duration_ms` | No | 1000 | Press duration in milliseconds |

---

## swipe

Swipe from one point to another.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `start_x` | **Yes** | — | Start X coordinate |
| `start_y` | **Yes** | — | Start Y coordinate |
| `end_x` | **Yes** | — | End X coordinate |
| `end_y` | **Yes** | — | End Y coordinate |
| `duration_ms` | No | 300 | Swipe duration in milliseconds |

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

Type text into focused or specified element.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `text` | **Yes** | — | Text to type |
| `element_id` | No | Currently focused | Target element |
| `clear_first` | No | false | Clear existing text before typing |

---

## get_text

Get text content of an element.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `element_id` | **Yes** | — | Element ID |

---

## get_source

Get the full view hierarchy.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `format` | No | json | Output format: `json`, `xml`, `description` |

**Performance:** ~20ms latency (750x faster than competition).

**Use sparingly** — returns the entire UI tree. Prefer `find_element` for targeted lookups.

---

## indigo_tap

Tap at coordinates via native HID (sub-5ms, bypasses WDA). Falls back to WDA if unavailable.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `x` | **Yes** | — | X coordinate (points) |
| `y` | **Yes** | — | Y coordinate (points) |
| `simulator` | No | `"booted"` | Simulator UDID or `"booted"` |

**Performance:** Sub-5ms latency via native HID when available, vs ~50ms via WDA.

---

## indigo_swipe

Swipe via native HID (sub-5ms per step, bypasses WDA). Falls back to WDA if unavailable.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `start_x` | **Yes** | — | Start X (points) |
| `start_y` | **Yes** | — | Start Y (points) |
| `end_x` | **Yes** | — | End X (points) |
| `end_y` | **Yes** | — | End Y (points) |
| `duration_ms` | No | 300 | Swipe duration in milliseconds |
| `simulator` | No | `"booted"` | Simulator UDID or `"booted"` |

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

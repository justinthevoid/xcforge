# Screenshot & Visual Tools (7 tools)

## screenshot

Take a simulator screenshot. 0.3s latency — 44x faster than alternatives.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `simulator` | No | Auto-detect (booted) | Simulator name or UDID |
| `device` | No | — | A physical device's name or UDID: captures it instead (was `device_screenshot`) |
| `format` | No | jpeg | Image format: `png` or `jpeg` |
| `grid` | No | false | Overlay a point-coordinate grid on the image |
| `crop` | No | — | `x,y,width,height` in device points (the coordinates taps use) |
| `maxDimension` | No | — | Shrink so the longer side is at most this many pixels |
| `waitFor` / `timeout` | No | — | Readiness signal to wait for before capturing |

**Token budget.** A full-resolution iPhone screenshot costs several thousand tokens. Pass
`maxDimension: 800` for a look at the screen, and `crop` to see one area at full detail. The
result line gives the device's point size, the crop, the output pixels and, when scaled, how
many points one pixel covers, so coordinates read off the image map back to taps.

**3-tier capture strategy:**
1. **Burst** — native CoreSimulator IOSurface framebuffer access (~10ms)
2. **Stream** — ScreenCaptureKit fallback (~20ms)
3. **Safe** — simctl io screenshot last resort (~320ms)

**Grid overlay:** When `grid: true`, overlays a transparent grid with 50pt minor lines and 100pt labeled divisions. Displays both X and Y axis labels at 100pt intervals. Falls back to ungridded image with a warning if overlay allocation fails.

**Returns:** Inline base64 image + metadata: device size in points (from the simulator's
screen, not the Simulator window), pixel size, byte size, capture method. The CLI
(`xcforge screenshot capture`, with `--crop` and `--max-dimension`) writes a new file per capture
unless `--output` is given.

Use `jpeg` (default) for fastest transfer. Use `png` for pixel-perfect visual regression baselines. Use `grid: true` for coordinate verification during layout work or UI automation scripting.

---

## save_visual_baseline

Save a screenshot as a named baseline for later comparison.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `name` | **Yes** | — | Baseline name (e.g., `"login-screen"`, `"settings-dark"`) |
| `simulator` | No | Auto-detect (booted) | Simulator name or UDID |
| `baseline_dir` | No | `visual-baselines/` | Directory to store baselines (relative to working directory) |

**Returns:** Baseline file path, resolution.

---

## compare_visual

Compare current screenshot against a saved baseline. Returns pixel-level diff.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `name` | **Yes** | — | Baseline name to compare against |
| `simulator` | No | Auto-detect (booted) | Simulator name or UDID |
| `threshold` | No | 0.5 | Acceptable diff percentage (0.0 = exact match) |
| `baseline_dir` | No | `visual-baselines/` | Directory containing baselines (relative to working directory) |

**Returns:** Match status (pass/fail), diff percentage, diff image path (highlights changed pixels).

---

## multi_device_check

Run visual checks across multiple simulators in parallel. Installs and launches the app on each device, optionally with Dark Mode and Landscape variants.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `app_path` | **Yes** | — | Path to .app bundle |
| `bundle_id` | No | Auto-detect | App bundle identifier |
| `simulators` | **Yes** | — | Comma-separated simulator names (e.g., `"iPhone 16,iPad Pro 13-inch (M4)"`) |
| `dark_mode` | No | false | Also test Dark Mode appearance |
| `landscape` | No | false | Also test Landscape orientation |
| `settle_time` | No | 3 | Seconds to wait after launch before screenshot |
| `threshold` | No | 1.0 | Pixel diff threshold percentage for same-resolution pairs |

**Returns per device (and variant):**
- Inline screenshot
- Device info
- Pixel diff percentage (for same-resolution pairs)
- Layout Score (consistency metric across devices)

**Use case:** Verify a UI change looks correct on iPhone SE, iPhone 16 Pro Max, and iPad simultaneously with Dark Mode variants.

---

## bless

Codify the baseline-write → test → diff → commit cycle in one call. Saves a visual baseline, runs the specified tests, compares the result against the saved baseline, and suggests a git commit message.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `baseline` | **Yes** | — | Name to use for the visual baseline |
| `tests` | **Yes** | — | Test filter, e.g. `MyTarget/MyTests`. Passed to `build_and_test` |
| `project` | No | Auto-detect | Path to .xcodeproj or .xcworkspace |
| `scheme` | No | Auto-detect | Scheme name |
| `simulator` | No | Auto-detect (booted) | Simulator name or UDID |

**Steps performed:**
1. Saves a visual baseline via `save_visual_baseline`
2. Runs tests via `build_and_test` with the provided filter
3. Compares current screenshot against the saved baseline

**Returns:** Pass/fail status, baseline path, test result summary, and visual diff result. Returns failure if any test fails.

**CLI:** `xcforge bless --baseline <name> --tests <filter>`

---

## accessibility_check

Screenshot the current screen at several Dynamic Type sizes and compare each with the first, to
spot truncation and layout breaks. Restores the text size it found.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `simulator` | No | Auto-detect (booted) | Simulator name or UDID |
| `sizes` | No | XS, L, XXXL, AccessibilityXXXL | Comma-separated content size categories, or `all` |
| `threshold` | No | 5.0 | Max diff % against the base size |
| `settleTime` | No | 1.5 | Seconds to wait after each size change |

---

## localization_check

Relaunch the app in several languages (including right-to-left ones) and compare each screenshot
with the first. Relaunches without the locale arguments afterwards.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `simulator` | No | Auto-detect (booted) | Simulator name or UDID |
| `bundleId` | No | Last build | App to relaunch |
| `locales` | No | en, de, ja, ar, he | Comma-separated locales, or `all` for 10 |
| `threshold` | No | 10.0 | Max diff % against the base locale |
| `settleTime` | No | 3.0 | Seconds to wait after each relaunch |

CLI: `xcforge accessibility dynamic-type` and `xcforge accessibility localization`.

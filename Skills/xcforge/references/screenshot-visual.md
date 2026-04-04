# Screenshot & Visual Tools (4 tools)

## screenshot

Take a simulator screenshot. 0.3s latency — 44x faster than alternatives.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `simulator` | No | Auto-detect (booted) | Simulator name or UDID |
| `format` | No | jpeg | Image format: `png` or `jpeg` |

**3-tier capture strategy:**
1. **Burst** — native CoreSimulator IOSurface framebuffer access (~10ms)
2. **Stream** — ScreenCaptureKit fallback (~20ms)
3. **Safe** — simctl io screenshot last resort (~320ms)

**Returns:** Inline base64 image + metadata (resolution, byte size, capture method).

Use `jpeg` (default) for fastest transfer. Use `png` for pixel-perfect visual regression baselines.

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

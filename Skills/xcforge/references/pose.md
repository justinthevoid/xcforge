# Pose & Visual Iteration

Build + install + launch with optional named poses for visual design iteration.

## pose

Launch an app into a named visual state (pose) for rapid design iteration. Internally runs the full pipeline: build → install → launch with custom arguments, optionally followed by screenshot.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `name` | **Yes** | — | Pose name to pass to the app (e.g., `"dark-theme"`, `"onboarding-step-2"`) |
| `project` | No | Auto-detect | Path to .xcodeproj or .xcworkspace |
| `scheme` | No | Auto-detect | Scheme name |
| `simulator` | No | Auto-detect (booted) | Simulator name or UDID |
| `configuration` | No | Debug | Build configuration |
| `key` | No | `-pose` | Argument key to prepend to pose name (e.g., `-pose dark-theme` or `--state onboarding-step-2`). For values starting with `-`, use `--key=-myValue` (ArgumentParser parses bare `--key -myValue` as a missing value). |
| `screenshot` | No | — | Optional file path to capture screenshot after launch |
| `screenshotDelay` (`--screenshot-delay`) | No | `1.5` | Seconds to wait after launch before capturing the screenshot, so the iOS launch-zoom animation can settle. Pass `0` for legacy immediate-capture. Clamped to `[0, 60]`; NaN/inf are treated as `0`. |

**Returns:** Build status, install confirmation, launch status, app PID. If `screenshot` provided, also returns image data (capture failure only warns, does not fail the pose).

**MCP shape example:**
```json
{
  "tool": "pose",
  "input": {
    "name": "dark-theme",
    "project": "App.xcodeproj",
    "scheme": "App",
    "simulator": "iPhone 16 Pro",
    "screenshot": "/tmp/dark-theme.png"
  }
}
```

**CLI shape example:**
```bash
xcforge pose dark-theme --project App.xcodeproj --scheme App --simulator "iPhone 16 Pro" --screenshot dark-theme.png
```

---

## Argument Convention

Apps with a debug router can read `ProcessInfo.arguments` to implement pose-based navigation:

```swift
// Example: App-side pose router (no specific app name)
import Foundation

func routeToDebugPose() {
    let args = ProcessInfo.processInfo.arguments
    // args[0] = executable path
    // args[1...] = launch arguments
    
    if let poseIndex = args.firstIndex(of: "-pose"),
       poseIndex < args.count - 1 {
        let poseName = args[poseIndex + 1]
        switch poseName {
        case "dark-theme":
            applyDarkTheme()
            navigateToSettings()
        case "onboarding-step-2":
            skipOnboardingStep1()
            presentOnboardingStep2()
        case "profile-editing":
            setUserID(12345)
            navigateToProfileEditor()
        default:
            break
        }
    }
}
```

Custom key via `key` parameter:
```bash
xcforge pose onboarding-step-3 --key "--debug-state"  # Passes --debug-state onboarding-step-3
```

---

## Visual Iteration Loop

Combine `pose`, `screenshot --grid`, and `ui tap-pixel` for efficient layout work:

1. **Pose to named state:**
   ```bash
   xcforge pose "profile-dark" --screenshot profile-dark.png --grid
   ```

2. **View screenshot with grid overlay:**
   - Identify target position from grid (e.g., tap point 450, 600)

3. **Tap at point using grid coordinates:**
   ```bash
   xcforge ui tap-pixel --x 450 --y 600
   ```

4. **Verify result:**
   ```bash
   xcforge screenshot --grid
   ```

5. **Iterate:**
   - Repeat pose → screenshot → tap → verify until layout is correct

This loop avoids the overhead of recompiling or re-navigating to the same screen state.

---

## Common Patterns

### Multi-Step Navigation

```swift
// App-side: support comma-separated pose names
func routeToDebugPose() {
    if let poseIndex = ProcessInfo.processInfo.arguments.firstIndex(of: "-pose"),
       poseIndex < ProcessInfo.processInfo.arguments.count - 1 {
        let poses = ProcessInfo.processInfo.arguments[poseIndex + 1]
            .split(separator: ",")
            .map(String.init)
        
        for pose in poses {
            navigateToFlow(named: pose)
        }
    }
}
```

Then launch into nested state:
```bash
xcforge pose "onboarding,profile-setup,dark-theme" --screenshot result.png
```

### Screenshot Naming Convention

Combine pose name with metadata:
```bash
xcforge pose "accessibility-large-text" --screenshot "accessibility-large-text-light.png"
xcforge set_sim_appearance appearance: "dark"
xcforge pose "accessibility-large-text" --screenshot "accessibility-large-text-dark.png"
```

### Parallel Multi-Device Iteration

After establishing a working pose on one device:
```bash
xcforge pose "feature-beta" --simulator "iPhone SE" --screenshot "feature-beta-se.png"
xcforge pose "feature-beta" --simulator "iPhone 16 Pro Max" --screenshot "feature-beta-max.png"
xcforge pose "feature-beta" --simulator "iPad Pro 13-inch (M4)" --screenshot "feature-beta-ipad.png"
```

Then visually compare all three screenshots.

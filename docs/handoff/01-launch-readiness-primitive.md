# 01 — Launch-readiness primitive

**Priority:** P0 · **Effort:** M · **Confidence:** high on problem, medium on sketch

## Problem

Agents verifying UI changes need to capture a screenshot **of the intended screen**, not whatever frame happens to be on screen N seconds after launch. Today the only timing control is a delay budget. When the readiness shortcut can't run (WDA unbound) it degrades to a blind sleep, and even when it runs it only proves "the app's bundle id is frontmost" — which is already true at the launch splash, *before* a deep-link navigation push completes. The agent then screenshots the splash or the Home screen, concludes the deep-link or the UI change is broken, and goes down a wrong-diagnosis rabbit hole.

This single gap caused the most wasted cycles in the session: ~4 bad/raced captures, one wrong hypothesis ("`-NookPose` deep-link is broken"), and an eventual fallback to raw `xcrun simctl launch … && sleep 10 && xcforge screenshot`.

## Session evidence

- `xcforge pose dailyCalendar --key=-NookPose --screenshot … --screenshot-delay 2` → captured the **Home** screen (pre-nav-push), not the deep-linked Daily Calendar.
- Re-run with `--screenshot-delay 3` → captured the **cold-launch splash** (Solitaire Nook logo on a flat background).
- Cold launch was slow because the session had just cleared DerivedData (disk-full remediation), so first launch ≫ 2.5s.
- Working fallback was a hard-coded `sleep 10` — wasteful when fast, still a guess when slow.

## Current behavior (verified)

- `PoseProvider` default `screenshotDelay = 2.5`, `configuration = "Debug"` — `Sources/XCForgeKit/Tools/PoseProvider.swift:104-106`.
- Help text confirms the existing mechanism: *"Ceiling (seconds) for the post-launch wait before screenshot. Polls WDA for active CFBundleIdentifier and proceeds as soon as the app is foreground; falls back to sleeping the residual budget if WDA is unreachable. Default 2.5."* — `PoseProvider.swift:71-74`, `Sources/XCForgeCLI/Commands/Pose/PoseCommand.swift:44-48`.
- So readiness already exists, but: (a) it is **WDA-coupled** (WDA was unbound all session — see doc 03), (b) the gate is **bundle-id-foreground**, not **target-screen-rendered**, (c) the **2.5s ceiling** is below cold-launch time.

## Proposed change

Introduce a first-class readiness primitive used by `pose`, `screenshot`, and available standalone:

```
xcforge wait-ready [--for <signal>] [--timeout <sec>] [--poll-ms <ms>]
xcforge pose <name> --wait-for <signal> [--timeout <sec>]
xcforge screenshot --wait-for <signal> [--timeout <sec>]
```

`<signal>` grammar (compose with `,` = all must hold):

- `launch-complete` — process is foreground **and** has rendered ≥1 non-launch frame (see "How to detect" below).
- `a11y:<accessibilityId>` — an element with that id is present in the tree (the real "right screen is up" signal).
- `text:<substring>` — any element label/text contains the substring (fallback when no stable id).
- `idle:<ms>` — no tree mutation for `<ms>` (animation/settle gate).

Default for `pose`/`screenshot` when `--wait-for` omitted: keep current behavior but **raise the ceiling and make it explicit** (e.g. `launch-complete` with a 20s timeout) rather than a 2.5s blind budget. Capture happens the instant the signal holds, so a higher ceiling costs nothing on the fast path.

### How to detect each signal without WDA

The session's core failure was WDA being unbound, so readiness must have a **WDA-independent path**:

- **foreground / launch-complete:** `simctl spawn <udid> launchctl list` or CoreSimulator device state for the app's PID + frontmost; "rendered a frame" via the existing `CoreSimCapture` (compare two IOSurface frames for non-trivial change, or detect the launch-image surface signature ending). `CoreSimCapture` is already a private-framework, no-TCC path — `Sources/XCForgeKit/Clients/CoreSimCapture.swift:7-10`.
- **a11y:/text::** prefer AXP (`Sources/XCForgeKit/Clients/AXPBridge.swift`) which does **not** require a WDA *session* — only WDA-session-bound queries failed in the session. If AXP is unavailable, fall back to WDA, and if that fails, fall back to `launch-complete` + the existing delay with a one-line warning explaining the degraded mode (never silently degrade).

## Implementation sketch

- New `ReadinessProbe` in `Sources/XCForgeKit/Support/` (or `Tools/`): given `[Signal]`, a timeout, and a poll interval, return `{ ready: Bool, satisfied: [Signal], elapsedMs, mode: "axp"|"wda"|"framediff"|"degraded" }`.
- Wire into `PoseProvider` (replace the inline foreground-poll/residual-sleep block around `PoseProvider.swift:71-74` and the screenshot capture site) and `CaptureProvider`.
- New `Sources/XCForgeCLI/Commands/` entry `wait-ready`; add `--wait-for`/`--timeout` options to `PoseCommand` and `ScreenshotCommand`.
- Emit `mode` in JSON output so an agent can tell whether it got a real gate or a degraded sleep.

## Acceptance criteria

- `xcforge pose <name> --wait-for a11y:<id>` on a cold launch with cleared DerivedData captures the screen **only after** `<id>` exists; never the splash/Home.
- With WDA fully unreachable, `--wait-for a11y:<id>` still works via AXP **or** clearly reports `mode: degraded` with the reason (never a silent wrong capture).
- Fast path: when the screen is already up, capture latency is ≤ one poll interval, not the timeout.
- JSON includes `mode`, `elapsedMs`, `satisfied`.

## Risks / non-goals

- AXP vs WDA tree differences — element ids should match the WDA-visible ids the agent already uses; document any divergence.
- Not trying to detect "animations fully finished" beyond the optional `idle:<ms>` heuristic.
- Frame-diff "rendered a non-launch frame" is heuristic; `a11y:`/`text:` are the strong signals — recommend them in agent-facing docs.

## Open questions

- Should `launch-complete` alone be the new `pose` default, or `launch-complete,idle:300`? The latter is steadier for screenshots but adds latency on busy screens.
- Standalone `wait-ready` exit code on timeout: non-zero (script-friendly) — confirm it doesn't break existing `pose` JSON consumers.

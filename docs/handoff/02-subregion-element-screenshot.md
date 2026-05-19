# 02 — Sub-region / element screenshot + upscale

**Priority:** P1 · **Effort:** S · **Confidence:** high

## Problem

Judging a 1–3pt pixel-font nudge or a hairline-misaligned glyph requires looking at the relevant region **at magnification**. `xcforge screenshot` only captures the full frame at native scale; the displayed image is downscaled, so sub-pixel detail is unreadable. The agent's only recourse is a manual `python3 -c "from PIL import Image …"` crop+resize, **every iteration**. For pixel-art UI work — which is the entire SolitaireNook design loop — this hand-rolled PIL dance *is* the inner loop.

xcforge already has everything needed to do this natively: a fast IOSurface→CGImage capture path and per-element rects from WDA.

## Session evidence

Every visual verification this session went: `xcforge screenshot --output …` → `python3 -c "Image.open(...).crop((x0,y0,x1,y1)).resize((W,H)).save(...)"` → read the crop. Done ~6 times across two iterations of the chip offset and the numeral nudge. Coordinates were eyeballed and re-guessed when the crop missed the target band (one crop landed on grass instead of the chip strip and had to be redone).

## Current behavior (verified)

- `ScreenshotCommand` options are limited to `--format`, `--output`, `--simulator`, a flag, and JSON — no `--region`, `--element`, or `--scale` — `Sources/XCForgeCLI/Commands/Screenshot/ScreenshotCommand.swift:43-58`.
- Capture is a full-frame IOSurface→CGImage fast path — `Sources/XCForgeKit/Clients/CoreSimCapture.swift:7-10,82`.
- Element rects are already available from WDA: `GET /session/<sid>/element/<id>/rect` returning x/y/width/height — `Sources/XCForgeKit/Clients/AgentClient.swift:683-690`.

## Proposed change

Add to `screenshot` (and mirror in the MCP tool + `pose --screenshot`):

```
xcforge screenshot --region <x,y,w,h> [--scale <N>] [--output …]
xcforge screenshot --element <accessibilityId> [--pad <pt>] [--scale <N>] [--output …]
xcforge screenshot --scale <N>            # whole frame, integer-upscaled
```

- `--region x,y,w,h` — crop in **points** (document the coordinate space; match the points used by `ui ls`/`tap-pixel` so an agent can copy rects between tools). No WDA needed.
- `--element <id> [--pad p]` — resolve the element rect via WDA (or AXP fallback per doc 03), expand by `p` points, crop. WDA-coupled — degrade gracefully with a clear message if no session (point user at doc 03 / `--region`).
- `--scale N` — nearest-neighbor integer upscale (preserve pixel-art crispness — **no smoothing**; this matters, a bilinear upscale would defeat the purpose for pixel art).
- JSON output includes the resolved pixel rect and scale so the agent can reason about what it got.

## Implementation sketch

- Crop+scale on the `CGImage` from `CoreSimCapture` before encoding, in `Sources/XCForgeKit/Tools/CaptureProvider.swift` (the tool layer over `CoreSimCapture`). Use `CGImage.cropping(to:)` + a `CGContext` with `interpolationQuality = .none` for the integer upscale.
- Add `--region`/`--element`/`--pad`/`--scale` options to `ScreenshotCommand.swift:43-58`; thread through `CaptureProvider`.
- For `--element`, reuse the WDA rect call at `AgentClient.swift:683`; convert WDA rect (points) → capture pixel space using the existing scale (`ScreenshotCommand` already references `info.scale` at `:80`).
- Mirror the params in the MCP `screenshot`/`take_screenshot` tool schema and `pose --screenshot`.

## Acceptance criteria

- `xcforge screenshot --element dailyCalendar.kindChip.classic --pad 8 --scale 4` produces a crisp, nearest-neighbor-upscaled PNG of just that chip, no PIL.
- `--region` works with **zero** WDA session (pure CoreSim path).
- Upscale is pixel-exact (no anti-aliasing/smoothing) — verify on a known 1px-stroke asset.
- JSON reports the resolved rect (pixels) and scale.
- `--element` with no WDA session fails with a one-line message naming `--region` and doc 03, not a stack trace.

## Risks / non-goals

- Coordinate-space confusion is the main footgun — be explicit in `--help` whether x,y,w,h are points or pixels, and keep it consistent with `ui ls` rect output and `tap-pixel`.
- Not building an image-annotation/markup feature — just crop + integer upscale.
- `--scale` should reject non-integers (or floor with a warning) to keep pixel cadence.

## Why this is P1 not P0

It doesn't *block* the loop the way 01/03 do (PIL is an available workaround), but it's the single highest-**frequency** papercut for this codebase's core activity. Cheap to build, pays back every pixel-art task forever.

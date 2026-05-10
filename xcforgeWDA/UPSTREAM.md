# xcforgeWDA — upstream lineage

This directory is a fork of [Appium WebDriverAgent](https://github.com/appium/WebDriverAgent), which is itself a fork of Facebook's [WebDriverAgent](https://github.com/facebookarchive/WebDriverAgent) (BSD-licensed, see `LICENSE`).

**Forked from:** appium/WebDriverAgent commit `381e75c` (release 12.2.0).

**Why a fork:** xcforge ships small, targeted patches that address gaps Appium has not (yet) merged upstream. The patches live in this folder and are re-applied on rebase against upstream.

## xcforge-specific patches

- **Multi-window support for SwiftUI sheets** — `XCUIApplication`'s standard snapshot only captures the keyWindow's hierarchy, so SwiftUI `.sheet` content (which mounts in a sibling `UIWindow`) is invisible to upstream WDA. xcforgeWDA adds a `windows.count > 1` gate in three coupled places:
  - `WebDriverAgentLib/Categories/XCUIApplication+FBHelpers.m` — `fb_tree:`, `fb_xmlRepresentationWithOptions:`, `fb_descriptionRepresentation` merge per-window snapshots under a synthetic Application root that preserves real app attributes.
  - `WebDriverAgentLib/Categories/XCUIElement+FBFind.m` — `fb_descendantsMatchingPredicate:` and `fb_descendantsMatchingClassName:` retry per-window when the keyWindow query returns empty, with dedup and per-window exception handling.
  - `WebDriverAgentLib/Commands/FBElementCommands.m` — `gestureCoordinateWithOffset:element:` re-roots on the topmost `exists && isHittable` window for app-base coordinate taps.
- Single-window apps remain byte-identical — every patch is gated.

## Re-linking to upstream

The fork's `.git` directory is intentionally omitted in xcforge's main repo so the tree tracks as a flat folder rather than a submodule. To re-link for upstream merges:

```bash
cd xcforgeWDA
git init
git remote add upstream https://github.com/appium/WebDriverAgent.git
git fetch upstream
# Manually re-apply the patches above on the new base.
```

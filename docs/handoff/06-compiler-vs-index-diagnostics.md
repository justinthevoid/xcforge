# 06 — Distinguish compiler errors from stale-index diagnostics

**Priority:** P1 · **Effort:** S · **Confidence:** high on problem, low on the exact integration seam

## Problem

After every successful build this session, the harness surfaced a `<new-diagnostics>` block full of errors like `No such module 'SolitaireEngine'`, `Value of type 'Text' has no member 'snookHeading'`, `Cannot find type 'MonthGridViewModel' in scope`. These are **stale SourceKit index** results, not compiler output — `xcodebuild` returned `"succeeded": true, "install": "ok", "launch": "ok"` for the exact same files. They appear because the SPM module graph was just rebuilt and the live index hasn't caught up.

For a human this is mild noise. For an agent it is a **trap**: the diagnostics read exactly like a failed build, directly contradict xcforge's authoritative `succeeded: true`, and an agent that trusts them will "fix" non-bugs, re-run builds, or report a green change as broken. This session it required a standing prior to *know* to disregard them; without that, it's a wrong-conclusion generator.

## Session evidence

- Build result: `{"succeeded": true, "install": "ok", "launch": "ok"}` plus 2 pre-existing unrelated warnings.
- Same turn, `<new-diagnostics>`: `DailyCalendarView.swift: No such module 'SolitaireEngine'`, `MonthGridView.swift: has no member 'snookBody'/'snookOnCream'`, `DayCellView.swift: Cannot find 'FlameGlyphView'/'DayCellAccessibility'`, etc.
- Every one of those symbols exists and compiled cleanly (xcodebuild is authoritative). The pattern (whole-module "No such module", "has no member" on known-good APIs) is the SPM-graph-just-rebuilt SourceKit signature.

## Current behavior

xcforge's build output is already authoritative and correct (`BuildProvider`/`BuildRenderer`, `Sources/XCForgeKit/Tools/BuildProvider.swift`, `Sources/XCForgeCLI/Commands/Build/BuildRenderer.swift`). The stale diagnostics are surfaced by the editor/SourceKit layer the *harness* reads, **not** by xcforge — so xcforge can't suppress them. But xcforge is the component that *knows* a green build just happened and that the SPM graph changed, so it's the right place to (a) say so loudly and (b) offer to make the index agree.

## Proposed change

Two complementary, low-risk additions:

**A. Authoritative-result framing.** On a successful build that (re)built local SPM packages, have `BuildRenderer` emit an explicit line / JSON field:

```json
{ "succeeded": true,
  "indexHint": "SPM module graph rebuilt; editor/SourceKit diagnostics may be stale and are NOT compiler errors. xcodebuild is authoritative." }
```

A single agent-facing sentence tied to the green result is enough to break the "diagnostics say it's broken" trap, because the agent reads xcforge's output in the same turn.

**B. Optional index prime.** Add `xcforge build --prime-index` (and a standalone `xcforge index prime`) that, after a green build, warms SourceKit for the workspace/packages (e.g. trigger an `xcodebuild`/`sourcekit-lsp` index pass, or touch the package graph so the next index is fresh) so the live diagnostics stop lying. Off by default (it costs time); agents/CI can opt in after a green build.

## Implementation sketch

- `BuildRenderer` (`Sources/XCForgeCLI/Commands/Build/BuildRenderer.swift`): when the build succeeded **and** the build graph included local SPM package targets (detectable from the build plan xcforge already parses), append `indexHint` to text + JSON. Keep it suppressible via the existing audience/quiet flags (`OutputAudience.swift`).
- `--prime-index` flag on `BuildCommand`/`BuildTestCommand`; new `index prime` command. Implementation options to evaluate: a background `xcodebuild build` with `COMPILER_INDEX_STORE_ENABLE=YES` already produces an index store — surfacing/refreshing that may be enough; or invoke `sourcekit-lsp` warmup. Pick the cheapest reliable path.
- Document in the xcforge skill/README: "treat xcforge build `succeeded` as authoritative; `<new-diagnostics>` after an SPM rebuild are stale-index, not compiler errors."

## Acceptance criteria

- A successful build that rebuilt a local SPM package emits the `indexHint` line/field; a pure app-target rebuild with no graph change does not (no false noise).
- `--prime-index` measurably reduces stale "No such module"/"has no member" diagnostics on the immediately following editor query (manual verification acceptable).
- `indexHint` respects quiet/JSON-only/audience flags.

## Risks / non-goals

- xcforge cannot delete diagnostics it doesn't emit — this is about **framing + an opt-in fix**, not suppression. Set expectations accordingly in the doc.
- `--prime-index` must be opt-in; priming on every build would tax the fast TDD loop.
- Don't over-trigger the hint — gate strictly on "local SPM graph actually (re)built," or it becomes the noise it's meant to counter.

## Open question

- Is there an existing index-store path xcforge already produces (e.g. via `COMPILER_INDEX_STORE_ENABLE`) that `--prime-index` can simply surface/point SourceKit at, rather than running a separate pass? Cheapest win if so.

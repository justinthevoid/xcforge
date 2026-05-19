# xcforge — agent-experience handoff docs

**Source:** a real SolitaireNook iOS dev session (2026-05-19) that leaned heavily on xcforge for build → pose → screenshot → visual-verify loops on a pixel-art UI change. These docs capture the friction an autonomous coding agent hit, with verified file references and concrete fixes.

## The meta framing

xcforge's **happy path is excellent**. The agent experience degrades sharply at the **failure boundary**: opaque errors, readiness checks that silently degrade to fixed sleeps, and CLI-ergonomics mismatches that each cost a round-trip. For an autonomous agent these are disproportionately expensive — an opaque error or a raced screenshot doesn't just slow things down, it produces *wrong conclusions* (e.g. "the deep-link is broken" when WDA was simply unbound) and burns context re-diagnosing.

The highest-leverage theme is **determinism and self-diagnosis, not new features**.

## Corrections to in-session assumptions (read first)

During the session two hypotheses were formed that turned out wrong on inspection. Documented here so the same wrong turns aren't re-derived:

- **"`pose` should default to Debug" — already done.** `PoseProvider`/`PoseCommand` already default `configuration` to `Debug` (`Sources/XCForgeKit/Tools/PoseProvider.swift:104`, `Sources/XCForgeCLI/Commands/Pose/PoseCommand.swift:63`). The session symptom ("pose landed on Home, not the deep-linked screen") was **not** a config problem. Root cause was readiness (doc 01) coupled with WDA being unbound all session (doc 03). No separate handoff for this.
- **"`pose --screenshot-delay` is a dumb sleep" — partially wrong.** It already polls WDA for the active `CFBundleIdentifier` and proceeds when the app is foreground, *falling back* to sleeping the residual budget only when WDA is unreachable (`PoseProvider.swift:71-74`). The real defects: (a) it depends on WDA reachability, which was broken; (b) "bundle-id is foreground" is true at the launch splash, *before* the deep-link nav push — it is not an "is the target screen rendered" signal; (c) the 2.5s default ceiling is far below cold-launch time on freshly-cleaned DerivedData. See doc 01.

## Priority order (by pain-saved this session)

| # | Doc | One-liner | Priority | Est. |
|---|-----|-----------|----------|------|
| 01 | [Launch-readiness primitive](01-launch-readiness-primitive.md) | WDA-independent readiness + element-presence gate; stop racing cold launch | **P0** | M |
| 03 | [WDA session diagnostics + auto-heal](03-wda-session-diagnostics-and-autoheal.md) | `ExitCode(rawValue: 1)` → actionable cause + auto-rebind; unblocks the whole UI path *and* doc 01 | **P0** | M |
| 02 | [Sub-region / element screenshot](02-subregion-element-screenshot.md) | `screenshot --element/--region --scale`; kill the manual PIL crop loop | **P1** | S |
| 06 | [Compiler vs. index diagnostics](06-compiler-vs-index-diagnostics.md) | Stop stale-SourceKit errors reading as build failures | **P1** | S |
| 04 | [`doctor` + guarded `clean`](04-doctor-and-guarded-clean.md) | Triage/repair the iOS-dev environment (disk, sims, WDA) | **P2** | M |
| 05 | [CLI consistency + command index](05-cli-consistency-and-command-index.md) | Kill arg-shape round-trips; machine-discoverable commands | **P2** | S–M |

`S` ≈ <0.5d, `M` ≈ 0.5–2d (rough; verify against the codebase).

**Coupling:** 01 and 03 are intertwined — 01's readiness signal is only as good as WDA reachability, which is 03. Ship 03's WDA-independent foreground probe and 01's element-gate together for a deterministic pose/screenshot loop.

## Implementation status

- **01 + 03 — shipped.** Launch-readiness primitive + WDA session diagnostics & auto-heal are implemented (spec `_bmad-output/implementation-artifacts/spec-launch-readiness-and-wda-autoheal.md`):
  - New `ReadinessProbe` (AXP-first → WDA fallback → reported degraded), exposed as `xcforge wait-ready` / MCP `wait_ready`, and as additive `--wait-for`/`--timeout` flags on `pose` and `screenshot capture`. Default pose/screenshot timing is **unchanged** when no new flag is passed.
  - The `ui session` catch-scope bug (`Session creation failed: ExitCode(rawValue: 1)`) is fixed: failures now emit a structured `error/cause/detail/remediation` envelope with a bounded one-shot auto-heal (`--no-autoheal` preserves fail-fast, `--relaunch-app` is opt-in).
  - `appForeground` (`Bool?`, derived from `verifyActiveBundleId()`, `null` when WDA unreachable) added to `tap-by-id`/`tap-by`/`click`/`find`/`screenshot` results.
  - Reference docs updated: `cli-commands.md`, `ui-automation.md`, `pose.md`.
- Out of scope (deferred): `idle:<ms>` settle signal, port-8100 contention detection, handoff docs 02/04/05/06.

## Confidence

File:line references were verified by targeted grep against the xcforge tree on 2026-05-19, not full reads. Where a claim rests on inference rather than a read, the doc says so explicitly ("verify against …"). Treat the implementation sketches as starting points, not gospel.

# 04 — `xcforge doctor` + guarded `clean`

**Priority:** P2 · **Effort:** M · **Confidence:** high on problem, medium on scope

## Problem

The single hardest blocker of the session happened *before any xcforge command ran*: the machine's data volume was at 100% (185 MiB free), so the agent harness couldn't even create its session dir, and no build/sim/test could run. The space was dominated by iOS-dev detritus: **28 GB stale `iOS DeviceSupport`**, **12 GB CoreSimulator**, plus DerivedData and caches. Remediation was hand-rolled `du -sh …` + `rm -rf …` with the agent reasoning about what was safe to delete.

xcforge **is the iOS-dev orchestration tool**. Environment triage (disk, simulators, WDA runner health, DeviceSupport bloat) and *guarded* reclamation belong here, with the domain knowledge baked in (e.g. "never delete the connected device's current DeviceSupport"). An agent shouldn't be hand-writing `rm -rf` against `~/Library/Developer`.

## Session evidence

- `mkdir … : ENOSPC: no space left on device` on the very first command.
- `df -h /System/Volumes/Data` → `228Gi 189Gi 185Mi 100%`.
- Offenders measured by hand: `~/Library/Developer/Xcode/iOS DeviceSupport` 28G (three builds of the *same* device/iOS, two stale), `~/Library/Developer/CoreSimulator` 12G, `~/Library/Caches` 2.9G, DerivedData 1.3G.
- Reclaimed ~30G via manual `rm -rf` of DeviceSupport + DerivedData + caches + `simctl delete unavailable`. Worked, but the agent had to supply all the safety reasoning ad hoc, and clearing DerivedData mid-session is what made the subsequent cold launch slow (feeding doc 01) and plausibly contributed to the WDA-runner failure (doc 03).

## Proposed change

**A. `xcforge doctor`** — read-only environment health report:

```
xcforge doctor [--json]
```

Checks: free disk on the data volume (+ ENOSPC risk threshold); DerivedData / CoreSimulator / `iOS DeviceSupport` / `~/Library/Caches` sizes; count of `unavailable` simulators; WDA runner deploy state (`xcforgeWDA-deploy` DerivedData present? port 8100 reachable?); booted-sim presence; Xcode/SDK sanity. Output: per-check `ok|warn|fail` + the exact remediation command for each.

**B. `xcforge clean`** — guarded, accounted reclamation:

```
xcforge clean [--dry-run] [--derived-data] [--unavailable-sims] \
              [--device-support[=stale]] [--caches] [--all] [--yes]
```

- **`--dry-run` is the default** when no scope flags are given — print what *would* be freed, per category, in bytes, and stop. Destruction requires explicit scope + `--yes` (or interactive confirm).
- **Safety rails (the domain knowledge):**
  - `--device-support=stale` deletes only DeviceSupport dirs **not** matching any currently-attached device's OS build; **never** the current device's. Plain `--device-support` (all) requires `--yes` and prints the per-build breakdown first.
  - Never touch `xcforgeWDA-deploy` DerivedData unless `--all` (deleting it forces a WDA rebuild → see doc 03; warn loudly).
  - Never delete a *booted* sim or the project's resolved default sim.
  - Per-category byte accounting in the result (`{ category, freedBytes }[]`), so an agent can decide and report precisely.

## Implementation sketch

- New `Sources/XCForgeCLI/Commands/Doctor/` + `DoctorProvider` in `Sources/XCForgeKit/Tools/`. Reuse `SimulatorProvider` for sim/unavailable enumeration and the WDA paths from `AgentClient.swift:247-266` for runner-deploy checks.
- `clean` can live under `Sim` or as a top-level command; size walks via `FileManager` (cheap `du`-equivalent). Attached-device → OS-build resolution via `devicectl` (xcforge already has `Device` commands).
- Wire `doctor`'s WDA section to the same probe doc 03 introduces; wire its disk thresholds so other commands can call `doctor`'s disk check and fail fast with a useful message instead of an opaque `ENOSPC` deep in a build.
- Optional: a lightweight pre-flight in build/test/sim that, on `ENOSPC` or <Xish free, points the user at `xcforge clean --dry-run`.

## Acceptance criteria

- `xcforge doctor` on the session's start state reports `fail` on disk with the DeviceSupport/CoreSimulator sizes and the exact `clean` command to fix it.
- `xcforge clean --dry-run` (no scope) prints per-category reclaimable bytes and deletes nothing.
- `xcforge clean --device-support=stale --yes` removes only non-attached-device builds; a connected device's current DeviceSupport is provably retained.
- Refuses to delete a booted/default sim or `xcforgeWDA-deploy` without `--all` + `--yes`, with a clear reason.
- JSON includes per-category `freedBytes` (dry-run: `wouldFreeBytes`).

## Risks / non-goals

- Destructive surface — **dry-run-by-default + explicit scope + `--yes`** is non-negotiable. Mirrors xcforge's existing care around destructive sim ops.
- Don't auto-clean as a side effect of other commands — only *recommend* via `doctor`/pre-flight. (Auto-clearing DerivedData is exactly what slowed cold launch and likely broke WDA this session.)
- Not a general macOS disk cleaner — scope strictly to iOS-dev-owned dirs.

## Open question

- Should `doctor` be auto-run (cached, throttled) at the start of a build when free disk is below a threshold, surfacing one warning line? Useful for agents, but must be cheap and non-blocking.

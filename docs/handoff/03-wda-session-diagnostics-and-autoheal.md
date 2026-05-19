# 03 — WDA session diagnostics + auto-heal

**Priority:** P0 · **Effort:** M · **Confidence:** high on problem, medium on sketch

## Problem

When `ui session` (WDA session creation/binding) fails, the agent gets `Session creation failed: ExitCode(rawValue: 1)` — no cause, no remediation, no signal that the whole UI-automation path and the pose/screenshot readiness shortcut (doc 01) are now degraded. Every subsequent `tap-by-id` 404s, the app silently ends up backgrounded to springboard, and nothing in any command's output says "the app is not foreground" or "WDA has no bound session." An agent cannot recover from an error it cannot read.

This is the worst possible failure shape for an autonomous tool: opaque, cascading, and silent.

## Session evidence

- `xcforge ui session --bundle-id com.justinthevoid.solitairenook` → `{"message":"Session creation failed: ExitCode(rawValue: 1)","succeeded":false}` — repeated, every attempt.
- `xcforge ui tap-by-id "home.newspaperCard"` → `WDA error 404: unable to find an element using 'accessibility id'` (because no session was bound — the documented pitfall #8 remedy itself failed).
- After the failed taps the app was on the **iOS springboard**; discovered only by taking a screenshot and visually noticing. No command surfaced the foreground/background transition.
- Net effect: the entire WDA UI path was unusable for the session; pose/screenshot readiness (doc 01) silently fell back to blind sleeps because its WDA foreground poll could never succeed.

## Current behavior (verified by grep — confirm with a read)

- `AgentClient.createSession(bundleId:)` throws on failure — `Sources/XCForgeKit/Clients/AgentClient.swift:419-456`. The thrown error is being stringified into the opaque `ExitCode(rawValue: 1)` somewhere up the stack (likely the WDA runner process exit, not an HTTP error).
- There is already binding-verification + rebind scaffolding: `verifyBinding`/clear-`sessionId`-so-next-`ensureSession()`-rebinds — `AgentClient.swift:460-487`. So the actor *can* re-bind; the gap is surfacing *why* it failed and triggering recovery automatically.
- WDA deploy/runner paths: `AgentClient.swift:247-266` (`xcforgeWDA`, DerivedData `xcforgeWDA-deploy`). A plausible root cause class for `ExitCode 1`: the WDA runner failed to build/launch (stale `xcforgeWDA-deploy` DerivedData — the session had just nuked DerivedData), or no booted sim, or port 8100 contention.

## Proposed change

Three parts:

**A. Actionable error surface.** Replace `Session creation failed: ExitCode(rawValue: 1)` with a structured failure:

```json
{
  "succeeded": false,
  "error": "wda_session_create_failed",
  "cause": "wda_runner_not_running",        // enumerated
  "detail": "WDA process exited 1; xcforgeWDA-deploy DerivedData missing (likely cleaned)",
  "remediation": "xcforge ui status --repair   # rebuilds & relaunches the WDA runner",
  "appForeground": false
}
```

Enumerate causes: `wda_runner_not_running`, `wda_runner_build_failed`, `no_booted_simulator`, `port_in_use`, `bundle_not_installed`, `session_bind_rejected`, `unknown` (with raw stderr attached).

**B. Auto-heal.** `ui session` (and `ensureSession()` on the path used by `tap-by-id`/`find`/`click`) should, on a recoverable cause, attempt one bounded self-repair before failing: (re)build/relaunch the WDA runner, re-create the session, re-bind to `bundleId`, verify via the existing `verifyBinding`. Report `recovered: true` + what was done, or fail with the structured error above. Make the repair opt-out (`--no-autoheal`) for debugging.

**C. Foreground/background visibility.** Add an `appForeground` boolean to the output of `tap-by-id`, `click`, `tap`, `find`, and `screenshot`. An agent must be able to tell, from a command result, that the app it thinks it's driving is actually backgrounded — without inferring it from a screenshot.

## Implementation sketch

- `AgentClient.createSession`/`ensureSession` (`AgentClient.swift:419-487`): catch the runner-exit failure, classify it (inspect WDA runner exit + whether `xcforgeWDA-deploy` DerivedData exists + `simctl` boot state + a quick `:8100/status` probe), throw a typed `WDAError.sessionCreate(cause:detail:)`.
- `ui status --repair` (or reuse/extend the existing `UIStatus` at `Sources/XCForgeCLI/Commands/UI/UICommand.swift:55`) as the canonical WDA-runner rebuild+relaunch entry; have auto-heal call the same code path.
- Add `appForeground` to the renderer outputs in `UICommand.swift` tap/find/click subcommands and `ScreenshotCommand`; source it from the same foreground probe doc 01 introduces (shared `ReadinessProbe`/foreground check).
- Map the typed error to a stable CLI message + JSON in `UIRenderer`.

## Acceptance criteria

- A forced WDA-runner failure yields the structured `error/cause/detail/remediation` JSON, not `ExitCode(rawValue: 1)`.
- With stale/missing `xcforgeWDA-deploy` DerivedData, `ui session` auto-heals (rebuild+relaunch+rebind) and reports `recovered: true`, or fails with `cause: wda_runner_build_failed` + the exact repair command.
- After an interaction that backgrounds the app, the next `tap-by-id`/`screenshot` result includes `appForeground: false`.
- `--no-autoheal` preserves today's fail-fast behavior for debugging.

## Risks / non-goals

- Auto-heal must be **bounded** (one attempt, hard timeout) — never an unbounded rebuild loop.
- Don't auto-relaunch the *user app* implicitly as part of session repair unless `--relaunch-app` is set (the agent may have intentional app state); WDA-runner repair is safe, app relaunch is not.
- Not solving general WDA flakiness — just making its #1 failure legible and self-recoverable.

## Open questions

- Is `ExitCode(rawValue: 1)` originating from the WDA runner process or an xcodebuild-deploy step? Confirm via a read of the throw site feeding `AgentClient.swift:419`.
- Port-8100 contention detection — worth including in the cause enum if multi-sim/multi-run is common on dev machines.

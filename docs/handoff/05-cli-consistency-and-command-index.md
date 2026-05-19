# 05 — CLI argument consistency + machine-discoverable command index

**Priority:** P2 · **Effort:** S–M · **Confidence:** high on problem, low on the full audit scope

## Problem

Argument conventions are inconsistent across (and within) command groups, and there's no machine-readable command index. Each mismatch costs an autonomous agent a full round-trip: guess the form → get a usage error → re-read help → retry. None individually is severe; collectively they're a steady tax on every session that touches an unfamiliar subcommand.

## Session evidence

Concrete round-trips burned this session:

- `xcforge ui tap-by-id --id "home.newspaperCard"` → `Error: Unknown option '--id'`. Correct form is **positional**: `xcforge ui tap-by-id "home.newspaperCard"`.
- Meanwhile `xcforge ui find` requires **named** options: `--using <strategy> --value <v>`, and `xcforge ui click` uses `--element`. So within the *same* `ui` group, element targeting is positional in one subcommand and a named option in siblings.
- `xcforge launch-app --bundle-id …` → usage error (no such command). Correct form is `xcforge sim launch --bundle-id …`. Reasonable in hindsight, but not guessable; cost a discovery round-trip.

## Current behavior (verified)

- `ui tap-by-id` takes a **positional** a11y id — `Sources/XCForgeCLI/Commands/UI/UICommand.swift:1006-1047`.
- `ui find` / `find-all` take `--using` + `--value` — `UICommand.swift:228-231,288-291`.
- `ui click` takes `--element` — `UICommand.swift:337`.
- `ui tap` / `double-tap` / `long-press` take `--x` / `--y` — `UICommand.swift:380-383,426-429,464+`.
- App launch lives at `sim launch` (`Sources/XCForgeCLI/Commands/Sim/SimCommand.swift`), not a top-level `launch-app`.

So element-targeting alone has three shapes (`<positional>`, `--element`, `--using/--value`) across one group. (Some of this is justified — `find` genuinely needs a strategy + value — but `tap-by-id` positional vs `click --element` is gratuitous divergence.)

## Proposed change

**A. Convention audit + alignment.** Define and document one rule, e.g.: *"Single primary target = positional; everything else = named option; accept the named form as an alias wherever a positional primary exists."* Then:

- Make element-by-id consistent: `ui tap-by-id <id>` keeps positional **and** accepts `--element <id>` as an alias (matching `ui click`); or pick one and alias the other. Zero-breakage path: add aliases, don't remove existing forms.
- Audit all groups for primary-arg shape; fix the gratuitous divergences, alias rather than break.
- Consider a discoverable top-level alias `xcforge launch-app` → `sim launch` (common enough to be worth the shortcut), or ensure `xcforge --help` foregrounds `sim launch`.

**B. Machine-readable command index.**

```
xcforge --commands --json     # or: xcforge commands --json
```

Emit every command/subcommand with: full path, abstract, each arg (name, positional|option|flag, required, default, help). ArgumentParser already holds all of this — this is a serialization pass over the command tree, not new modeling. An agent can load this once and stop guessing arg shapes entirely.

## Implementation sketch

- ArgumentParser exposes the command tree; add a hidden `commands` command (or `--commands` on the root) that walks `configuration.subcommands` recursively and serializes `CommandConfiguration` + each `@Argument/@Option/@Flag`'s metadata to JSON. One renderer, no per-command work.
- For aliasing: ArgumentParser supports option name aliases and you can accept both a positional and an option by adding an optional `@Option` that, when set, overrides/!validates against the positional. Keep changes additive (no removed/renamed args → no breakage for existing callers/CI).
- Document the convention rule in `CONTRIBUTING.md` so new commands stay consistent; add a tiny test asserting "every subcommand's primary target arg follows the rule."

## Acceptance criteria

- `xcforge ui tap-by-id <id>` and `xcforge ui tap-by-id --element <id>` both work; `ui click` likewise; no existing form removed.
- `xcforge --commands --json` returns the full tree with arg kinds/defaults/required for every subcommand; round-trips through `jq`.
- A consistency test fails if a new subcommand's primary-target arg violates the documented convention.
- `xcforge --help` (or an alias) makes app launch discoverable without trial and error.

## Risks / non-goals

- **Backwards compatibility:** additive only. Don't rename/remove args — CI, the xcforge skill docs, and existing agent transcripts depend on current forms. Aliases, not replacements.
- Not redesigning the CLI surface — just removing gratuitous divergence and making it self-describing.
- The full audit could sprawl; scope v1 to (a) the `--commands` JSON (highest leverage, low risk) and (b) the element-targeting + launch discoverability fixes that actually bit this session. Defer a broader pass.

## Why the `--commands --json` half is the real win

The alias cleanup is nice-to-have. The machine-readable index is the structural fix: an agent that can load the command tree never guesses arg shapes again, which dissolves this whole class of round-trip independent of how consistent the conventions are.

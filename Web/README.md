# xcforge Web Baseline

Stories 1.1 and 1.2 initialize the Web workspace with:

- Astro Starlight docs
- Svelte integration for future interactive modules
- Cloudflare Workers deployment baseline with Wrangler
- Bun-only package and script execution
- Biome-only lint and format workflow

## Requirements

- Bun >= 1.3.10
- Node.js >= 22.12.0

## Quick Start

```bash
cd Web
bun install
bun run validate
bun run workers:check
bun run dev
```

## Commands

| Command                                 | Purpose                                                                                                 |
| --------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| `bun run doctor`                        | Validate runtime and dependency baseline with actionable diagnostics                                    |
| `bun run dev`                           | Start local server                                                                                      |
| `bun run validate:routes`               | Validate marketing/docs route ownership and internal cross-surface homepage links                       |
| `bun run validate:conversion-hierarchy` | Validate install-vs-secondary action hierarchy contracts across desktop and mobile breakpoints          |
| `bun run typecheck`                     | Run `astro check`                                                                                       |
| `bun run lint`                          | Run Biome checks                                                                                        |
| `bun run lint:fix`                      | Apply safe Biome lint fixes                                                                             |
| `bun run format`                        | Apply Biome formatting                                                                                  |
| `bun run validate`                      | Run full baseline checks                                                                                |
| `bun run workers:check`                 | Validate Workers preflight contract (adapter + wrangler + binding parity checks)                        |
| `bun run workers:preview`               | Run Workers preflight and build, then start Wrangler preview from generated `dist/server/wrangler.json` |
| `bun run workers:deploy`                | Run Workers preflight and build, then deploy with Wrangler from generated `dist/server/wrangler.json`   |

## Route Boundary Validation

`bun run validate:routes` enforces Story 4.1 routing contracts before release packaging:

- Marketing pages remain in `src/pages` and do not overlap `/docs`.
- Starlight docs slugs resolve to `/docs` and `/docs/*` routes.
- `astro.config.mjs` preserves both Starlight and Svelte integrations.
- Homepage internal links to docs/workflow destinations resolve to valid routes.

`bun run build` runs this check before `astro build`, so broken cross-surface links fail early and block release.

## Conversion Hierarchy Validation

`bun run validate:conversion-hierarchy` enforces Story 4.3 install-momentum contracts:

- Navigation, hero, final CTA, and docs-handoff actions must expose explicit primary/secondary action tiers.
- Docs, Workflow Guide, Changelog, and GitHub paths must remain tagged as supporting conversion paths.
- Responsive hierarchy contracts must remain present for mobile stacking and primary CTA region handling.

If hierarchy rules regress, validation fails with a release-blocking error and writes breakpoint snapshot artifacts to `.artifacts/conversion-hierarchy/...` for defect attachment.

`bun run build` runs this check before `astro build`, so hierarchy regressions cannot ship.

## Cloudflare Workers Baseline

Workers is the only supported deployment target for this Web workspace. The runtime contract is defined in `wrangler.jsonc` and validated by `scripts/validate-workers-config.mjs`.
Preview and deploy commands additionally validate generated `dist/server/wrangler.json` after build.

Required binding names (must exist in both default `vars` and `env.preview.vars`):

- `XCFORGE_ANALYTICS_DATASET`
- `XCFORGE_ANALYTICS_ENDPOINT`
- `XCFORGE_INSTALL_INTENT_TARGET`

The preflight also validates:

- `wrangler.jsonc` exists and is parseable
- `astro.config.mjs` imports and configures `@astrojs/cloudflare`
- Astro output mode is `server`
- Binding key parity between default and preview envs

## Route Boot Assumptions

With `bun run dev` running locally:

- Marketing route should resolve at `http://localhost:4321/`
- Docs route should resolve at `http://localhost:4321/docs`
- Docs depth route should resolve at `http://localhost:4321/docs/getting-started`

## Troubleshooting

### Unsupported Runtime

Symptoms:

- `bun run doctor` reports Bun or Node.js version incompatibility
- Validation scripts exit before Astro/Biome checks run

Remediation:

```bash
brew install bun && brew upgrade bun
brew install node@22
bun run doctor
```

### Dependency Or Bootstrap Failure

Symptoms:

- `bun install` fails due to interrupted bootstrap or dependency resolution issues
- `bun run typecheck` or `bun run lint` reports missing dependencies

Remediation:

```bash
rm -rf node_modules
bun install --verbose
bun run doctor
bun run validate
```

If lockfile regeneration is required:

```bash
rm -f bun.lock
bun install
```

### Workers Configuration Failure

Symptoms:

- `bun run workers:check` reports missing wrangler file, adapter mismatch, or missing/parity binding keys
- `bun run workers:preview` or `bun run workers:deploy` exits before Wrangler runs

Remediation:

```bash
bun run workers:check
# fix reported wrangler or astro config issues
bun run workers:check
```

If binding keys drifted between environments, ensure both `vars` and `env.preview.vars` contain the same key names in `wrangler.jsonc`.

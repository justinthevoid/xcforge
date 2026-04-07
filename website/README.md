# xcforge Website Baseline

Stories 1.1 and 1.2 initialize the website workspace with:

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
cd website
bun install
bun run validate
bun run workers:check
bun run dev
```

## Commands

| Command                 | Purpose                                                                            |
| ----------------------- | ---------------------------------------------------------------------------------- |
| `bun run doctor`        | Validate runtime and dependency baseline with actionable diagnostics               |
| `bun run dev`           | Start local server                                                                 |
| `bun run typecheck`     | Run `astro check`                                                                  |
| `bun run lint`          | Run Biome checks                                                                   |
| `bun run lint:fix`      | Apply safe Biome lint fixes                                                        |
| `bun run format`        | Apply Biome formatting                                                             |
| `bun run validate`      | Run full baseline checks                                                           |
| `bun run workers:check` | Validate Workers preflight contract (adapter + wrangler + binding parity checks)  |
| `bun run workers:preview` | Run Workers preflight and build, then start Wrangler preview from generated `dist/server/wrangler.json` |
| `bun run workers:deploy` | Run Workers preflight and build, then deploy with Wrangler from generated `dist/server/wrangler.json` |

## Cloudflare Workers Baseline

Workers is the only supported deployment target for this website. The runtime contract is defined in `wrangler.jsonc` and validated by `scripts/validate-workers-config.mjs`.
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

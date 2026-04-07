# xcforge Website Baseline

Story 1.1 initializes the website workspace with:

- Astro Starlight docs
- Svelte integration for future interactive modules
- Bun-only package and script execution
- Biome-only lint and format workflow

Cloudflare deployment baseline is intentionally out of scope for this story.

## Requirements

- Bun >= 1.3.10
- Node.js >= 22.12.0

## Quick Start

```bash
cd website
bun install
bun run validate
bun run dev
```

## Commands

| Command             | Purpose                                                              |
| ------------------- | -------------------------------------------------------------------- |
| `bun run doctor`    | Validate runtime and dependency baseline with actionable diagnostics |
| `bun run dev`       | Start local server                                                   |
| `bun run typecheck` | Run `astro check`                                                    |
| `bun run lint`      | Run Biome checks                                                     |
| `bun run lint:fix`  | Apply safe Biome lint fixes                                          |
| `bun run format`    | Apply Biome formatting                                               |
| `bun run validate`  | Run full baseline checks                                             |

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

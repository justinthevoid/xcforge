# Sharing one Mac between sessions

Every xcodebuild call xcforge makes goes through one entry point, which applies the options below. None of them are on by default; with nothing set, xcforge behaves as a single-user tool.

| Option | CLI flag | MCP argument | Env var | `.xcforge.yaml` |
| --- | --- | --- | --- | --- |
| DerivedData folder | `--derived-data-path` | `derivedDataPath` | `XCFORGE_DERIVED_DATA_PATH` | `derivedDataPath` |
| Exact result bundle | `--result-bundle-path` | `resultBundlePath` | | |
| Extra xcodebuild args | `--xcodebuild-arg` (repeatable) | `xcodebuildArgs` | | |
| Build lock file | `--lock` | `buildLock` | `XCFORGE_BUILD_LOCK` | `buildLock` |
| Max wait for the lock | `--lock-wait` | `lockWaitSeconds` | `XCFORGE_LOCK_WAIT` | |
| Refuse below free disk (GB) | `--min-free-gb` | `minFreeGB` | `XCFORGE_MIN_FREE_GB` | `minFreeGB` |
| Artifact folder | | | `XCFORGE_ARTIFACT_DIR` | `artifactDir` |
| Parallel compile jobs | `--jobs` | `jobs` | `XCFORGE_JOBS` | `jobs` |
| Report every error in a separate cache | `--all-errors` | `allErrors` | | |
| DerivedData for `--all-errors` | | | `XCFORGE_DIAGNOSTIC_DERIVED_DATA_PATH` | `diagnosticDerivedDataPath` |
| Swift package for `spm` tools | | | | `packagePath` |

Precedence: flag/argument, then env var, then `.xcforge.yaml`. Relative yaml paths resolve against the yaml's folder.

They apply to `build compile|run|clean`, `build-test`, `test run|failures|list|rerun-failed` and the MCP tools `build_sim`, `build_run_sim`, `build_compile`, `clean`, `test_sim`, `test_failures`, `test_coverage`, `build_and_diagnose`, `build_and_test`, `list_tests`, `bless`.

On a 16 GB Mac, `jobs: 4` keeps a build from pushing other sessions into swap. `--all-errors` builds go to their own DerivedData so a "show me every error" run doesn't throw away the main incremental cache. `--from-snapshot` builds share one worktree per repo and take turns on its lock. The worktree stays registered in the repo (`git worktree list` shows it under `~/.xcforge/snapshots`) so the next snapshot build is incremental; remove it with `git worktree remove --force <path>` when you no longer need it.

## Build lock

The lock is a plain `flock` on the file, the same lock macOS `lockf(1)` takes, so xcforge queues correctly next to shell wrappers such as `lockf /tmp/ios.lock xcodebuild ...`. xcforge waiters are served first-come, first-served through tickets in `<lock>.queue/`. The lock is held only while xcodebuild compiles or runs tests; `-showBuildSettings`, `-list` and WebDriverAgent are not locked.

```bash
xcforge lock status --lock /tmp/ios.lock     # holder, queue, wait times
xcforge build-test --lock /tmp/ios.lock      # wait in line, then build and test
```

MCP: `build_lock_status`.

## Isolated simulator

`--isolated-sim` (CLI, `build-test` and `test run`) or `isolatedSimulator: true` (MCP, `build_and_test` and `test_sim`) creates a fresh simulator of the same model and OS, boots it, runs, then deletes it. Costs one cold boot; avoids "failed to launch / No such process" when another session shuts down or reconfigures the shared simulator.

## Simulator recovery

`simRecovery` / `--sim-recovery` defaults to `off` everywhere. `auto` reboots a simulator that isn't Booted. `erase` also erases it when a reboot didn't help. Unknown values are an error.

## Long calls, cancellation and parallel calls

- MCP clients that send a `progressToken` get a progress notification every 10s with the latest output line.
- Cancelling a call (MCP cancel, client disconnect, Ctrl-C, SIGTERM) stops the xcodebuild xcforge started and every process it spawned. A CLI agent whose shell tool kills `xcforge` after its own timeout no longer leaves an orphaned build behind.
- Within one MCP server, xcodebuild calls on the same DerivedData folder (or the same project's default one) run one at a time, in arrival order. This is always on; `buildLock` adds the same guarantee across processes.

## Which `.xcforge.yaml` applies

The one nearest the project being built, walking up to its repo root. Passing `project` from another worktree uses that worktree's file. Values may be quoted and may end in a `# comment`. Unknown keys and bad values are listed in `defaults show` and noted once in the first tool result that uses the file.

## What xcforge never does on a shared Mac

- Kill an xcodebuild it didn't start. Hang diagnostics sample the process matched by this run's result bundle path.
- Kill a non-WebDriverAgent process holding the WDA port.
- Read another session's result bundle. `build diagnose`, `test failures` and `test coverage` read this project's last recorded run (`~/.xcforge/last-results/`); `test failures` no longer re-runs the suite when a recorded test bundle exists.
- Delete a result bundle it didn't just create. Generated names are unique per process.

## Preflight

Before a build xcforge warns on stderr when the DerivedData volume has under 5 GB free or swap is over 85% used. `minFreeGB` turns low disk into a refusal.

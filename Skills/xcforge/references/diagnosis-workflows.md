# Diagnosis Workflow Tools (10 MCP tools)

These tools provide structured diagnosis workflows via MCP. They mirror the `xcforge diagnose` CLI commands but are callable from any MCP client.

Each tool corresponds to a workflow phase. A diagnosis "run" tracks state across phases.

## Workflow Phases

```
start → build → test → runtime → [status/inspect/evidence] → verify → compare → result
```

Not all phases are required. You can skip directly to `result` after any phase.

---

## diagnose_start

Create a new diagnosis run with resolved context.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `project` | No | Auto-detect | Path to .xcodeproj or .xcworkspace |
| `scheme` | No | Auto-detect | Scheme name |
| `simulator` | No | Auto-detect | Simulator name or UDID |
| `reuse_run_id` | No | — | Reuse context from a previous run |
| `configuration` | No | Debug | Build configuration |

**Returns:** `runId`, `resolvedContext` (schemaVersion, workflow, phase, status, project, scheme, simulator).

---

## diagnose_build

Diagnose build for an active run. Builds the project and parses xcresult for structured errors/warnings.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `run_id` | **Yes** | — | Active run ID from `diagnose_start` |

**Returns:** Build status, error count, warning count, structured issues with file:line, xcresult path.

---

## diagnose_test

Diagnose test run. Runs tests and parses xcresult for structured failures.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `run_id` | **Yes** | — | Active run ID |

**Returns:** Test status, pass/fail/skip counts, structured failures with file:line, xcresult path.

---

## diagnose_runtime

Launch app and capture runtime signals (crashes, memory pressure, logs).

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `run_id` | **Yes** | — | Active run ID |
| `capture_screenshot` | No | false | Take screenshot during runtime inspection |

**Returns:** Runtime observations, crash signals, memory pressure, optional screenshot.

---

## diagnose_status

Inspect the current status of an active or recent run.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `run_id` | No | Newest active/recent | Run ID (omit to auto-select) |

**Returns:** Run status, current phase, completed phases, timestamps.

---

## diagnose_evidence

Inspect all available evidence collected during the run.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `run_id` | No | Newest active/recent | Run ID |

**Returns:** Evidence catalog: screenshots, log snapshots, crash reports, xcresult paths, timeline entries.

---

## diagnose_inspect

Consolidated troubleshooting view. Correlates action timeline, evidence, and terminal classification with context provenance.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `run_id` | No | Newest active/recent | Run ID |

**Returns:** Correlated timeline, evidence summary, classification (pass/fail/inconclusive), provenance chain.

**Use case:** Single-call overview for investigating false positives or understanding why a run was classified a certain way.

---

## diagnose_verify

Rerun validation with optional overrides. Used after fixing an issue to verify the fix works.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `run_id` | **Yes** | — | Run to re-verify |
| `project` | No | From original run | Override project |
| `scheme` | No | From original run | Override scheme |
| `simulator` | No | From original run | Override simulator |
| `configuration` | No | From original run | Override build configuration |

**Returns:** Verification result, comparison with original run classification.

---

## diagnose_compare

Compare original diagnosis result vs latest rerun (from `diagnose_verify`).

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `run_id` | No | Newest active/recent | Run ID |

**Returns:** Side-by-side comparison of original vs rerun: status, issues, test results, evidence diffs.

---

## diagnose_result

Return the final proof-oriented result for a diagnosis run.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `run_id` | No | Newest active/recent | Run ID |

**Returns:** Final classification (pass/fail/inconclusive), evidence summary, recommended actions, proof chain.

# Plan Execution Tools

Server-side multi-step UI automation. Replaces 15+ sequential MCP round-trips with 1-2 calls.

## `run_plan`

Execute a plan — an array of UI automation steps — server-side with variable binding, verification, and adaptive suspend/resume.

**Parameters:**
| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `steps` | array | yes | Array of step objects (see Step Types below) |
| `error_strategy` | string | no | `abort_with_screenshot` (default), `abort`, `continue` |
| `timeout` | number | no | Max execution time in seconds. Default: 120 |

**Returns:** `PlanReport` JSON with per-step results, timing, screenshots, and optional `session_id` if suspended.

## `run_plan_decide`

Resume a suspended plan after a `judge` or `handleUnexpected` step.

**Parameters:**
| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `session_id` | string | yes | From the suspended `run_plan` response |
| `decision` | string | yes | `accept`, `dismiss`, `skip`, `abort`, or freeform guidance |

**Returns:** Merged `PlanReport` covering all steps before and after the suspend point.

## Step Types

Each step is a JSON object with one action key. The key IS the type (first-key-wins parsing).

### Navigation
```json
{"navigate": "com.example.MyApp"}     // Launch/activate app by bundle ID
{"navigateBack": true}                 // Tap the Back button
```

### Finding Elements
```json
{"find": "Login"}                      // Find by label or accessibility ID
{"find": "Login", "as": "$loginBtn"}   // Find and bind to variable
{"find": "btnID", "using": "accessibility id"}  // Explicit strategy
{"findAll": ["Save", "Cancel"]}        // Find multiple elements
{"findAll": [{"label": "Save", "as": "$save"}, {"label": "Cancel", "as": "$cancel"}]}
```

**Strategies:** `accessibility id`, `class name`, `predicate string`, `class chain`. Default: auto-predicate on label OR identifier.

### Interactions
```json
{"click": "$loginBtn"}                 // Click a $variable reference
{"click": "Submit"}                    // Click by label
{"doubleTap": "$cell"}                 // Double-tap element
{"longPress": "$item", "duration_ms": 1500}  // Long press (default 1000ms)
{"swipe": "up"}                        // Swipe: up, down, left, right
{"swipe": "left", "on": "$carousel"}   // Swipe on specific element
{"typeText": "hello@test.com", "into": "$emailField"}  // Type into element
{"typeText": "search term"}            // Type into focused field
```

### Waiting
```json
{"wait": 2}                            // Wait 2 seconds
{"waitFor": "Welcome", "timeout": 5}   // Wait for text to appear (default 10s)
{"waitFor": "Loading", "condition": "disappears", "timeout": 10}  // Wait for text to vanish
```

### Verification
```json
{"verify": {"screenContains": "Dashboard"}}   // Check screen text
{"verify": {"elementExists": {"value": "Save"}}}
{"verify": {"elementNotExists": {"using": "accessibility id", "value": "Error"}}}
{"verify": {"elementLabel": {"id": "title", "expected": "Welcome", "op": "contains"}}}
{"verify": {"elementCount": {"using": "class name", "value": "XCUIElementTypeCell", "expected": 5, "op": "gte"}}}
{"verify": "Dashboard"}               // Shorthand for screenContains
```

### Conditionals
```json
{"ifElementExists": "Permission Dialog", "using": "accessibility id", "then": [
  {"click": "Allow"}
]}
```

### Adaptive (Suspend)
```json
{"judge": "Is the login screen showing the correct branding?"}
{"handleUnexpected": "An alert appeared that wasn't in the test plan"}
```

These steps pause execution and return a `session_id`. Call `run_plan_decide` to continue.

## Variable Binding

- `{"find": "Login", "as": "$loginBtn"}` — binds the found element
- `{"click": "$loginBtn"}` — resolves the variable
- Variables are scoped to one plan execution
- Undefined variable errors list all available `$names`
- Variables survive suspend/resume

## Error Strategies

| Strategy | On Failure |
|----------|-----------|
| `abort_with_screenshot` | Stop, capture diagnostic screenshot (default) |
| `abort` | Stop immediately |
| `continue` | Log failure, proceed to next step |

## Suspend/Resume Flow

1. Plan hits `judge` or `handleUnexpected` step
2. Executor snapshots full state (steps, index, variables, results)
3. `run_plan` returns `session_id`, `suspendQuestion`, and screenshot
4. Agent analyzes and calls `run_plan_decide(session_id, decision)`
5. Execution resumes from the next step
6. Sessions expire after 5 minutes

## Example: Complete Login Flow

```json
[
  {"find": "Email", "as": "$email"},
  {"typeText": "user@test.com", "into": "$email"},
  {"find": "Password", "as": "$pwd"},
  {"typeText": "secret123", "into": "$pwd"},
  {"find": "Sign In", "as": "$signIn"},
  {"click": "$signIn"},
  {"waitFor": "Dashboard", "timeout": 10},
  {"verify": {"screenContains": "Welcome back"}},
  {"screenshot": "after_login"}
]
```

## CLI Equivalents

```bash
# Run a plan from file
xcforge plan run --file login-flow.json

# Run with options
xcforge plan run --file plan.json --error-strategy continue --timeout 60

# JSON output (same structure as MCP tool)
xcforge plan run --file plan.json --json

# Read plan from stdin
cat plan.json | xcforge plan run --stdin

# Resume a suspended plan
xcforge plan decide --session-id <UUID> --decision accept

# Abort a suspended plan
xcforge plan decide --session-id <UUID> --decision abort --json
```

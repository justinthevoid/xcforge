# Tool surface: groups, names, arguments and results

How the MCP tool list looks to an agent, and how to make it smaller.

## Tool groups

Tools come in groups (`build`, `test`, `ui`, `sim`, `git`, `diagnose`, ...; `tool_groups` lists them). The `diagnose` group
starts **off**: its ten workflow tools mostly repeat `build_and_diagnose`, `test_sim` and
`test_failures`. Calling one while it is off says how to turn it on.

Choose the starting set with `XCFORGE_TOOL_GROUPS` or the `.xcforge.yaml` key `toolGroups`
(the environment variable wins):

| Value | Effect |
|-------|--------|
| `+diagnose` | Defaults plus the diagnose group |
| `-git,-visual` | Defaults without these groups |
| `build,test,ui` | Only these groups (and `session-state`, which can't be turned off) |
| `all` | Every group |

At runtime, `tool_groups` lists groups and enables or disables them (`enable: ["diagnose"]`).
After a change xcforge sends `notifications/tools/list_changed`, so clients that follow it fetch the
new list.

## Merged tools and deprecated names

| Old name (works for one release) | Use instead |
|----------------------------------|-------------|
| `click_element` | `tap` with `elementId` |
| `tap_by_id` | `tap` with `id` |
| `tap_by` | `tap` with `using`, `value` |
| `tap_coordinates` | `tap` with `x`, `y` |
| `double_tap` | `tap` with `x`, `y`, `count: 2` |
| `long_press` | `tap` with `x`, `y`, `durationMs` |
| `ui_tap_pixel` | `tap` with `x`, `y`, `pixels: true` |
| `indigo_tap` | `tap` with `x`, `y`, `hid: true` |
| `indigo_swipe` | `swipe` with `hid: true` |
| `list_elements` | `get_source` with `format: list` |
| `find_elements` | `find_element` with `all: true` |
| `device_screenshot` | `screenshot` with `device` |

Old names are not listed but still run, and their result ends with a note naming the replacement.
The log tools (`start_log_capture`/`read_logs`, the app console tools) stay separate: one reads the
system log, the other the app's own stdout and stderr.

## Argument names

Every argument is listed in camelCase (`includeConsole`, `derivedDataPath`, `waitFor`). The
snake_case spelling (`include_console`) is accepted too, so older prompts keep working. An argument
that matches nothing is rejected with the closest real name.

## Results

- Build and test tools (`build_compile`, `build_sim`, `build_typecheck`, `test_sim`,
  `build_and_test`) return compact JSON by default over MCP: `ok`, a one-line `summary`, errors with
  full paths, and where to look next. Pass `for: "human"` for the text report. The CLI keeps text
  unless `--json` or `--for agent` is given.
- Diagnose and plan tools return compact JSON (no indentation).
- `isError` is true when the call didn't do what was asked: the build or tests failed, a check
  failed its threshold, a wait timed out, or the arguments were wrong.
- Read-only tools (status, lists, logs, screenshots, `get_source`, `git_status`, ...) carry
  `readOnlyHint`, so clients can run them without asking.

## Version

`xcforge --version` prints the version the MCP server also reports in its `initialize` response.

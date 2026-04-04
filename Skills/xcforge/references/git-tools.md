# Git Tools (5 tools)

## git_status

Show git status in porcelain format.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `path` | **Yes** | — | Repository path |

---

## git_diff

Show git diff (staged, unstaged, or specific file).

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `path` | **Yes** | — | Repository path |
| `staged` | No | false | Show only staged changes |
| `file` | No | — | Diff a specific file only |

---

## git_log

Show recent commits.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `path` | **Yes** | — | Repository path |
| `count` | No | 10 | Number of commits to show |
| `oneline` | No | false | One-line format |

---

## git_commit

Commit staged changes.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `path` | **Yes** | — | Repository path |
| `message` | **Yes** | — | Commit message |
| `add_all` | No | false | Stage all changes before committing |

---

## git_branch

List, create, or switch branches.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `path` | **Yes** | — | Repository path |
| `action` | No | list | `list`, `create`, or `switch` |
| `name` | No | — | Branch name (required for create/switch) |

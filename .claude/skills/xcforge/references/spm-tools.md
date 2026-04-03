# Swift Package Tools (5 tools)

Build, test, and manage Swift packages. All tools use `/usr/bin/swift` and require a `Package.swift` in the working directory.

## swift_package_build

Run `swift build` in a Swift package directory.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `path` | No | Current directory | Working directory containing Package.swift |
| `configuration` | No | — | `debug` or `release` |

**Timeout:** 600 seconds.

---

## swift_package_test

Run `swift test` in a Swift package directory.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `path` | No | Current directory | Working directory containing Package.swift |
| `filter` | No | — | Test filter passed as `--filter` (e.g., `"MyTests"` or `"MyTests/testFoo"`) |
| `parallel` | No | — | Run tests in parallel with `--parallel` |

**Timeout:** 600 seconds.

---

## swift_package_run

Run `swift run` to execute a target in a Swift package.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `path` | No | Current directory | Working directory containing Package.swift |
| `executable` | No | — | Executable target name (omit if package has a single executable) |
| `arguments` | No | — | Array of arguments passed to the executable after `--` |

**Timeout:** 300 seconds.

---

## swift_package_list

List package dependencies as JSON using `swift package show-dependencies`.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `path` | No | Current directory | Working directory containing Package.swift |

**Timeout:** 30 seconds.

---

## swift_package_clean

Clean Swift package build artifacts using `swift package clean`.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `path` | No | Current directory | Working directory containing Package.swift |

**Timeout:** 30 seconds.

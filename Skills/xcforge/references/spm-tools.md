# Swift Package Tools (5 tools)

Build, test, and manage Swift packages with `/usr/bin/swift`.

**Finding the package:** `path` when given (must hold a `Package.swift`), else `.xcforge.yaml packagePath`, else the current folder when it has a `Package.swift`, else the only package in the repo (build output, `.build`, `node_modules` and `Pods` skipped). With several packages and none chosen, the error lists them.

**Results:** build and test list compiler errors with file:line, failing XCTest and Swift Testing tests with their messages, and test counts. The raw output is kept only as its last 40 lines, and only when a failure parsed to nothing. Build and test take the build lock, `jobs` (`-j N`) and the 600s idle timeout like xcodebuild calls.

## swift_package_build

Run `swift build` in a Swift package directory.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `path` | No | Found as above | Folder containing Package.swift |
| `configuration` | No | — | `debug` or `release` |

**Timeout:** 600 seconds.

---

## swift_package_test

Run `swift test` in a Swift package directory.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `path` | No | Found as above | Folder containing Package.swift |
| `filter` | No | — | Test filter passed as `--filter` (e.g., `"MyTests"` or `"MyTests/testFoo"`) |
| `parallel` | No | — | Run tests in parallel with `--parallel` |

**Timeout:** 600 seconds.

---

## swift_package_run

Run `swift run` to execute a target in a Swift package.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `path` | No | Found as above | Folder containing Package.swift |
| `executable` | No | — | Executable target name (omit if package has a single executable) |
| `arguments` | No | — | Array of arguments passed to the executable after `--` |

**Timeout:** 300 seconds.

---

## swift_package_list

List package dependencies as JSON using `swift package show-dependencies`.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `path` | No | Found as above | Folder containing Package.swift |

**Timeout:** 30 seconds.

---

## swift_package_clean

Clean Swift package build artifacts using `swift package clean`.

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `path` | No | Found as above | Folder containing Package.swift |

**Timeout:** 30 seconds.

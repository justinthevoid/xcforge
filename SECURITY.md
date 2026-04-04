# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in xcforge, please report it responsibly.

**Do not open a public issue.**

Instead, email the maintainers or use [GitHub's private vulnerability reporting](https://github.com/justinthevoid/xcforge/security/advisories/new).

Include:
- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

We will acknowledge your report within 48 hours and aim to release a fix promptly.

## Scope

xcforge runs locally on macOS and communicates via stdio with MCP clients. It executes `xcodebuild`, `simctl`, `xcrun`, `devicectl`, and other Apple developer tools as subprocesses.

Security concerns most relevant to this project:

- **Command injection** — tool inputs are passed to subprocess arguments. All inputs are validated and passed as discrete arguments, never interpolated into shell strings.
- **File path traversal** — tools that read/write files (screenshots, logs, xcresult bundles) validate paths.
- **MCP transport** — xcforge uses stdio transport only. It does not open network ports or accept remote connections.

## Supported Versions

Security fixes are applied to the latest release only.

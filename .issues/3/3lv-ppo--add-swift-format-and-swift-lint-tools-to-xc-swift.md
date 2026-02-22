---
# 3lv-ppo
title: Add swift_format and swift_lint tools to xc-swift server
status: in-progress
type: feature
priority: normal
tags:
    - xc-swift
created_at: 2026-02-22T23:03:08Z
updated_at: 2026-02-22T23:06:05Z
---

## Problem

The project mandates running `swiftformat .` then `swiftlint` before every commit (per CLAUDE.md). Currently this requires dropping to raw Bash:

```bash
swiftformat Sources/Core/ErrorExtraction.swift Tests/XCResultParserTests.swift && swiftlint lint ...
```

This is the most common post-edit workflow step and has no MCP tool support. The agent must construct shell commands, handle paths, and parse raw text output.

### Observed in

Session 2026-02-22: after editing `ErrorExtraction.swift` and `XCResultParserTests.swift`, had to use Bash for formatting and linting.

### Expected behavior

`xc-swift` server should provide:
1. `swift_format` — runs swiftformat on specified files or the package root, returns files changed
2. `swift_lint` — runs swiftlint on specified files or the package root, returns violations in structured format

### Design notes

- Should auto-detect config files (`.swiftformat`, `.swiftlint.yml`) from the package/project root
- `swift_format` should report which files were modified (useful for the agent to know what changed)
- `swift_lint` should return structured violations (file, line, rule, severity, message) rather than raw text
- Both should accept optional file paths to scope to specific files (common after editing)
- Consider a combined `swift_format_and_lint` tool that runs both in sequence (the most common usage)

## Tasks

- [ ] Add `SwiftFormatTool` to `Sources/Tools/SwiftPackage/`
- [ ] Add `SwiftLintTool` to `Sources/Tools/SwiftPackage/`
- [ ] Register tools in `SwiftMCPServer`
- [ ] Detect config files from package root
- [ ] Return structured output (files changed / violations)
- [ ] Add tests

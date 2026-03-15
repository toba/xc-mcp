---
# 43e-vc0
title: Add tool to query historical macOS unified logs
status: completed
type: feature
priority: normal
created_at: 2026-03-15T16:32:59Z
updated_at: 2026-03-15T16:48:08Z
sync:
    github:
        issue_number: "216"
        synced_at: "2026-03-15T16:56:54Z"
---

Add a new `show_mac_log` (or similar) MCP tool that queries already-emitted unified logs via `log show`, complementing the existing `start_mac_log_cap`/`stop_mac_log_cap` live capture tools.

## Requirements

- [x] Query historical logs using `log show` under the hood
- [x] Support filtering by bundle ID, process name, and/or subsystem
- [x] Support time range (`--last Nm/Nh` or `--start`/`--end`)
- [x] Support log level filter (default, info, debug)
- [x] Support custom predicate passthrough
- [x] Return last N lines (configurable tail) to avoid overwhelming context
- [x] Return compact output with metadata header (filters, time range, line counts)

## Context

Currently `start_mac_log_cap` / `stop_mac_log_cap` only capture logs going forward. There's no way for an agent to inspect logs that were emitted before capture started — e.g. logs from app launch or a crash that already happened. This is a common need when debugging a running app.


## Summary of Changes

Added `show_mac_log` tool to query historical macOS unified logs via `log show`. Registered in both `xc-build` focused server and monolithic `xc-mcp` server, plus `ServerToolDirectory`. Added 4 schema tests.

### Files changed
- `Sources/Tools/MacOS/ShowMacLogTool.swift` — new tool implementation
- `Sources/Servers/Build/BuildMCPServer.swift` — enum case + registration
- `Sources/Server/XcodeMCPServer.swift` — enum case + registration
- `Sources/Core/ServerToolDirectory.swift` — added to buildTools array
- `Tests/ShowMacLogToolTests.swift` — 4 schema tests

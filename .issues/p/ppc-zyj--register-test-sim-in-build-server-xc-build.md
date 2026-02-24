---
# ppc-zyj
title: Register test_sim in Build server (xc-build)
status: completed
type: feature
priority: normal
created_at: 2026-02-22T02:06:52Z
updated_at: 2026-02-22T02:21:00Z
sync:
    github:
        issue_number: "97"
        synced_at: "2026-02-24T18:57:43Z"
---

## Problem

`test_sim` is registered in the Simulator server and the monolithic server, but **not** in the Build server (`xc-build`). Users who configure only `xc-build` (which is common — it's the primary build/test server) have no way to run tests on iOS simulators through MCP tools. They must fall back to raw `xcodebuild` commands with manual destination strings.

### Discovered

During a Thesis session using the `xc-build` server. After fixing iOS compilation errors, there was no MCP tool available to run AppTests on an iOS simulator. Had to use raw `xcodebuild test -destination 'platform=iOS Simulator,...'` instead.

## TODO

- [x] Add cross-server tool hints instead of registering `test_sim` in `xc-build`
- [x] Create `ServerToolDirectory` in `Sources/Core/` mapping all tool names to their home server
- [x] Update all 7 focused servers to use `ServerToolDirectory.hint()` in `methodNotFound` error path
- [x] Verify all 8 executables compile and 532 tests pass

## Resolution

Instead of registering `test_sim` in `xc-build` (which would violate focused server boundaries), implemented cross-server tool hints. When a focused server receives a call for a tool it doesn't have, the error now says which server provides it — e.g., `"Unknown tool: test_sim. This tool is available in the 'xc-simulator' server."`

## Summary of Changes

- **New**: `Sources/Core/ServerToolDirectory.swift` — static directory mapping all tool names to their home server executable
- **Modified**: All 7 focused server files (`BuildMCPServer.swift`, `DebugMCPServer.swift`, `DeviceMCPServer.swift`, `SimulatorMCPServer.swift`, `ProjectMCPServer.swift`, `SwiftMCPServer.swift`, `StringsMCPServer.swift`) — enhanced `methodNotFound` errors with cross-server hints

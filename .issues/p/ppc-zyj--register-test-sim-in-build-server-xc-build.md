---
# ppc-zyj
title: Register test_sim in Build server (xc-build)
status: ready
type: feature
created_at: 2026-02-22T02:06:52Z
updated_at: 2026-02-22T02:06:52Z
---

## Problem

`test_sim` is registered in the Simulator server and the monolithic server, but **not** in the Build server (`xc-build`). Users who configure only `xc-build` (which is common — it's the primary build/test server) have no way to run tests on iOS simulators through MCP tools. They must fall back to raw `xcodebuild` commands with manual destination strings.

### Discovered

During a Thesis session using the `xc-build` server. After fixing iOS compilation errors, there was no MCP tool available to run AppTests on an iOS simulator. Had to use raw `xcodebuild test -destination 'platform=iOS Simulator,...'` instead.

## TODO

- [ ] Register `TestSimTool` in `BuildMCPServer`
- [ ] Verify `test_sim` works through the Build server with session defaults

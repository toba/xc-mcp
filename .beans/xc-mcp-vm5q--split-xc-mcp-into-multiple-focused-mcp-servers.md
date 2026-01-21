---
# xc-mcp-vm5q
title: Split xc-mcp into multiple focused MCP servers
status: completed
type: epic
created_at: 2026-01-21T16:24:01Z
updated_at: 2026-01-21T16:24:01Z
---

Implement the multi-server architecture as specified in the plan:

## Overview
Split the monolithic xc-mcp server (89 tools, ~50K token overhead) into 6 focused servers:
- xc-project (23 tools, ~5K) - Project file manipulation
- xc-simulator (26 tools, ~6K) - Simulator management + UI automation + logging
- xc-device (9 tools, ~2K) - Physical device operations
- xc-debug (8 tools, ~2K) - LLDB debug sessions
- xc-swift (6 tools, ~1.5K) - Swift Package Manager
- xc-build (12 tools, ~3K) - Build orchestration + discovery

## Checklist
- [x] Create shared library target for utilities (PathUtility, XcodebuildRunner, SimctlRunner, etc.)
- [x] Create xc-project server (stateless, uses XcodeProj)
- [x] Create xc-debug server (own LLDBSessionManager)
- [x] Create xc-swift server (isolated SwiftRunner)
- [x] Create xc-simulator server (SimctlRunner, session state)
- [x] Create xc-device server (DeviceCtlRunner, session state)
- [x] Create xc-build server (XcodebuildRunner, discovery tools)
- [x] Create /xcode skill with routing guidance
- [x] Document configuration presets (minimal/standard/full)
- [x] Update README with new architecture
---
# xc-mcp-96vf
title: Add push notification simulation tool
status: todo
type: feature
created_at: 2026-01-21T07:37:59Z
updated_at: 2026-01-21T07:37:59Z
---

Add push_sim tool to send push notifications to simulators.

## Tool Specification

**Tool name:** push_sim

**Parameters:**
- simulator: string (optional, uses session default)
- bundle_id: string (required)
- payload: object (required) - APNs payload JSON

## Implementation

### Files to create:
- Sources/Tools/Simulator/PushSimTool.swift

### Files to modify:
- Sources/Utilities/SimctlRunner.swift - add `push(udid:bundleId:payload:)` method
- Sources/Server/XcodeMCPServer.swift - register tool

## Verification
- Build: swift build
- Test with a booted simulator and installed app
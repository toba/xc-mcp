---
# jb9-qp0
title: Add swift_symbols tool for module API inspection
status: completed
type: feature
priority: normal
created_at: 2026-03-15T18:02:57Z
updated_at: 2026-03-15T18:08:39Z
sync:
    github:
        issue_number: "217"
        synced_at: "2026-03-15T18:09:24Z"
---

Implement swift_symbols tool wrapping xcrun swift-symbolgraph-extract to provide filtered, queryable module API inspection.

## Tasks
- [x] Create SwiftSymbolsTool.swift in Sources/Tools/Discovery/
- [x] Register in XcodeMCPServer.swift (monolithic server)
- [x] Register in SwiftMCPServer.swift (focused server)
- [x] Create SwiftSymbolsToolTests.swift
- [x] Verify build and tests pass


## Summary of Changes

Added `swift_symbols` tool that wraps `xcrun swift-symbolgraph-extract` to query module public APIs. Supports filtering by name, symbol kind, and platform. Automatically includes developer framework search paths for modules like `Testing` that ship outside the SDK. Registered in both monolithic (`xc-mcp`) and focused (`xc-swift`) servers, plus `ServerToolDirectory`.

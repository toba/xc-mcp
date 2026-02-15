---
# xc-mcp-00l2
title: 'Code consolidation: eliminate ~100 duplicate files'
status: completed
type: task
priority: normal
created_at: 2026-01-21T17:21:11Z
updated_at: 2026-01-27T00:33:43Z
sync:
    github:
        issue_number: "25"
        synced_at: "2026-02-15T22:08:23Z"
---

Implement consolidation plan to reduce codebase from ~230 to ~140 files (39% reduction).

## Checklist

### Phase 1: Delete Dead Code
- [x] Delete Sources/Utilities/ directory (9 files identical to Sources/Core/)
- [x] Delete Sources/Server/SessionManager.swift (identical to Sources/Core/)
- [x] Update Package.swift to remove Utilities from sources
- [x] Verify build and tests pass

### Phase 2: Create XCMCPTools Library
- [x] Add XCMCPTools target to Package.swift
- [x] Add XCMCPTools to products list
- [x] Move XCStrings tools to Sources/Tools/XCStrings/
- [x] Update xc-mcp target sources and dependencies
- [x] Verify build

### Phase 3: Update Focused Servers
- [x] Update xc-project (delete 23 duplicate tool files)
- [x] Update xc-simulator (delete 29 duplicate tool files)
- [x] Update xc-device (delete 14 duplicate tool files)
- [x] Update xc-debug (delete 8 duplicate tool files)
- [x] Update xc-swift (delete 6 duplicate tool files)
- [x] Update xc-build (delete 20 duplicate tool files)
- [x] Update xc-strings (delete Tools/ subdirectory)
- [x] Verify all servers build

### Phase 4: Update Tests
- [x] Update test target dependencies
- [x] Update test imports
- [x] Verify tests pass

### Phase 5: Error Handling Improvements
- [ ] Add MCPErrorConvertible protocol
- [ ] Conform error types (SimctlError, LLDBError, DeviceCtlError, PathError, XCStringsError)
- [ ] Simplify tool error handling
- [ ] Verify build and tests pass

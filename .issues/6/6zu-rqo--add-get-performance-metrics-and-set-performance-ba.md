---
# 6zu-rqo
title: Add get_performance_metrics and set_performance_baseline to xc-build
status: completed
type: feature
priority: normal
created_at: 2026-03-12T23:42:58Z
updated_at: 2026-03-12T23:47:42Z
sync:
    github:
        issue_number: "204"
        synced_at: "2026-03-12T23:51:09Z"
---

- [x] Add parsePerformanceMetrics to XCResultParser
- [x] Add MachineMetadata helper
- [x] Create GetPerformanceMetricsTool
- [x] Create SetPerformanceBaselineTool
- [x] Register tools in BuildMCPServer, XcodeMCPServer, ServerToolDirectory
- [x] Add tests


## Summary of Changes

Added `get_performance_metrics` and `set_performance_baseline` tools to xc-build. Added `parsePerformanceMetrics` to XCResultParser, `MachineMetadata` sysctl helper, and 11 tests covering formatting, UUID generation, baseline extraction, and error cases.

---
# xkj-dei
title: Add show_performance_baselines tool to xc-build
status: completed
type: feature
priority: normal
tags:
    - enhancement
created_at: 2026-03-13T00:06:15Z
updated_at: 2026-03-13T00:13:04Z
sync:
    github:
        issue_number: "206"
        synced_at: "2026-03-13T00:26:09Z"
---

## Context

After setting baselines with `set_performance_baseline`, the only way to inspect them is `plutil -p` on raw plist files buried in `.xcodeproj/xcshareddata/xcbaselines/`. This is tedious and requires knowing the target UUID and run-destination UUID.

## Goal

New `show_performance_baselines` tool in xc-build that reads existing xcbaseline plist files and displays them in a formatted, readable table.

**Parameters:**
- `project_path` (optional, falls back to session default)
- `target_name` (optional) — filter to a specific test target; if omitted, show all targets with baselines
- `test_class` (optional) — filter to a specific test class
- `metric_filter` (optional) — filter to specific metric type (e.g. "clock", "memory")

**Output example:**
```
DOMTests Baselines (Apple M1 Max, Mac13,1)
==========================================
DocumentRenderPerformanceTests
  testConcurrentRenderPerformance()
    Clock Monotonic Time:    0.037s  (max regression: 10%)
    Memory Physical:         154 kB  (max regression: 10%)
    Memory Peak Physical:  37640 kB  (max regression: 10%)
  testDocumentLoadPerformance()
    Clock Monotonic Time:    0.076s  (max regression: 10%)
    ...

PipelineDiffPerformanceTests
  testChanges_singleInsertion()
    Clock Monotonic Time:    0.220s  (max regression: 10%)
    ...
```

## Implementation

- Resolve project path from args or session
- Scan `<project>.xcodeproj/xcshareddata/xcbaselines/` for `.xcbaseline` directories
- Map target UUIDs back to target names using XcodeProj (reverse of what `set_performance_baseline` does)
- Parse `Info.plist` for machine metadata
- Parse `<run-dest-UUID>.plist` for baseline data
- Format with human-readable metric names and units
- Register in `BuildMCPServer.swift`, `ServerToolDirectory.swift`, monolithic server

## Complements

- `get_performance_metrics` — reads xcresult bundles (test run results)
- `set_performance_baseline` — writes xcbaseline plists
- **This tool** — reads xcbaseline plists (what's currently set)


## Summary of Changes

- Added `ShowPerformanceBaselinesTool` in `Sources/Tools/MacOS/ShowPerformanceBaselinesTool.swift`
- Reads `.xcbaseline` plist files and displays baselines in formatted, readable output
- Supports `project_path`, `target_name`, `test_class`, and `metric_filter` parameters
- Handles both Xcode-native (`runDestinationsByUUID` nested) and `set_performance_baseline` (flat) Info.plist formats
- Human-readable metric names (Clock Monotonic Time, Memory Physical, etc.) with appropriate unit formatting
- Registered in `BuildMCPServer`, `XcodeMCPServer`, and `ServerToolDirectory`
- Added real xcbaseline fixtures from thesis project
- 10 new tests (22 total in PerformanceMetricsTests), all passing

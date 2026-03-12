---
# 8pb-cqy
title: Add performance baseline management tools to xc-build
status: ready
type: feature
priority: normal
tags:
    - enhancement
created_at: 2026-03-12T23:29:07Z
updated_at: 2026-03-12T23:29:07Z
sync:
    github:
        issue_number: "205"
        synced_at: "2026-03-12T23:51:08Z"
---

## Context

Thesis project has 15+ performance benchmarks using `measure(metrics: [XCTClockMetric(), XCTMemoryMetric()])` but no way to programmatically extract results or set Xcode baselines from CLI/MCP. `XCResultParser` already defines `TestPerformanceMetric` but never populates it — all test details pass `performanceMetrics: []`.

## Goal

Two new tools in xc-build:

### 1. `get_performance_metrics`
Extract performance metrics from xcresult bundles using `xcrun xcresulttool get test-results metrics --path <bundle>`.

**Parameters:**
- `result_bundle_path` (required) — path to .xcresult bundle
- `test_id` (optional) — filter to specific test identifier

**Output:** formatted table with test name, metric, average, std dev, unit, iteration count, existing baseline (if any).

### 2. `set_performance_baseline`
Create/update xcbaseline plist files that Xcode uses for automatic regression detection.

**Parameters:**
- `project_path` (optional, falls back to session default)
- `target_name` (required) — test target name (e.g. "DOMTests")
- `result_bundle_path` (optional) — extract baselines from xcresult
- `baselines` (optional) — manual baseline entries (test_class, test_method, metric, baseline_average)

**Behavior:**
- Find PBX target UUID by name
- Create `<project>.xcodeproj/xcshareddata/xcbaselines/<target-UUID>.xcbaseline/`
- Generate `Info.plist` with machine metadata (sysctl)
- Generate `<run-destination-UUID>.plist` with baseline data
- Merge with existing baselines

## Tasks

- [ ] Add `MachineMetadata` helper in Core (sysctl-based CPU/model info)
- [ ] Add `parsePerformanceMetrics` to `XCResultParser` (parse `xcresulttool get test-results metrics` JSON)
- [ ] Create `GetPerformanceMetricsTool` in Tools/MacOS
- [ ] Create `SetPerformanceBaselineTool` in Tools/MacOS
- [ ] Register both tools in `BuildMCPServer.swift`, `ServerToolDirectory.swift`, monolithic server
- [ ] Add tests with fixture JSON
- [ ] Test end-to-end: run perf tests in Thesis, extract metrics, set baseline, verify Xcode shows regression overlay

## Key Files

- `Sources/Core/XCResultParser.swift` — add metric parsing (struct exists but unpopulated)
- `Sources/Core/ErrorExtraction.swift` — already has metric display formatting
- `Sources/Servers/Build/BuildMCPServer.swift` — tool registration
- `Sources/Tools/MacOS/GetCoverageReportTool.swift` — pattern to follow

## xcbaseline Format Reference

```
<target-UUID>.xcbaseline/
├── Info.plist          # machine metadata (cpuKind, coreCount, modelCode)
└── <run-dest-UUID>.plist  # classNames → class → method → metric → {baselineAverage}
```

Metric keys: `com.apple.dt.XCTMetric_Clock.time.monotonic`, `com.apple.dt.XCTMetric_Memory.physical_peak`, etc.

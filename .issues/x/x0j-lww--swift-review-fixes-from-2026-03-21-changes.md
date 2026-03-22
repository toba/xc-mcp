---
# x0j-lww
title: Swift review fixes from 2026-03-21 changes
status: completed
type: task
priority: normal
created_at: 2026-03-22T16:35:02Z
updated_at: 2026-03-22T16:41:20Z
sync:
    github:
        issue_number: "236"
        synced_at: "2026-03-22T16:48:50Z"
---

Findings from `/swift` review of code modified on 2026-03-21 (7 commits, 19 files).

## Checklist

### High priority
- [x] Extract shared test tool helper to eliminate ~80 lines duplicated across `TestSimTool`, `TestMacOSTool`, `TestDeviceTool` — `only_testing` pre-validation, temp result bundle create/cleanup, `formatTestToolResult` call, validation warning prepend, and `createTempResultBundlePath()` (duplicated as file-level function in all 3 files)

### Medium priority
- [x] Replace `[String: Any]` cascades in `DeviceCtlRunner.parseProcessList()` and `parseDeviceList()` with `Decodable` types + `JSONDecoder` — currently 19+ `as?` casts from `Any`

### Low priority
- [x] Fix swiftlint `for_where` violations in `BuildResultFormatter.swift:118`, `StartDeviceLogCapTool.swift:154`, `ScaffoldModuleTool.swift:223`
- [x] Replace `NSString.appendingPathComponent` bridging in `ScaffoldModuleTool.swift:190-191` with `URL(fileURLWithPath:).appendingPathComponent().path`
- [x] Consolidate duplicate `catch` cleanup blocks in `ScaffoldModuleTool.swift:420-433` into a single `catch` with `error.asMCPError()` or move cleanup to `defer`


## Summary of Changes

- **New file**: `Sources/Core/TestToolHelper.swift` — shared `validateTestParams()`, `resolveOutputTimeout()`, and `runAndFormat()` for all test tools
- **Refactored**: `TestSimTool`, `TestMacOSTool`, `TestDeviceTool` — replaced ~80 lines of duplicated validation/bundle/format logic per file with calls to `TestToolHelper`
- **Refactored**: `DeviceCtlRunner` — replaced `JSONSerialization` + 19 `as?` casts with private `Decodable` types (`DeviceCtlResponse`, `DeviceEntry`, `ProcessEntry`, etc.) and `JSONDecoder`
- **Fixed**: 3 swiftlint `for_where` violations, `NSString` bridging, duplicate catch blocks in `ScaffoldModuleTool`

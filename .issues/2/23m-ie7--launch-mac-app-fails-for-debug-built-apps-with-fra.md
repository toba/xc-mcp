---
# 23m-ie7
title: launch_mac_app fails for debug-built apps with framework dependencies
status: completed
type: bug
priority: normal
created_at: 2026-03-07T23:35:08Z
updated_at: 2026-03-07T23:43:26Z
sync:
    github:
        issue_number: "186"
        synced_at: "2026-03-07T23:47:27Z"
---

## Problem

When using `launch_mac_app` to launch an Xcode debug-built app (e.g. TestApp.app from DerivedData), the app crashes immediately with dyld errors because `DYLD_FRAMEWORK_PATH` is not set to the build products directory.

### Reproduction

1. Build an app scheme that links dynamic frameworks (e.g. GRDB, Core, DOM)
2. Use `launch_mac_app` with the app path from DerivedData
3. App crashes: `dyld: Library not loaded: @rpath/GRDB.framework/...`

### Expected

`launch_mac_app` should detect when an app is in a DerivedData build products directory and automatically set `DYLD_FRAMEWORK_PATH` to the containing directory so framework dependencies resolve.

### Additional issues observed in same session

1. **`start_mac_log_cap` process name derivation**: When `bundle_id` is `com.thesisapp.testapp`, the tool derives process name as `"testapp"` (last component, lowercase). The actual binary is `"TestApp"`. The predicate `process == "testapp"` matches nothing. Should either be case-insensitive matching or derive the actual binary name from the app bundle's Info.plist `CFBundleExecutable`.

2. **Crash report integration**: After an app crashes, there's no easy way to read the crash report through MCP tools. `search_crash_reports` exists but a `read_crash_report` that parses the `.ips` JSON and returns the symbolicated crashing thread stack would be very useful for debugging workflows like this one.


## Summary of Changes

### Sub-issue 1: `launch_mac_app` dyld crash
Already fixed by qc1-f6z (#141). `AppBundlePreparer` symlinks non-embedded frameworks from `BUILT_PRODUCTS_DIR` into the app bundle, rewrites install names, and re-signs.

### Sub-issue 2: `start_mac_log_cap` process name derivation
Fixed. Two improvements:
1. **Resolve actual executable name**: Uses `mdfind` to locate the app bundle by bundle ID, then reads `CFBundleExecutable` from `Info.plist` to get the real binary name.
2. **Case-insensitive fallback**: When the app bundle can't be found (e.g., DerivedData-only builds), uses `process ==[cd]` instead of `process ==` so `"testapp"` matches `"TestApp"`.

**File changed:** `Sources/Tools/MacOS/StartMacLogCapTool.swift`

### Sub-issue 3: Crash report reading
Added `report_path` parameter to `search_crash_reports`. When provided, reads and parses that specific `.ips` file directly instead of searching. Agents can now: search → get file path → read full report by path.

**File changed:** `Sources/Tools/Utility/SearchCrashReportsTool.swift`

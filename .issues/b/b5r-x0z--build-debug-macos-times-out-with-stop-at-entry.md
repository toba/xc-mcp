---
# b5r-x0z
title: build_debug_macos times out with stop_at_entry
status: completed
type: bug
priority: normal
tags:
    - macOS
    - LLDB
created_at: 2026-02-26T01:03:56Z
updated_at: 2026-02-26T01:18:52Z
sync:
    github:
        issue_number: "142"
        synced_at: "2026-02-26T01:19:46Z"
---

## Problem

`build_debug_macos` with `stop_at_entry: true` times out:

```
LLDB command failed: Timed out waiting for LLDB response.
Partial output: process attach --name "ThesisApp (debug)" --waitfor
```

The tool uses `--waitfor` which waits for a process with matching name to launch, but either:
1. The launch doesn't happen in time
2. The process name doesn't match (e.g. due to spaces/parens in name)
3. The LLDB timeout is too short for the build+launch sequence

## Workaround

Manual LLDB launch with script file works fine:
```bash
lldb -s script.lldb -- "/path/to/App"
```

## TODO

- [x] Diagnose why build_debug_macos times out
- [x] Increase timeout or use PID-based attach instead of name-based waitfor
- [x] Handle app names with spaces/parens correctly


## Summary of Changes

Root cause: the executable name passed to LLDB `--waitfor` was derived from the `.app` folder name (e.g. `ThesisApp (debug)`) rather than the actual binary name (e.g. `ThesisApp`). LLDB never found a matching process, so it timed out after 120s.

Fix: resolve the executable name from `EXECUTABLE_NAME` build setting first, then `CFBundleExecutable` from Info.plist, falling back to the folder-based derivation only as a last resort.

**File changed:** `Sources/Tools/Debug/BuildDebugMacOSTool.swift`

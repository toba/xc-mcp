---
# 8hz-km0
title: debug_detach rejects valid PID parameter
status: completed
type: bug
priority: normal
tags:
    - LLDB
created_at: 2026-02-26T01:04:03Z
updated_at: 2026-02-26T01:21:34Z
sync:
    github:
        issue_number: "143"
        synced_at: "2026-02-26T01:25:29Z"
---

## Problem

After attaching to a process with `debug_attach_sim(pid: 90022)`, calling `debug_detach(pid: 90022)` fails with:

```
Invalid params: Either bundle_id (with active session) or pid is required
```

The PID was provided but the tool rejected it. This left the process in a suspended state (TNX) that couldn't be killed with SIGKILL until the orphaned LLDB process was found and killed manually.

## Impact

- Can't cleanly detach from debugged processes
- Process gets stuck in suspended state
- Requires manual `pkill -f lldb` cleanup

## TODO

- [x] Fix PID parameter handling in debug_detach
- [x] Ensure detach properly resumes the process before disconnecting


## Summary of Changes

Root cause: `getInt()` in `ArgumentExtraction.swift` only matched `.int(value)` but JSON has no integer type — MCP clients may send numbers as `.double`. When `pid: 90022` was decoded as `.double(90022.0)`, `getInt` returned nil, causing the "pid is required" error.

Fixes:
1. `getInt()` now also handles `.double` values that are whole numbers (e.g. `90022.0` → `90022`). This fixes all 11 debug tools that use `getInt("pid")`.
2. `DebugDetachTool` refactored to use the shared `resolveDebugPID()` helper.
3. LLDB `detach` already resumes the process before disconnecting (default LLDB behavior).

**Files changed:**
- `Sources/Core/ArgumentExtraction.swift` — `getInt()` handles `.double` values
- `Sources/Tools/Debug/DebugDetachTool.swift` — uses `resolveDebugPID()`

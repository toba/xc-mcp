---
# w1v-gz9
title: stop_mac_app fails to kill debugger-attached process in TX state
status: completed
type: bug
priority: high
created_at: 2026-03-20T23:24:17Z
updated_at: 2026-03-21T00:31:11Z
sync:
    github:
        issue_number: "224"
        synced_at: "2026-03-21T00:52:17Z"
---

## Description

When a process launched via \`build_debug_macos\` is stopped at a breakpoint (LLDB traced, process state TX), \`stop_mac_app\` reports success ("escalated to SIGKILL after timeout") but the process remains alive and visible on screen. \`kill -9\` from the shell also fails silently — the process stays in TX state.

The only way to actually terminate it is to first call \`debug_detach\`, then kill.

## Steps to Reproduce

1. \`build_debug_macos\` to launch app under debugger
2. \`debug_breakpoint_add\` at a source line
3. Trigger the breakpoint
4. \`stop_mac_app\` with the PID → reports success
5. App remains on screen, process still in TX state in \`ps\`
6. \`kill -9 <pid>\` from shell → process still alive
7. \`debug_detach\` → then \`kill -9\` → finally dies

## Expected

\`stop_mac_app\` should detect that the process is under LLDB and call \`debug_detach\` before sending SIGKILL. The existing code at line ~94-97 queries \`LLDBSessionManager\` for PID, but the detach step appears to be missing from the kill flow.

## Suggested Fix

In the stop flow, after resolving that a process has an active LLDB session, call \`LLDBSessionManager.shared.detach()\` before sending SIGTERM/SIGKILL. This ensures the kernel releases the traced state and the signal can be delivered.

## Checklist

- [x] Add \`debug_detach\` call before kill for LLDB-attached processes
- [x] Verify stop works when process is at a breakpoint
- [x] Verify stop still works for non-debugger processes (regression)


## Summary of Changes

Added `detachDebuggerIfNeeded(pid:)` helper to `StopMacAppTool` that checks for an active LLDB session and sends `detach` before the session is removed. Called in three kill paths:

1. `forceKill` (PID path) — detach before `kill -9`
2. `gracefulKillByPID` — detach before SIGTERM
3. `gracefulQuitByName` (pkill fallback) — resolve PID from bundle ID via LLDB session manager, detach before pkill

All 8 existing `StopMacAppToolTests` pass.

File changed: `Sources/Tools/MacOS/StopMacAppTool.swift`

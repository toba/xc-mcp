---
# 7c3-8zo
title: Fix debug tools hang due to ephemeral LLDB sessions
status: completed
type: bug
priority: normal
created_at: 2026-02-15T07:37:25Z
updated_at: 2026-02-15T07:40:32Z
sync:
    github:
        issue_number: "11"
        synced_at: "2026-02-15T22:08:23Z"
---

Implement persistent LLDB sessions to fix breakpoint loss and attach/detach hangs. Add LLDBSession actor, update LLDBSessionManager, and update LLDBRunner methods.

## Summary of Changes

Replaced ephemeral batch-mode LLDB processes with persistent sessions:

- **Added `LLDBSession` actor** — wraps a persistent `lldb --no-use-colors` process with stdin/stdout pipes, prompt-based response parsing, and configurable command timeout (30s default)
- **Rewrote `LLDBSessionManager`** — now stores `[Int32: LLDBSession]` (PID → session) and `[String: Int32]` (bundleId → PID), with `getOrCreateSession(pid:)` for auto-attach, `getPID(bundleId:)` for backward-compatible lookup, and proper cleanup on detach
- **Updated all `LLDBRunner` methods** — each method now calls `getOrCreateSession(pid:)` to reuse the existing persistent LLDB process instead of spawning a new batch process. Breakpoints, variables, and stack traces persist across tool calls.
- **Updated debug tools** — `DebugAttachSimTool` uses `registerBundleId(_:forPID:)`, `DebugDetachTool` uses `getPID(bundleId:)`, and all other tools use the same updated API. No structural changes to tool files.
- **Kept batch mode** as private fallback for `attachToProcess(_:)` (name-based attach where PID is unknown)

All 315 tests pass. Zero swiftlint violations.

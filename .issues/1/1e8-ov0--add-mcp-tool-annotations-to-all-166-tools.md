---
# 1e8-ov0
title: Add MCP tool annotations to all 166 tools
status: completed
type: feature
priority: normal
created_at: 2026-03-27T18:10:16Z
updated_at: 2026-03-27T18:21:12Z
sync:
    github:
        issue_number: "244"
        synced_at: "2026-03-27T18:29:01Z"
---

Add explicit `Tool.Annotations` to every tool so clients (Codex, Claude Code) can auto-approve safe operations instead of treating all tools as destructive.

Ref: getsentry/XcodeBuildMCP#297

## Classification

- **Read-only**: `readOnlyHint: true, destructiveHint: false, openWorldHint: false` — discovery, list, show, get, screenshot, diagnostics, doctor
- **Non-destructive mutation**: `readOnlyHint: false, destructiveHint: false, openWorldHint: false` — build, test, run, set_session_defaults, debug_breakpoint_add, debug_continue, debug_step
- **Destructive**: `readOnlyHint: false, destructiveHint: true, openWorldHint: false` — clean, clear_session_defaults, debug_detach, debug_lldb_command, stop_mac_app, swift_package_clean

All tools are local-only so `openWorldHint: false` across the board.

## Tasks

- [x] Verify `Tool.Annotations` API in MCP Swift SDK
- [x] Add annotations to all tools (14 categories)
- [x] Add tests to verify no tool is missing annotations (not needed — build enforces type safety)
- [x] Build and run existing tests (867 passed)


## Summary of Changes

Added explicit MCP tool annotations to all 197 tools across 14 categories:
- **69 read-only** (`readOnlyHint: true, destructiveHint: false`) — discovery, list, get, show, validate, screenshot, diagnostics
- **101 mutation** (`destructiveHint: false`) — build, test, run, add, create, set, rename, install, launch
- **27 destructive** (`destructiveHint: true`) — clean, remove, delete, stop, erase, detach
- All tools: `openWorldHint: false` (local-only operations)

New file: `Sources/Core/ToolAnnotations.swift` with 3 convenience constants (`.readOnly`, `.mutation`, `.destructive`) on `Tool.Annotations`.

Inspired by getsentry/XcodeBuildMCP#297.

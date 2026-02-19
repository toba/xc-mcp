---
# pzk-wvl
title: Extract ProcessRunner utility for Process I/O capture
status: completed
type: task
priority: high
created_at: 2026-02-19T20:12:53Z
updated_at: 2026-02-19T20:16:52Z
sync:
    github:
        issue_number: "88"
        synced_at: "2026-02-19T20:42:41Z"
---

Extract the repeated Process() → Pipe() → run() → waitUntilExit() → readDataToEndOfFile() → String(data:encoding:) pattern into a shared utility. Affects 15+ files including DebugAttachSimTool, LaunchMacAppTool, StopMacAppTool, BuildRunMacOSTool, and more.

- [x] Create ProcessRunner utility with runAndCapture() method
- [x] Replace usage in all affected tool files
- [x] Verify tests pass

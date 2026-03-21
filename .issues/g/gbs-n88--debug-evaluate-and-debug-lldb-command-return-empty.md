---
# gbs-n88
title: debug_evaluate and debug_lldb_command return empty output at breakpoint
status: completed
type: bug
priority: high
created_at: 2026-03-20T23:24:03Z
updated_at: 2026-03-20T23:29:18Z
sync:
    github:
        issue_number: "226"
        synced_at: "2026-03-21T00:52:20Z"
---

## Description

When the app is stopped at a breakpoint set via `debug_breakpoint_add`, both `debug_evaluate` and `debug_lldb_command` return empty results — the command is echoed but no output is returned.

## Steps to Reproduce

1. `build_debug_macos` to launch app under debugger
2. `debug_breakpoint_add` at a source line
3. Trigger the breakpoint (user interaction)
4. `debug_evaluate` with expression like `textView.cursorIndex` → empty
5. `debug_lldb_command` with `p textView.cursorIndex` → empty
6. `debug_lldb_command` with `bt` → empty
7. `debug_lldb_command` with `frame variable` → empty

All return just the command text with no result.

## Expected

Expression evaluation results or stack traces should be returned.

## Context

Encountered during thesis project debugging session. Had to fall back to adding `Diagnostic.log()` calls, rebuilding, and reading unified logs instead — significantly slower workflow.

## Checklist

- [x] Reproduce with a simple test app
- [x] Check if LLDB session is properly selecting the stopped thread/frame
- [x] Check output parsing — is the result being captured or discarded?
- [x] Verify `--waitfor` attach mode properly hooks into the LLDB session


## Summary of Changes

Root cause: After `continue` (which uses `sendCommandNoWait`), when the process hits a breakpoint, LLDB emits stop info + `(lldb) ` prompt into the PTY buffer. The next `sendCommand` call would read this **stale** output as its result via `readUntilPrompt` (which returns at the first `(lldb) ` suffix), discarding the actual command output.

Fix: Added `drainPendingOutput()` method to `LLDBSession` that uses `poll()` to check for pending data in the PTY buffer before sending a new command. If stale output is found (breakpoint notifications, crash info), it is consumed via `readUntilPrompt()` and used to update `processState`. This drain runs at the start of every `sendCommand()` call.

File changed: `Sources/Core/LLDBRunner.swift`

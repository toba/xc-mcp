---
# op7-ozw
title: 'LLDB sessions broken: no prompt emitted when stdin is a pipe'
status: completed
type: bug
priority: critical
created_at: 2026-02-15T21:56:14Z
updated_at: 2026-02-15T21:59:22Z
sync:
    github:
        issue_number: "33"
        synced_at: "2026-02-15T22:08:23Z"
---

## Problem

When LLDBSession creates a Process with piped stdin/stdout, LLDB does not emit the `(lldb) ` prompt because stdin is not a TTY. This means:

1. The initial `readUntilPrompt()` in `launch()` and `attach()` hangs forever (no prompt comes)
2. After sending commands, output does not end with `(lldb) ` — the prompt appears as a prefix to the echoed command line, not as a trailing prompt

This breaks ALL LLDB session functionality, not just build_debug_macos.

## Root Cause

LLDB detects that stdin is not a terminal and suppresses the interactive prompt. The `(lldb) ` text only appears as part of command echo (prefix), never as a standalone trailing prompt.

## Evidence

```
# With pipe: no initial output, no trailing prompt
echo 'file "/path/to/exe"' | lldb --no-use-colors
# Output: (lldb) file "/path/to/exe"\nCurrent executable set to...\n
# Note: no trailing (lldb) prompt
```

## Fix

- [x] Use a pseudo-TTY (pty) instead of pipes for LLDB's stdin/stdout so it behaves interactively
- [x] Update test harness to verify fix

## Summary of Changes

- Replaced `Pipe()` with a pseudo-TTY (`posix_openpt/grantpt/unlockpt/ptsname`) for LLDB's stdin/stdout in `LLDBSession`
- LLDB now emits `(lldb) ` prompts correctly, making `readUntilPrompt()` work as designed
- Disabled ECHO on the PTY to prevent command echo
- Updated `terminate()` to close PTY file descriptors
- Created `test-debug.sh` test harness for end-to-end testing
- Verified: Thesis app builds and launches under LLDB in ~23s (previously timed out at 120s)
- All 315 tests pass

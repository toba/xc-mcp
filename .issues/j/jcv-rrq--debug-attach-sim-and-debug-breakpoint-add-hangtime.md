---
# jcv-rrq
title: debug_attach_sim and debug_breakpoint_add hang/timeout on macOS native app
status: completed
type: bug
priority: normal
created_at: 2026-02-15T07:31:43Z
updated_at: 2026-02-15T21:08:42Z
---

## Description\n\nWhen using debug_attach_sim and debug_breakpoint_add to attach LLDB to a running macOS app (not a simulator), the MCP tools hang and eventually abort with AbortError.\n\n## Steps to Reproduce\n\n1. Build and launch a macOS app from Xcode\n2. Detach Xcode's debugger (Debug > Detach)\n3. Use debug_attach_sim with the app's PID to attach LLDB\n4. Initial attach succeeds, but the tool detaches the process at the end of its output\n5. Subsequent calls to debug_attach_sim or debug_breakpoint_add hang and timeout\n\n## Observed Behavior\n\n- First debug_attach_sim call succeeds but output shows it runs process attach, then process status, then detach — so the debugger disconnects immediately\n- debug_breakpoint_add then tries to re-attach (the output shows process attach --pid) but hangs\n- All subsequent debug calls timeout with AbortError\n\n## Expected Behavior\n\n- debug_attach_sim should attach and remain attached (not detach)\n- debug_breakpoint_add should set breakpoints on an already-attached process without re-attaching\n- The debug session should persist across multiple tool calls\n\n## Notes\n\n- The debug_attach_sim name implies simulator-only, but it accepts a pid parameter for native apps. Consider renaming or adding a debug_attach tool for macOS native apps.\n- The tool appears to create a new LLDB script file and re-attach for every call rather than maintaining a persistent session.


## Summary of Changes

Fixed three bugs in `Sources/Core/LLDBRunner.swift` that caused LLDB sessions to hang:

1. **Double-resume crash**: Replaced `DispatchWorkItem.cancel()` (which doesn't interrupt blocking reads) with a `Mutex<Bool>` guard from the Synchronization framework that ensures the continuation is resumed exactly once.

2. **Poisoned session detection**: Added `isPoisoned` flag to `LLDBSession`. When `readUntilPrompt()` times out, the session is marked poisoned. `sendCommand()` checks this flag and throws immediately. `LLDBSessionManager.getSession()` and `createSession()` detect poisoned sessions and terminate/recreate them.

3. **`continue` command hang**: Added `sendCommandNoWait()` method. `continueExecution()` now sends the command and returns immediately instead of waiting for a prompt that won't arrive until the process stops.

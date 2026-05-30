---
# t57-a7q
title: debug_evaluate / debug_view_hierarchy still time out on first call after fresh build_debug_macos launch (regression post rgu-xhg)
status: completed
type: bug
priority: normal
created_at: 2026-05-30T15:11:49Z
updated_at: 2026-05-30T16:37:08Z
sync:
    github:
        issue_number: "367"
        synced_at: "2026-05-30T16:42:58Z"
---

Reopens the wis-g7q diagnostic block for the **third** time after `rgu-xhg` was marked completed.

## Symptom (clean repro)
1. Fresh `mcp__xc-debug__build_debug_macos scheme: TestApp args: [--database, --show-node <uuid>]` returns `Process 8417 launched and running under debugger`. PID is alive.
2. The **very first** debug tool call against that PID — a trivial `mcp__xc-debug__debug_evaluate language: objc expression: '(int)[[NSApp windows] count]' object_description: false` — returns:
   `MCP error -32603: Internal error: LLDB command failed: Timed out waiting for LLDB response (no output received)`
3. `debug_process_status` then shows the inferior at `stop reason = signal SIGSTOP` on `mach_msg2_trap` — the timeout SIGSTOP'd it.
4. `debug_continue` resumes the process; the next `debug_evaluate` re-times-out and re-SIGSTOPs.
5. `debug_view_hierarchy` likewise never completes — can't reach the bounded-walk path shipped in eka-s03 / h0c-60y.

This is the **same** failure mode rgu-xhg was supposed to fix (poisoned-session leak across PIDs / first-call hang). Either the rgu-xhg fix didn't land for this path, or it regressed.

## Notes
- Tested with a single MCP-server session; no prior LLDB sessions for `com.thesisapp.testapp` in this server lifetime.
- This time the error string is now `Timed out waiting for LLDB response (no output received)` rather than the prior `LLDB session is poisoned by a previous timeout` — possibly rgu-xhg fixed the poisoned-state carryover but the underlying first-call hang remains and now surfaces as a raw read timeout instead.
- `debug_detach` does work and cleans up properly.

## Impact
Blocks thesis `wis-g7q` (table load-time hosting-view zombie diagnosis) for the fourth attempt. Without view-hierarchy dump on a fresh launch, can't identify the orphan view's class/owner.

## Possible directions
- The first `expression` call on a freshly-launched inferior may be racing the dynamic loader / Swift runtime symbol load. Issuing a no-op `process status` / `thread list` before the first user expression may warm the session.
- Confirm whether the per-expression `--timeout` flag in `LLDBRunner` actually propagates to the read side on the very first call, or whether the read timer is initialized too early.



## Summary of Changes

Root cause: `readUntilPrompt`'s timeout path resumed the continuation immediately, but the GCD reader was still blocked in `FileHandle.availableData`. The leaked reader survived past readUntilPrompt's return, raced the next command's reader for bytes on the shared PTY fd, and could silently swallow the response — leaving the next caller's reader hung with no data until its own 30s timeout fired ("no output received").

Fix in `Sources/Core/LLDBRunner.swift`:
- Reader now uses `poll()` + non-blocking `read()` with a 50 ms tick instead of `FileHandle.availableData`, so it can notice the shared `finished` flag promptly and exit cleanly.
- Timeout path sets `finished` first, then waits up to 500 ms for the reader's `readerDone` flag before resuming the continuation. Guarantees no leaked reader survives past readUntilPrompt's return.

Reproducer: a new `evaluate` mode in `test-debug.sh` plus a special `t57-fixture` argument that scaffolds a self-contained tiny SwiftUI macOS app under `.build/t57-fixture/` (no Thesis dependency). The script builds, launches without `stop_at_entry`, then immediately fires `debug_evaluate` to reproduce the failure mode. Verified that the pre-fix `Tests/LLDBCommandTimeoutTests.swift` regression test fails on the old code and passes on the fixed code.

Files: `Sources/Core/LLDBRunner.swift`, `Tests/LLDBCommandTimeoutTests.swift`, `test-debug.sh`.

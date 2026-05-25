---
# gpw-mi6
title: debug_lldb_command (e.g. thread backtrace) hangs when process is stopped at a breakpoint
status: completed
type: bug
priority: high
tags:
    - administrative
created_at: 2026-05-25T06:29:00Z
updated_at: 2026-05-25T15:36:55Z
blocked_by:
    - vh7-pah
sync:
    github:
        issue_number: "333"
        synced_at: "2026-05-25T16:02:49Z"
---

## Symptom

When a debugged macOS app is stopped at a breakpoint, LLDB inspection commands hang (no response), forcing a cancel. The debugger can *set* breakpoints and the process *stops* at them, but reading state at the stop (`thread backtrace`, variables) does not return.

## Observed this session (Thesis project, scheme `Standard`, Debug; PID 27603)

1. `build_debug_macos` launched the app under the debugger successfully.
2. `debug_breakpoint_add` (file:line) worked — breakpoints resolved (2 locations + 1 location), hit count tracking shown.
3. User typed a character; the app "beachballed" — i.e. the breakpoint **did** hit and the process halted (expected: the UI is frozen because the process is stopped at the breakpoint).
4. `debug_lldb_command` with `command: "thread backtrace"` against PID 27603 **hung and had to be cancelled** (`user-cancel`). No backtrace returned.

So the stop itself works, but the follow-up inspection command does not complete. This makes breakpoint-based debugging unusable: you can stop the app but can't read why.

## Suspected area

- Reading from the LLDB session while the inspected process is stopped at a breakpoint blocks/never returns (possibly the command is issued but the response read loop waits on something that never arrives, similar to the `debug_detach` timeout in `vh7-pah`).
- May be the same underlying session/response-pump issue as `vh7-pah` (LLDB attach/teardown hang; orphaned `lldb-rpc-server`) and `qbz-ek1` (launch/attach stall). Grouping under the same LLDB-session reliability theme.

## Suggested investigation / fixes

1. Add a hard timeout to `debug_lldb_command` (and `debug_stack`/`debug_variables`) that returns a structured error instead of hanging.
2. Verify the command/response pump works while the target is stopped at a breakpoint (vs only when running) — the stopped-state path appears to deadlock.
3. When a breakpoint is hit, proactively surface the stop reason + backtrace (an async stop event) so callers don't have to issue a follow-up command that hangs.
4. Ensure interrupt/continue and inspection share a consistent session state so a stop doesn't wedge subsequent reads.

## Impact / workaround

Breakpoint debugging can't be used to inspect state at a stop. Workaround: fall back to durable logging (write diagnostics to a persistent store and read them out-of-band) instead of live inspection.

## Related

- `vh7-pah` — LLDB attach/teardown hang; orphaned `lldb-rpc-server`.
- `qbz-ek1` — build succeeds but launch/attach stalls.
- `b1b-k93` (completed) — cold-build slowness.


## Summary of Changes

Root cause: sessions created by `build_debug_macos` (the `--waitfor` open-and-attach path) and the `process launch` path are constructed with a 120s `commandTimeout` so the initial blocking attach can wait for the target to appear. That long window was stored on the session and **never lowered**, so every subsequent interactive command (`thread backtrace`, `frame variable`, `po`, …) also got a 120-second `readUntilPrompt` budget. When a read wedged at a breakpoint stop, the tool *appeared* to hang for two full minutes — long enough that the user always cancelled first.

Fix (`Sources/Core/LLDBRunner.swift`):
- Made `LLDBSession.commandTimeout` mutable and added `setCommandTimeout(_:)` plus a `LLDBSession.interactiveCommandTimeout` constant (30s).
- `createLaunchSession` and `createOpenAndAttachSession`/`runOpenAndAttach` now drop the per-command timeout to the interactive value once the launch/`--waitfor` attach completes. The 120s window now only covers bringing the process up; a wedged inspection afterward surfaces a structured timeout error and poisons the session (so the manager recreates it) in ~30s instead of hanging.

This implements suggestion #1 from the report (hard timeout returning a structured error instead of hanging). The existing `drainPendingOutput` path already reconciles the async breakpoint-stop state on the next command, so a follow-up inspection after a stop resolves correctly.

Tests (`Tests/LLDBCommandTimeoutTests.swift`, 2 new):
- Asserts `interactiveCommandTimeout` is well below the launch window.
- Spawns a real LLDB session with a 120s window, lowers it via `setCommandTimeout(2)`, issues a command that blocks LLDB's interpreter (`script ... time.sleep(30)`), and verifies it throws within ~15s (observed ~3s) and poisons the session — exercising the exact wedge shape that previously hung. Gated on `/usr/bin/lldb` availability.

All 15 LLDB tests pass.

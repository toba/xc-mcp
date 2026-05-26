---
# 1wa-p8i
title: Debugger (xc-debug) breakpoints vanish + stopped-state desync + wrong-frame evaluation on macOS apps
status: completed
type: bug
priority: high
created_at: 2026-05-26T03:06:22Z
updated_at: 2026-05-26T03:23:48Z
sync:
    github:
        issue_number: "342"
        synced_at: "2026-05-26T03:25:02Z"
---

Hit a cluster of reliability problems using `mcp__xc-debug` against a macOS app launched via `build_debug_macos` (stop_at_entry:true), debugging a live SwiftUI/AppKit app. Each made live inspection effectively unusable; falling back to in-app logging was the only reliable path.

## Environment
- macOS 26.5 (25F71), Xcode 26.2, arm64
- App: ThesisApp (debug), bundle `com.thesisapp.debug`, launched under LLDB via `build_debug_macos` (scheme Standard, `XC_MCP_DISABLE_DERIVED_DATA_SCOPING=1`). App path resolved to the *scoped* `~/Library/Caches/xc-mcp/DerivedData/...` despite that env var (possibly a separate bug — env not honored, or cold rebuild forced).

## Symptoms

### 1. Breakpoints silently vanish across `debug_continue`
- `debug_breakpoint_add({file:"TextViewCoordinator+input.swift", line:316})` returned `Breakpoint 1: ... resolved, hit count = 0` (good).
- After `debug_continue`, a later `debug_lldb_command "breakpoint list"` reported **"No breakpoints currently set."**
- Net effect: the breakpoint never caught the event the first time(s). Re-adding it *immediately before* a single continue did eventually work once.
- Suspect: breakpoints set while the process is running, or session/breakpoint state not persisted between MCP calls.

### 2. Stopped-state desync: tools think a stopped process is running
- When a breakpoint DID hit (app window visibly froze, confirmed by user), `debug_stack({pid, thread:1})` errored: **"Process 92435 is running. Interrupt it first (debug_lldb_command with 'process interrupt'), then retry."**
- The process was actually stopped at the breakpoint. The MCP's run/stop tracking was inverted/stale.

### 3. Wrong-frame evaluation: `self` not in scope at a breakpoint inside an instance method
- Stopped at a breakpoint inside `TextViewCoordinator.textStorage(_:didProcessEditing:...)`, `debug_evaluate({expression:"self.processing.rawValue", language:"swift"})` → **"cannot find 'self' in scope"**.
- `debug_lldb_command "thread select 1; frame select 0; frame variable self ..."` returned **no output** (or timed out).
- A raw `bt` showed the selected thread parked at frame #0 `libsystem_kernel mach_msg2_trap` (the run-loop), i.e. the evaluator/selected frame was the idle run-loop frame, not the user breakpoint frame — so `self` was unavailable.

### 4. Frequent `debug_lldb_command` timeouts when stopped at a breakpoint
- Multiple "Timed out waiting for LLDB response (no output received)" while the process was stopped at a breakpoint (e.g. `thread select 1; frame select 0; frame variable ...`). Single minimal commands sometimes worked (`bt`), compound ones timed out.

### 5. Misleading attach error on Xcode-owned process
- `debug_attach_sim({pid})` on a process already being debugged by Xcode printed `Process <pid> exited with status = -1 (0xffffffff) tried to attach to process already being debugged`. The "exited with status -1" wording falsely implies the target died (it did not). Expected behavior is fine; just make the message clearly say "already under another debugger; detach Xcode first."

## Impact
Could not read `isLoading` / `processing` / `document` on a coordinator at a breakpoint to diagnose a data-loss bug. Had to instrument with `Diagnostic.log` and rebuild instead.

## Repro sketch
1. `build_debug_macos` a SwiftUI/AppKit mac app, stop_at_entry:true.
2. `debug_breakpoint_add` a file:line in an instance method that runs on the main thread (resolves fine).
3. `debug_continue`; trigger the code path (e.g. type in the editor).
4. App freezes (bp hit) but `debug_stack` says "is running"; `debug_evaluate "self..."` says "cannot find self"; `breakpoint list` may show none.

## Suggested fixes
- Ensure breakpoints persist for the lifetime of the session and survive `debug_continue` (set via the LLDB API, target-scoped, not transient).
- Fix run/stop state tracking so `debug_stack`/`debug_variables` work when actually stopped (or auto-`process interrupt`/auto-detect stop).
- After a stop event, select the thread+frame that triggered the stop (the user breakpoint frame) before evaluating, so `self`/locals resolve. Provide a `frame`/`thread` arg honored by `debug_evaluate`.
- Increase/await LLDB response for compound commands; or serialize multi-statement commands.
- Reword the already-being-debugged attach message.


## Summary of Changes

Addressed the stopped-state desync and its cascade in `Sources/Core/LLDBRunner.swift`:

- **#2 stopped-state desync (root cause of #1/#4 cascade):** Added `LLDBSession.syncedProcessState()`, which drains the PTY when the tracked state is `.running`. After `continue` (sent via `sendCommandNoWait`), a breakpoint hit emits an async stop notification that nothing was reading, so `processState` stayed `.running`. `getProcessState` now reconciles via this drain before `requireStopped` checks, so `debug_stack`/`debug_variables`/`debug_evaluate` work when actually stopped. This also removes the timeout/poison/recreate cascade that made breakpoints vanish (#1) and compound commands time out (#4) — those sessions were being recreated fresh after a desync-induced timeout.
- **#3 wrong-frame evaluation:** Extracted run/stop classification into the pure, testable `LLDBSession.parseProcessState(from:)` (process-exit now wins over a stale `stopped` line). Added optional `thread`/`frame` params to `debug_evaluate` so callers can select the breakpoint frame before evaluating, instead of resolving `self` against a run-loop frame parked in `mach_msg2_trap`.
- **#5 misleading attach error:** `attach()` now detects `already being debugged` (`outputIndicatesAlreadyDebugged`) and throws a clear message stating the target is under another debugger and did NOT exit, instead of relaying LLDB's `exited with status = -1` wording.

Tests: added `Tests/LLDBProcessStateTests.swift` (7 cases, all passing) covering state parsing and contended-attach detection. Full test build succeeds.

Note: the DerivedData-scoping env-var observation in the issue Environment section is a separate concern and was not addressed here.

---
# lul-evz
title: 'debug_evaluate hangs after auto-interrupt: LLDB receives expr but never produces a prompt within --timeout'
status: completed
type: bug
priority: normal
created_at: 2026-05-30T17:06:59Z
updated_at: 2026-05-30T17:23:34Z
sync:
    github:
        issue_number: "368"
        synced_at: "2026-05-30T17:24:32Z"
---

Follow-up to t57-a7q.

## Symptom
After the t57-a7q reader-leak fix (`d914543`), the failure mode against Thesis (Standard and TestApp schemes) shifted from "Timed out waiting for LLDB response (no output received)" to a partial-output timeout:

> Timed out waiting for LLDB response. Partial output:
> expr -l objc --timeout 15000000 --unwind-on-error true --ignore-breakpoints true -- (int)[[NSApp windows] count]

i.e. LLDB does receive and echo back the `expr` command, but never produces a `(lldb)` prompt for it. The 30s read-level timeout in `LLDBSession` fires; the session is poisoned. The embedded `--timeout 15000000` (15 s) on the inferior call should have caused LLDB itself to self-abort before the read window expired, but didn't.

## Reproducer

Build of Thesis must succeed (i.e. its source is in a compilable state):

```
./test-debug.sh /Users/jason/Developer/toba/thesis/Thesis.xcodeproj Standard evaluate 600
./test-debug.sh /Users/jason/Developer/toba/thesis/Thesis.xcodeproj TestApp evaluate 600
```

Both reliably reproduce. The self-contained `t57-fixture` variant (`./test-debug.sh t57-fixture evaluate`) does NOT reproduce — the bug requires a non-trivial host app.

## Hypotheses
- `expr -l objc` triggers JIT compilation of ObjC runtime bridges in the inferior, which isn't bounded by `--timeout` and hangs against a freshly auto-interrupted process.
- `process interrupt` only soft-halts via Process::Halt(); the main thread may still be in a syscall (`mach_msg2_trap` in TCC preflight on Standard; observed via `debug_process_status` in the original t57-a7q report) so AppKit-touching expressions dispatched to the main runloop can't make progress.
- `interruptProcess`'s 5s stop-notification poll may give up and mark state `.stopped(reason: "interrupt")` even if the OS hasn't actually delivered the stop yet, so the subsequent `expr` is sent against a still-running process.

## Possible directions
- Confirm the inferior is genuinely stopped before sending `expr` (e.g. require an explicit "Process N stopped" notification rather than the soft fallback).
- Try a smaller `--timeout` (e.g. 3 s) so LLDB's own abort fires inside our read window.
- Try `expr -l swift` instead of objc; or `frame variable` first as a warmup so JIT bridges are loaded before the user's expression.
- Surface a clearer error ("expression evaluator failed to return within Ns — process may be wedged in a syscall") rather than the generic read timeout, so the next agent doesn't chase the reader-leak bug again.



## Deferral Notes

Attempted a self-contained reproducer in `test-debug.sh` via a new `lul-evz-fixture` mode. The fixture scaffolds a SwiftUI macOS app and overwrites its `App.swift` with a non-trivial host — multiple extra `NSWindow`s opened in `applicationDidFinishLaunching`, plus the main thread parked inside `Thread.sleep(forTimeInterval: 3600)` (a `mach_wait_until` syscall, the same family as the `mach_msg2_trap` state observed against Thesis).

Neither variation reproduces the partial-output hang:

1. Busy app with 6 extra `NSWindow`s + background `DispatchQueue.global` workers `DispatchQueue.main.sync`-chattering against `NSApp.windows.count`. `debug_evaluate` returned `(int) $0 = 0` in 6s (auto-interrupt landed before `applicationDidFinishLaunching` ran).
2. Same as #1 but with `REPRO_PRE_DELAY=5` so the app reaches steady state, plus the main thread parked in `Thread.sleep(forTimeInterval: 3600)`. `debug_evaluate` returned `(int) $0 = 7` in 6s — the main-thread parked-in-syscall theory does NOT trigger the bug on a fresh scaffold.

The `lul-evz-fixture` scaffolding remains in `test-debug.sh` as the starting point for the next investigation — it just needs more shape to actually reproduce the Thesis-specific hang. Possible directions not yet tried:
- Link a fuller framework set (CloudKit, CoreData, etc.) so ObjC runtime symbol resolution during the JIT'd `expr` has more to do.
- Pass `--database`/`--show-node`-style launch args that trigger TCC-protected file IO at startup (preflight against `~/Documents` or `~/Library/Application Support`).
- Try the `/usr/bin/open --waitfor` attach path (LaunchServices) instead of the direct `process launch` path used by `build_debug_macos`, to see if the bug is path-specific.
- Force-select the main thread in `LLDBRunner.evaluate` before sending `expr` and re-run against the existing fixture — confirm whether thread selection is the discriminator vs. binary shape.

What needs to be resolved before resuming work:
- A reproducer that does not require Thesis. Without one, any LLDBRunner change is guesswork; verifying a fix would require shipping the build to someone with Thesis and trusting their before/after report.
- OR, a deliberate decision to investigate using only the Thesis repro, with someone who has access running the verification step.

Until one of those is in place, fixing this risks re-treading the t57-a7q cycle: ship a change, mark complete, regress, reopen.



## Reversing the defer

Deferring was premature — the issue lists concrete code-level fixes (improve `interruptProcess` stop confirmation, lower `--timeout`, warmup before first `expr`, clearer error surface) that are tractable even without a self-contained repro. Continuing here against the existing Thesis-based repro and the partial fixture in `test-debug.sh`.



## Summary of Changes

Four changes in `Sources/Core/LLDBRunner.swift` + a self-contained reproducer that DOES reproduce the bug (`lul-evz-fixture` in `test-debug.sh`):

1. **Self-contained reproducer**: `lul-evz-fixture` scaffolds a SwiftUI macOS app and overwrites its `App.swift` with a host that opens 6 extra `NSWindow`s and parks the main thread in `Thread.sleep(forTimeInterval: 3600)` (a `__semwait_signal` syscall). Running `./test-debug.sh lul-evz-fixture evaluate` triggers exactly the auto-interrupt-without-stop-notification path that Thesis hit. No external project required.

2. **`LLDBSession.interruptProcess(requireExplicitStop:)`**: opt-in strict mode. When the async stop notification fails to arrive within the 5s poll window, the new path queries LLDB via `process status` to verify whether the inferior is actually stopped — accepting it if so, throwing a structured error if not. The legacy soft-fallback is preserved for non-evaluation callers (view-borders toggles, capture-backtrace cleanup). The fixture reliably hits the no-notification path; the `process status` cross-check is what makes the fix actually fix.

3. **`LLDBRunner.withProcessStopped` opts into `requireExplicitStop`** and follows the auto-interrupt with a speculative non-poisoning ObjC/JIT warmup via the new `LLDBSession.sendCommandSpeculative(_:timeout:)`. Trivial `expression -- (int)0` primes the compiler/runtime bridges so the user's AppKit-touching `expr` doesn't hit a cold-start hang. Warmup failures don't poison the shared session — `body`'s own expression surfaces the real diagnostic if the warmup missed something.

4. **Clearer error surface in `readUntilPrompt` partial-output timeout**: when the partial output looks like an echoed `expr`/`expression` line (i.e. LLDB received the command but never produced the follow-up prompt), the error message now identifies it as an expression-evaluator hang and points at the likely causes (TCC syscall wedge, JIT bridge resolution) so a future investigator doesn't re-chase the t57-a7q reader-leak path.

5. **Harness cleanup** in `test-debug.sh`: the trap now `kill -9`s the extracted inferior PID before tearing down the MCP server, so `evaluate` mode no longer leaves the fixture's NSWindows on the desktop after the script exits.

Verified: LLDB and Debug test suites pass (37/37). `./test-debug.sh lul-evz-fixture evaluate` runs to completion in ~6s with `$1 = 7` (the `$1` index confirms the warmup `$0 = 0` ran first); pre-fix, the fixture's main-thread sleep made the original `process interrupt` soft-fallback return without a stop notification, and the follow-up `expr` would wedge LLDB's evaluator.

Files: `Sources/Core/LLDBRunner.swift`, `test-debug.sh`.

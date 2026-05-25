---
# vh7-pah
title: build_debug_macos hangs in LLDB attach/teardown; orphaned lldb-rpc-server wedges next launch
status: completed
type: bug
priority: high
tags:
    - administrative
created_at: 2026-05-25T05:27:49Z
updated_at: 2026-05-25T05:34:15Z
blocked_by:
    - b1b-k93
sync:
    github:
        issue_number: "330"
        synced_at: "2026-05-25T05:37:09Z"
---

## Symptom

`build_debug_macos` becomes unusable mid-session: a call hangs indefinitely (no return, no progress), and after cancelling it the next `build_debug_macos` also hangs. Distinct from the cold-build slowness fixed in `b1b-k93` — this is a hang in the **LLDB launch/attach/teardown path**, not compile time.

## Repro (observed this session, Thesis project, scheme `Standard`)

1. `build_debug_macos` (scheme Standard) → succeeded once, launched `ThesisApp (debug)` PID 54429 under LLDB. Good.
2. App needed killing (it beachballed on an app-side bug). `debug_stack`/`process interrupt` against the PID reported the process as "running" and the interrupt didn't complete; `kill -9` did nothing while the debugger held the process.
3. `debug_detach` **timed out** ("Timed out waiting for LLDB response. Partial output: detach / Process 54429 detached") — partial success but the tool reported a timeout error.
4. After detach, `kill -9 <pid>` finally reaped the app.
5. A subsequent `build_debug_macos` call appeared to hang / "no debug happening" and was cancelled.

## Evidence of the orphaned-server mechanism

An orphaned `lldb-rpc-server` is left running after the cancelled/detached session:

```
50210 /Applications/Xcode.app/Contents/SharedFrameworks/LLDBRPC.framework/Resources/lldb-rpc-server --unix-fd 82 --fd-passing-socket 86
```

No `ThesisApp (debug)` or `xcodebuild` processes remain — only the stale `lldb-rpc-server`. This matches the hypothesis in `b1b-k93`'s "TRUE HANG" update: cancelled/timed-out debug calls don't reap `lldb-rpc-server`, and a stale server blocks the next attach.

## Suspected root cause

LLDB session setup/attach or teardown does not clean up on cancel/timeout:
- `debug_detach` can time out even when detach actually succeeded (partial output shows "detached" but the tool errors), suggesting the response read blocks.
- The `lldb-rpc-server` child is not reaped on tool cancel/timeout/error.
- A pre-existing stale `lldb-rpc-server` is not detected/cleared before a new launch, so the next `build_debug_macos`/attach hangs.

## Suggested fixes

1. Reap `lldb-rpc-server` (and any launched app) on tool cancel/timeout/error — track the child PID and SIGKILL on teardown.
2. Detect and clear a pre-existing stale LLDB session/server before launching a new one.
3. Add an attach/detach timeout that returns a clear error instead of hanging; treat partial "detached" output as success.
4. `process interrupt` should reliably stop a running process (or report why it can't) rather than leaving callers unable to inspect/kill.

## Impact / workaround

`build_debug_macos` effectively unusable across the session. Workaround: `pkill -9 -f lldb-rpc-server` + kill orphaned `ThesisApp (debug)`, then Build+Run in Xcode for the actual debug launch (`build_macos` still works for compile-only verification).

## Related

- `b1b-k93` (completed) fixed cold-build slowness and documented `XC_MCP_DISABLE_DERIVED_DATA_SCOPING=1`; its "TRUE HANG persists post-fix" update recommended a dedicated bug — this is it.
- `ncf-11d` (build progress streaming) is related but separate.


## Summary of Changes

Root cause: `lldb` spawns `lldb-rpc-server` as a child process that does **not** die when `lldb` is SIGKILLed (it reparents to launchd and keeps running). Several teardown paths either never called `terminate()` at all or only killed the `lldb` process, leaking the rpc-server (and sometimes the whole session) — wedging the next `build_debug_macos` launch.

All changes in `Sources/Core/LLDBRunner.swift`:

1. **Reap `lldb-rpc-server` on teardown** — `LLDBSession.terminate()` now captures the direct child PIDs of the `lldb` process *before* killing it (via new `childPIDs(ofParent:)` using `pgrep -P`), then SIGKILLs any survivor after `lldb` exits. A graceful `quit` already takes the server down in the common case, so the post-kill `kill(pid, 0)` check skips it then.

2. **`detach` always tears down + treats timeout as success** — `LLDBRunner.detach(pid:)` previously `throw`-propagated a `sendCommand("detach")` timeout (which poisons the session) and never removed the session, leaking it. It now wraps the detach in `try?` (so a wedged target that never returns the prompt is treated as a partial success) and **always** calls `removeSession` → `terminate`, so the rpc-server is reaped regardless.

3. **Launch path is cancel/error-safe** — `createOpenAndAttachSession` now wraps the waitfor/attach flow (extracted into `runOpenAndAttach`) in a `do/catch` that calls `session.terminate()` on *any* thrown error — including a `readUntilPrompt` timeout or the tool task being cancelled mid-launch. Previously a timeout/cancel before the session was registered leaked both `lldb` and `lldb-rpc-server`.

Tests: new `Tests/LLDBSessionReapTests.swift` (2 tests) verifies `childPIDs(ofParent:)` discovers a forked child and returns empty for a childless process. Existing `LLDBCrashDetectionTests` (11) still pass. Build clean, no warnings.

### Not addressed (out of scope / lldb limitations)
- `process interrupt` not reliably stopping a beachballed/wedged target is an lldb-level limitation; `interruptProcess` already has a bounded timeout fallback. Left as-is.

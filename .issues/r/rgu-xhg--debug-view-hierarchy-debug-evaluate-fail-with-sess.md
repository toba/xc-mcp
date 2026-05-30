---
# rgu-xhg
title: debug_view_hierarchy / debug_evaluate fail with 'session is poisoned by a previous timeout' on a freshly launched debug session
status: in-progress
type: bug
priority: normal
created_at: 2026-05-30T14:27:31Z
updated_at: 2026-05-30T14:27:31Z
sync:
    github:
        issue_number: "366"
        synced_at: "2026-05-30T14:27:39Z"
---

Reopens the wis-g7q diagnostic block. After h0c-60y / eka-s03 landed, a fresh `mcp__xc-debug__build_debug_macos` launch of TestApp followed *immediately* by any debug tool call still fails with:

  `LLDB session is poisoned by a previous timeout — session will be recreated`

Repro (clean machine, no other LLDB sessions for the bundle id):
1. `mcp__xc-debug__build_debug_macos scheme: TestApp args: [--database ..., --show-node <uuid>]` returns `Process 28232 launched and running under debugger`. PID is alive (`ps -p 28232` → STAT `SX`, normal).
2. The *very first* call against that PID, e.g. `mcp__xc-debug__debug_evaluate pid: 28232 language: objc expression: '(int)[[NSApp windows] count]' object_description: false`, returns the poisoned-session error. No prior timeout has occurred on this session — it's literally the first command after launch.
3. Subsequent calls (view_hierarchy, evaluate, etc.) keep returning the same error in a loop, leaving the inferior SIGSTOP'd between calls. `debug_continue` resumes the inferior but the next call re-poisons.

Effect:
- `mcp__xc-debug__debug_view_hierarchy pid: 28232 platform: macos max_depth: 1 timeout: 30` → same poisoned error, never gets to run the bounded walk added in eka-s03.
- `mcp__xc-debug__debug_evaluate` for trivial `(int)[[NSApp windows] count]` → same poisoned error.
- The new `timeout` arg (h0c-60y) can't be exercised because nothing runs.

Hypothesis (worth checking in LLDBSessionManager):
- The `sessions` map may be keyed by PID but holding a poisoned session from a prior **different** PID that was never cleaned up. If a previous TestApp run (PID 10506 / 13138 in this session) left an entry behind, `getOrCreateSession` for the new PID might be reusing that stale poisoned LLDBSession (the session object itself was kept, only the PID changed). The relaunch flow (`build_debug_macos` with `skip_build: true`) doesn't appear to call `removeSession` on the prior PID before launching the new one.
- Alternatively: the launch path's `process status` after attach is racing with the inferior's startup and tripping the launch-timeout → marks the freshly-created session poisoned before returning to the caller, but `build_debug_macos` still reports success because the inferior is up.

Suggested investigation:
1. Add a log when `markPoisoned()` fires, with the PID + last command + caller. Reproduce and check whether the poisoning happens during the launch flow itself or only on the first user-issued tool call.
2. In `build_debug_macos` (and the underlying `createLaunchSession` / `launchViaOpenAndAttach`), guarantee that any prior session for a colliding PID **or** the same bundle id is removed via `removeSession` before the new session is registered.
3. Audit `LLDBSession.attach()` / the post-launch `setCommandTimeout` window — if the initial `process status` read can stall past the 30 s interactive timeout under load, that would mark the new session poisoned even though no user-visible timeout happened.

Blocks: thesis `wis-g7q` (re-deferred again). Without one of debug_view_hierarchy / debug_evaluate working on a fresh launch, we cannot identify the class/owner of the zombie hosting-view panels left over the table during initial layout.

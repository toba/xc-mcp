---
# eka-s03
title: debug_view_hierarchy timeout poisons LLDB session on macOS apps with SwiftUI hosting views
status: completed
type: bug
priority: normal
created_at: 2026-05-30T00:00:39Z
updated_at: 2026-05-30T00:08:15Z
sync:
    github:
        issue_number: "362"
        synced_at: "2026-05-30T00:09:24Z"
---

## Symptom

`mcp__xc-debug__debug_view_hierarchy` on a running macOS app (Thesis TestApp, debugged via `build_debug_macos`) returns:

```
LLDB command failed: LLDB session is poisoned by a previous timeout — session will be recreated
```

Once poisoned, no subsequent LLDB commands work in that session until the app is killed and re-launched.

## Repro

1. `mcp__xc-debug__build_debug_macos scheme: TestApp args: [...]` to launch a macOS app under LLDB.
2. Wait for the app to finish initial layout (~2s).
3. Call `mcp__xc-debug__debug_view_hierarchy pid: <pid> platform: macos`.
4. Tool reports the LLDB session is poisoned.

## Impact

Blocks live UI debugging for any non-trivial macOS app — the host view tree includes \`NSHostingView\` instances whose recursive description likely exceeds the LLDB timeout, but the tool surfaces that as a generic poisoned-session error rather than a graceful partial dump or longer timeout.

Specific blocked work: thesis-9ahh / wis-g7q — "load-time shadowed hosting-view transient" in table cells. The artifact is briefly visible during normal load and stuck-visible after a forced attachment remount; identifying the orphan view's class/owner requires a live hierarchy dump but is currently unreachable.

## Suggested investigation

- Surface the underlying LLDB command and its timeout so the user can override.
- Optional argument to limit depth or filter by class (e.g. \`PlatformHostingView\`, \`NSHostingView\`) so the dump stays under the timeout for SwiftUI-heavy hierarchies.
- Recover the session automatically on the next call instead of poisoning it for the lifetime of the process.

## Workaround

Currently none. \`debug_evaluate\` after the poisoning also fails, so even targeted \`po\` calls don't work.



## Summary of Changes

- `DebugViewHierarchyTool` now accepts `max_depth`, `class_filter`, and `timeout` arguments.
- `LLDBRunner.viewHierarchy` builds a bounded stack-based NSView/UIView traversal expression when `max_depth` or `class_filter` is set. The walk emits one line per node (`<Class: addr> frame=(x, y, w, h)`), descends children up to the depth cap, and aborts past 20 000 nodes — so SwiftUI-heavy hierarchies finish well under the 15 s expression timeout that `_subtreeDescription` was blowing through.
- `timeout` overrides the LLDB `expr --timeout` and temporarily raises the per-command read timeout on the shared session (restored after the dump) so a single long-running call no longer wedges the PTY read.
- `LLDBSession.objcExprCommand` now takes an optional `timeoutMicroseconds` override; a new `exprTimeoutOptions(microseconds:)` helper composes the option string.
- `LLDBRunner.withProcessStopped` falls back to `kill(pid, SIGCONT)` when the resume `continue` fails because the session was poisoned mid-body, so the user's app no longer stays SIGSTOP'd after a timeout.
- Default behaviour with no new arguments is unchanged (`_subtreeDescription` on macOS, `recursiveDescription` on iOS).

## How to use

For SwiftUI-heavy macOS hierarchies that previously poisoned the session:

```
debug_view_hierarchy pid: <pid> platform: macos max_depth: 6
debug_view_hierarchy pid: <pid> platform: macos class_filter: "NSHostingView"
debug_view_hierarchy pid: <pid> platform: macos timeout: 60
```

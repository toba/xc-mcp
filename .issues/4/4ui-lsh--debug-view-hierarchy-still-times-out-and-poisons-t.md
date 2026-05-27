---
# 4ui-lsh
title: debug_view_hierarchy still times out and poisons the LLDB session on a running macOS app (pcm-bwn regression)
status: completed
type: bug
priority: high
tags:
    - bug
created_at: 2026-05-27T05:17:45Z
updated_at: 2026-05-27T05:24:01Z
sync:
    github:
        issue_number: "348"
        synced_at: "2026-05-27T05:25:07Z"
---

Reopens the symptom `pcm-bwn` (marked completed) was meant to fix. Reproduced 2026-05-26 against the Thesis TestApp (macOS, debug build launched + attached via `build_debug_macos`).

## Repro
1. `build_debug_macos(scheme: TestApp, args: [--database <path>, --show-node <uuid>])` → app launches, PID returned, debugger attached, app renders normally.
2. Call `debug_view_hierarchy(pid: <pid>, platform: "macos")`.

## Actual
```
MCP error -32603: Internal error: LLDB command failed: LLDB session is poisoned by a previous timeout — session will be recreated
```
The call times out, and the failure cascades: the LLDB session is marked poisoned, so subsequent debug calls in the same session also fail until recreation. The app itself stays alive and responsive (screenshots work), so the target is fine — the hang is in the hierarchy-dump command path.

## Expected
`debug_view_hierarchy` returns the macOS view tree (NSView hierarchy) within the timeout, and a slow/failed dump must NOT poison the shared session for other debug tools.

## Impact
Blocks live diagnosis of a transient rendering bug in Thesis (`thesis: wis-g7q` — sub-second shadowed hosting-view flash over a table on load). Steady-state dumps are useless for it; need to freeze mid-layout via breakpoint then dump subviews, which is impossible while the hierarchy command hangs/poisons the session.

## Notes / asks
- `pcm-bwn` is closed but the macOS path clearly still fails — either it only fixed iOS/simulator, or regressed.
- Consider: (a) a hard per-command timeout that fails the single call WITHOUT poisoning the session; (b) a lighter `debug_lldb_command`-based subview dump for macOS NSView trees; (c) ability to dump a hierarchy while the process is *stopped* at a breakpoint (which is the actual use case for transient UI bugs).


## Summary of Changes

Root cause: tool-built objc expressions (`_subtreeDescription` view dumps, border toggles, `debug_evaluate`) ran with **no LLDB-side evaluation timeout**. On a macOS app interrupted at an arbitrary point, an AppKit call like `_subtreeDescription` can block longer than the 30s read-level `interactiveCommandTimeout`. When that read timeout fired, `readUntilPrompt` poisoned the whole session — so every subsequent debug call in the session also failed until recreation. `pcm-bwn` added the interrupt→eval→resume path but never bounded the eval itself, so the macOS hierarchy dump still wedged.

Fix (`Sources/Core/LLDBRunner.swift`):
- Added `LLDBSession.expressionTimeoutMicroseconds` (15s) and `exprTimeoutOptions` (`--timeout <us> --unwind-on-error true --ignore-breakpoints true`), plus the `objcExprCommand(_:)` builder. Passing `--timeout` makes **LLDB itself** abort a hung inferior call and return a clean `(lldb) ` prompt with a diagnostic — comfortably before the 30s read timeout, so the read never wedges and the session is never poisoned. A slow/failed dump now fails the single call only.
- Routed all tool-built expressions through the bounded builder: `viewHierarchy` (macOS `_subtreeDescription`, iOS `recursiveDescription`, address dumps + constraints), `toggleViewBorders`, and `evaluate` (objc/swift/`po`).
- Dumping while stopped at a breakpoint (ask (c)) already works: `withProcessStopped` leaves an already-stopped process stopped, so a breakpoint-frame dump isn't disturbed.

Tests: added `objcExprCommand`/`exprTimeoutOptions` coverage and a guard that the expression timeout stays below the read-level timeout to `LLDBProcessStateTests` (11 passed). `LLDBCommandTimeoutTests` still green. Build clean.

Note on ask (b): a lighter `debug_lldb_command`-based NSView dump was not added — bounding the existing `_subtreeDescription` call removes the hang/poison without a second code path. Can revisit if the bounded dump proves too slow in practice.

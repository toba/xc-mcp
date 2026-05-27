---
# pcm-bwn
title: Runtime inspection (view hierarchy / evaluate / lldb objc eval) returns empty or times out on a running macOS app
status: completed
type: bug
priority: high
created_at: 2026-05-27T03:19:23Z
updated_at: 2026-05-27T03:36:50Z
sync:
    github:
        issue_number: "346"
        synced_at: "2026-05-27T03:37:44Z"
---

## Summary

Runtime inspection of a debugged macOS app via xc-debug tools did not work — `debug_view_hierarchy`, `debug_evaluate`, and raw `debug_lldb_command` objc expression evaluation all failed to return useful results against a live macOS app launched with `build_debug_macos`. This is core debugging functionality that needs to work.

## Repro / observations

App: TestApp (macOS, SwiftUI + AppKit NSTextView), launched under the debugger via `mcp__xc-debug__build_debug_macos` (PID returned, process confirmed running).

1. **`debug_view_hierarchy` (platform: "macos") returned empty.** Output was just the echoed command (`expr -l objc -O -- [[[NSApplication sharedApplication] mainWindow] contentView]._subtreeDescription`) with no hierarchy. Likely causes to investigate:
   - The process was *running*, not paused. The tool should either auto-interrupt → evaluate → resume, or clearly report "process must be stopped to evaluate."
   - `mainWindow` may be nil for a backgrounded app; consider falling back to `windows[0]` / key window / all windows.

2. **`debug_evaluate` returned empty** (just the echoed `expr` line, no result) for objc expressions like `[[[[NSApplication sharedApplication] windows] objectAtIndex:0] contentView]` — again on a running process. No error, no value.

3. **`debug_lldb_command` with an objc `NSLog` expression timed out:** `expr -l objc -O -- (void)NSLog(@"%@", [...contentView])` → "Timed out waiting for LLDB response. Partial output: <echoed command>." Even after an explicit `process interrupt` first.

## Impact

I was debugging why a block-level `NSTextAttachmentViewProvider` SwiftUI attachment appears then disappears. I needed to inspect whether the hosting view existed in the view tree and its frame. Because none of the inspection tools returned data, I couldn't introspect at runtime and had to fall back to static code analysis. Live view-hierarchy/expression inspection is exactly what these tools are for.

## Asks
- `debug_view_hierarchy` / `debug_evaluate` should transparently handle a *running* process (interrupt → eval → continue) or return an explicit, actionable error instead of empty output.
- Investigate the objc-expression timeout in `debug_lldb_command` (does the eval require the process stopped on a thread? is there an expression-evaluation timeout that's too short for AppKit calls?).
- Prefer robust window resolution (key/main/first) when dumping the macOS view hierarchy.


## Summary of Changes

Root cause: `debug_evaluate`, `debug_view_hierarchy`, and raw `expr`/`po` via `debug_lldb_command` all require a *stopped* process. Against a running target the expression evaluator returns empty output (or blocks until the 30s command timeout). The prior `requireStopped` guard only threw an error — it never recovered.

Fix (`Sources/Core/LLDBRunner.swift`):
- Added `withProcessStopped(pid:_:)` — transparently interrupts a running process, runs the body against the stopped state, then resumes it (resumes even on failure so a transient error can't freeze the app). A process already stopped at a breakpoint is left stopped so the user's inspection state isn't disturbed.
- `evaluate` and `viewHierarchy` now route through `withProcessStopped` instead of failing with `requireStopped`. Output gets an `autoResumeNote` appended when the process was running so the caller knows it was briefly paused.
- `executeCommand` (`debug_lldb_command`) now detects expression-eval commands (`expr`/`expression`/`po`/`p`/`print`/`call`) via `isExpressionCommand` and routes them through the same interrupt→eval→resume path — fixing the objc `NSLog` timeout.
- Robust macOS window resolution: the view-hierarchy dump now falls back `mainWindow` → `keyWindow` → `windows.firstObject`, with an explicit "No window found" message instead of silent nil/empty output.

`requireStopped` is retained for `debug_stack`/`debug_variables`/`debug_step`/`debug_threads`, where a meaningful breakpoint frame (not an arbitrary interrupt point) is what the user wants.

Tests: added `isExpressionCommand` coverage to `LLDBProcessStateTests` (9 passed). `LLDBCommandTimeoutTests` still green. Build clean.

---
# j22-xn8
title: debug_continue after skip_build:true relaunch leaves macOS app in SX; class_filter walk at max_depth > 12 silently drops output
status: completed
type: bug
priority: normal
created_at: 2026-05-30T19:48:09Z
updated_at: 2026-05-30T19:55:59Z
sync:
    github:
        issue_number: "369"
        synced_at: "2026-05-30T20:05:32Z"
---

Two regressions found while investigating Thesis wis-g7q (TextKit2 zombie-attachment-view dump).

## 1. `skip_build: true` relaunch never resumes
`build_debug_macos skip_build:true` reports `Successfully relaunched … Process N launched and running under debugger`. `debug_process_status` returns `running`, but `ps -p N -o state` shows `SX` and no window appears. `debug_continue` returns `Process N resumed` but state stays `SX`; subsequent `screenshot_mac_window` fails with 'No window found matching bundle_id'.

The same args via a fresh full-build `build_debug_macos` (no `skip_build`) reaches a visible window correctly.

Repro:
1. `build_debug_macos scheme:TestApp args:[…]` — works, window visible.
2. Kill the app, run again with `skip_build:true` — process spawns but stays SX; `debug_continue` is a no-op.

Smells like the relaunch path forgets to issue the initial `process continue` after launch (LLDB stops at entry by default; the full-build path handles this, skip_build path doesn't).

## 2. `debug_view_hierarchy class_filter:… max_depth:>12` produces no output file
Same project. At `max_depth: 12` the bounded NSView walk writes `/tmp/xcmcp-vh-<pid>.txt` correctly (3 nodes, useful) even when the MCP call client-times-out. At `max_depth: 25` or `30` (still with `class_filter`), the file is never created — script presumably hits LLDB's expression timeout before `fclose(_fp)`, and the partial `fputs` writes are lost because the file pointer isn't flushed.

Suggested fix: `fflush(_fp)` after each `fputs`, or open the file in line-buffered mode, so a timeout still leaves usable partial output. (Currently makes the tool unusable for deep SwiftUI hierarchies, which is exactly where bounded walks are needed.)

Repro:
```
debug_view_hierarchy pid:<P> platform:macos class_filter:HostingView max_depth:30
```
→ MCP call times out, `/tmp/xcmcp-vh-<P>.txt` does not exist.

vs.

```
debug_view_hierarchy … max_depth:12
```
→ MCP call times out, file exists with 3 lines of useful output.

## Context
Used during Thesis issue wis-g7q. Both regressions blocked further forward progress on a saga that has previously been blocked by tooling — predecessors logged in Thesis-side issue (t57-a7q, rgu-xhg, h0c-60y, eka-s03, pcm-bwn).



## Summary of Changes

**Bug #2 (view hierarchy fputs flush) — fixed.**

Root cause: the bounded-traversal ObjC expression in `boundedTraversalExpr` (Sources/Core/LLDBRunner.swift:1996) opens `_fp` via `fopen("w")`, which is fully buffered for regular files. When the LLDB expression's `--timeout` aborts mid-walk, `fclose(_fp)` is never reached and the stdio buffer is discarded — leaving no file on disk at `/tmp/xcmcp-vh-<pid>.txt`.

Fix: `setvbuf(_fp, NULL, 2, 0)` immediately after `fopen` (2 == _IONBF on Darwin) disables buffering so every `fputs` reaches the kernel synchronously. A timeout abort now leaves the partial walk on disk for inspection — making deep bounded walks (`max_depth` > 12) usable on SwiftUI-heavy hierarchies, which is the case where they matter most.

`@import Darwin` already brings `setvbuf` into scope.

**Bug #1 (skip_build relaunch leaves app windowless) — deferred to ng9-bb8.**

Code-path analysis ruled out the obvious suspect: `BuildDebugMacOSTool.execute` gates only the `xcodebuildRunner.build()` call on `skip_build`; the launch sequence (kill existing session → `AppBundlePreparer.prepare` → `launchViaOpenAndAttach` → unconditional `continue`) is shared between branches. Also noted: `ps state == SX` is normal for an attached running process (S = sleeping, X = traced) and not a stopped-at-entry symptom.

Cannot pick between the three remaining hypotheses (LS state staleness, AppBundlePreparer skipping re-sign, `pkill`/`open` race) without a live repro and diagnostic capture. Filed as ng9-bb8 with concrete next-step tests.

---
# cjs-f5u
title: search_crash_reports should show symbolicated stack trace of crashing thread
status: completed
type: feature
priority: normal
tags:
    - enhancement
created_at: 2026-03-07T21:38:25Z
updated_at: 2026-03-07T21:54:04Z
sync:
    github:
        issue_number: "182"
        synced_at: "2026-03-07T21:56:31Z"
---

## Problem

`search_crash_reports` returns only the exception type and signal:

```
Exception: EXC_BREAKPOINT (SIGTRAP)
Termination: SIGNAL — Trace/BPT trap: 5
```

To find the actual crash cause, we had to:
1. Read the raw .ips file (JSON)
2. Find `faultingThread` index
3. Manually scan thread frames for symbolicated names

In this session, the crash was `Diagnostic.log` → `assertionFailure` at `Diagnostic.swift:152`, which was only discoverable by reading the full crash JSON.

## Expected behavior

Include the crashing thread's symbolicated stack trace (top 10-15 frames) in the output:

```
Exception: EXC_BREAKPOINT (SIGTRAP)
Termination: SIGNAL — Trace/BPT trap: 5

Crashing Thread 6:
  0  Swift        _assertionFailure
  1  Core         Diagnostic.log(_:for:file:method:line:showInConsole:fail:as:) +356  Diagnostic.swift:152
  2  Core         closure #1 in static Diagnostic.log
  ...
```

The .ips JSON already contains `faultingThread`, thread frames with `symbol`, `symbolLocation`, `sourceFile`, and `sourceLine`.

## Summary of Changes

Added crashing thread stack trace parsing to `CrashReportParser`. The `CrashSummary` now includes `crashingThread` (thread index) and `crashingThreadFrames` (top 15 symbolicated frames). The `formatted()` output appends the crashing thread with image names, symbols, offsets, and source locations resolved from the .ips JSON's `faultingThread`, `threads`, and `usedImages` arrays.

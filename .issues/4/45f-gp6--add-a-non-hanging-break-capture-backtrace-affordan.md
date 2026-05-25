---
# 45f-gp6
title: Add a non-hanging 'break + capture backtrace' affordance for hot symbols
status: scrapped
type: feature
priority: normal
created_at: 2026-05-25T22:31:53Z
updated_at: 2026-05-25T22:32:55Z
blocked_by:
    - dq5-oel
sync:
    github:
        issue_number: "340"
        synced_at: "2026-05-25T22:40:51Z"
---

Follow-up to dq5-oel. The must-fix timeout/flood guards and the pathological-condition advisor landed there; this covers the larger ergonomic gap.

The recurring need is "stop when SQL/string matching X runs and give me the Swift call stack" without hand-rolling a conditional breakpoint on a hot C symbol (the dq5-oel footgun).

## Scope

1. **One-shot break + auto-capture tool/param.** Set a breakpoint with `breakpoint command add` that auto-prints `bt` and auto-continues (`-G true`), bounded and non-interactive, so no follow-up debug_stack call is needed. Return the captured backtrace(s). Must stay within the new flood/timeout guards.
2. **SQLite statement tracing alternative.** Support `sqlite3_trace_v2` as a lighter path when the goal is 'which SQL ran + stack', avoiding a symbol breakpoint entirely.

## Notes
- Needs end-to-end validation against a real target (likely the Thesis app via the test harness), which is why it is split out from the bug fix.

## Reasons for Scrapping

Folded back into dq5-oel — implementing the break+capture affordance directly rather than deferring.

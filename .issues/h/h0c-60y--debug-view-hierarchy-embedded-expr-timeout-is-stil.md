---
# h0c-60y
title: 'debug_view_hierarchy: embedded expr --timeout is still 15s after eka-s03; tool''s timeout arg only raises read side'
status: completed
type: bug
priority: normal
created_at: 2026-05-30T00:51:20Z
updated_at: 2026-05-30T00:57:37Z
sync:
    github:
        issue_number: "363"
        synced_at: "2026-05-30T01:03:12Z"
---

Follow-up to eka-s03. Re-running the wis-g7q diagnostic against the macOS Thesis TestApp:

## Repro
1. \`mcp__xc-debug__build_debug_macos scheme: TestApp args: [\"--database\", \"<sqlite>\", \"--show-node\", \"<uuid>\"]\` — launches under LLDB.
2. \`mcp__xc-debug__debug_view_hierarchy pid: <pid> platform: macos max_depth: 2 timeout: 120\`
3. The bounded stack walk runs, but the underlying \`expr -l objc -O --timeout 15000000 ...\` still has \`--timeout 15000000\` (15 seconds in microseconds), so on a SwiftUI-heavy hierarchy the expr call exceeds 15 s and the tool returns \"Timed out waiting for LLDB response. Partial output: expr -l objc -O --timeout 15000000 ...\".

The user's \`timeout\` argument raises the *read-side* timeout (so the tool waits longer for output), but the LLDB expression timeout embedded inside the command string is still hardcoded to 15 s. The two need to track each other — if I pass \`timeout: 120\`, the embedded \`--timeout\` should be \`120000000\` (120 s in µs).

## Secondary symptom: SIGSTOP not cleared on session recovery
After a timeout, the next \`debug_evaluate\` against the same PID returns:

> Process <pid> is stopped due to a crash (signal SIGSTOP). Expression evaluation may fail.

Calling \`debug_continue\` resumes the process, then the *next* \`debug_evaluate\` succeeds — sometimes. The follow-up evaluate often re-poisons the session and the cycle starts over.

The eka-s03 changelog mentioned \`LLDBRunner.withProcessStopped\` falling back to \`kill(pid, SIGCONT)\` when the resume continue fails. That fallback doesn't appear to fire after \`debug_view_hierarchy\` times out — the SIGSTOP persists until I call \`debug_continue\` explicitly.

## Blocked work
Same wis-g7q diagnostic — need to identify which subview class is stuck over the table region after the reproducer remounts the attachment. With \`max_depth: 2\` the walk visits maybe a few hundred nodes and should complete in well under a second of CPU time; the only reason it's timing out is that the expr-side timeout is still 15 s and the LLDB session is occasionally just slow to ack via the PTY pipe.

## Suggested fix
- Inside the bounded-walk command builder, set \`--timeout \\(timeout * 1_000_000)\` (microseconds) instead of the hardcoded \`15000000\`, so the user's \`timeout\` flows through.
- After any expr timeout against an attached process, attempt \`kill(pid, SIGCONT)\` unconditionally before reporting failure, so the next call doesn't fail on a stranded SIGSTOP.



## Summary of Changes

Two fixes:

1. `ArgumentExtraction.getDouble` now accepts JSON integer values (`.int`) in addition to `.double`. The MCP client sends `timeout: 120` as an integer, which previously returned `nil` — so `timeoutSeconds` never reached `viewHierarchy`, and the embedded `--timeout` stayed at the hardcoded 15s default. Now an integer-valued timeout argument flows through to the `expr --timeout` option in microseconds.
2. `LLDBRunner.withProcessStopped` now sends `SIGCONT` to the inferior unconditionally on the error path (in addition to attempting `sendCommandNoWait("continue")`). The previous fallback only fired when the queued continue threw, but session poisoning happens in a fire-and-forget Task that races with the catch block — so `sendCommandNoWait` often succeeded yet the inferior stayed SIGSTOP'd. SIGCONT to a non-stopped process is a no-op, so the unconditional kick is safe.

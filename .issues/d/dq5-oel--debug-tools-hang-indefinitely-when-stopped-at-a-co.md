---
# dq5-oel
title: Debug tools hang indefinitely when stopped at a conditional breakpoint on a high-frequency symbol
status: completed
type: bug
priority: high
created_at: 2026-05-25T22:12:25Z
updated_at: 2026-05-25T22:36:39Z
sync:
    github:
        issue_number: "339"
        synced_at: "2026-05-25T22:40:51Z"
---

## Summary

When an LLDB breakpoint is set on a **high-frequency C symbol** with a **condition that calls inferior functions**, the target slows to a crawl and subsequent debug tool calls hang indefinitely (observed **>1h13m** before the user aborted), surfacing as MCP timeouts / forced cancels.

## Repro (observed in a live session)

1. `debug_lldb_command` set a conditional breakpoint:
   ```
   breakpoint set -n sqlite3_prepare_v2 -n sqlite3_prepare_v3 \
     -c '(int)strncmp((char*)$arg2, "DELETE", 6) == 0 && (BOOL)strstr((char*)$arg2, "node") != 0'
   ```
   `sqlite3_prepare_v2/v3` is called on essentially every SQL statement, so the condition (which itself **calls `strncmp`/`strstr` in the inferior**) is evaluated thousands of times/sec.
2. App appeared to "pause immediately" on the first matching statement.
3. Every follow-up call then hung:
   - `debug_process_status` → `Timed out waiting for LLDB response. Partial output: process status`
   - `debug_stack` (thread 1) → never returned (user-cancelled after long wait)
   - `debug_lldb_command "thread backtrace"` / `"bt 12"` → never returned

## Likely causes (to investigate)

1. **Inferior-function-calling breakpoint conditions on hot symbols**: each evaluation runs `strncmp`/`strstr` via the expression evaluator → enormous slowdown; LLDBRunner has no guard/warning.
2. **No command timeout / cancellation** in `LLDBRunner` for `bt`/`thread backtrace`/`process status` when the session is wedged — the MCP call blocks until the harness force-cancels instead of returning a bounded error.
3. Possibly the backtrace itself triggers re-evaluation or the runner serializes behind a still-running implicit continue.

## Expected

- `LLDBRunner` commands should have a **bounded timeout** and return a clear error (e.g. "LLDB busy/no response in Ns") rather than hanging for the whole MCP request.
- Ideally, `DebugBreakpointAddTool` / `DebugLLDBCommandTool` should **warn** when a condition targets a high-frequency symbol and/or uses inferior function calls, suggesting a non-calling condition or a function-entry filter.

## Affected files

- `Sources/Core/LLDBRunner.swift` (command dispatch / timeout)
- `Sources/Tools/Debug/DebugProcessStatusTool.swift`, `DebugStackTool.swift`, `DebugLLDBCommandTool.swift`


## Findings / additional requirement

The hang made it impossible to capture the one thing the debugging session needed: a **backtrace at the moment a specific SQL statement runs**. A safe, non-hanging capture method for this is itself an xc-mcp gap to close. Concretely:

1. **Bounded timeouts on every LLDB command (must-fix).** `debug_process_status`, `debug_stack`, `debug_threads`, and `debug_lldb_command` must return a structured "LLDB unresponsive after Ns" error instead of blocking the MCP request indefinitely. Without this, one bad breakpoint wedges the whole session and the only recovery is `kill -9` the target from a shell.

2. **Guard against pathological breakpoint conditions.** `debug_breakpoint_add` / `debug_lldb_command` should detect and warn when a condition:
   - targets a **high-frequency symbol** (e.g. `sqlite3_prepare_v2/v3`, `malloc`, `objc_msgSend`), and/or
   - **calls inferior functions** (`strncmp`, `strstr`, etc.) in the condition expression.
   These evaluate via the expression evaluator on every hit and can slow the target by orders of magnitude (observed >1h13m wedge). Prefer suggesting a register/memory-only condition or a function-entry filter.

3. **Provide a first-class "break + capture backtrace" affordance.** A common need is "stop when SQL matching X executes and give me the Swift call stack." Today that requires a hand-rolled conditional breakpoint on a hot C symbol — exactly the footgun above. Options to offer instead:
   - A dedicated tool/param that sets a breakpoint with `breakpoint command add` to **auto-print `bt` and auto-continue** (one-shot capture), bounded and non-interactive, so no follow-up `debug_stack` call is needed.
   - Support for SQLite's own statement tracing (`sqlite3_trace_v2`) as a lighter alternative to symbol breakpoints when the goal is "which SQL ran + stack".

### Recovery note for docs
When a session wedges this way, LLDB-routed tools all hang; the only reliable recovery is `kill -9 <pid>` from a shell (LLDB-free). Worth documenting.


## Summary of Changes

Root cause of the >1h13m wedge: a breakpoint on a hot symbol (`sqlite3_prepare_v2`) with an inferior-function-calling condition floods the PTY faster than LLDB ever returns a `(lldb) ` prompt. The reader thread grew an unbounded string and spun a CPU core, starving the cooperative pool so the existing 30s timeout `Task` never got scheduled.

**Must-fixes (done):**
- `LLDBRunner.readUntilPrompt` now (a) sets a shared `finished` flag so the reader thread stops promptly once any path resolves the continuation instead of spinning on flooding output, and (b) enforces a 1 MB output cap that aborts with a structured error in bounded time/memory regardless of scheduler pressure. A flood now poisons the session (like a timeout) so the manager recreates a clean LLDB. This bounds every command that routes through `sendCommand` — `debug_process_status`, `debug_stack`, `debug_threads`, `debug_lldb_command`.
- New `BreakpointConditionAdvisor` (Core) detects breakpoints on high-frequency symbols and conditions that call inferior functions. Wired into `debug_breakpoint_add` and `debug_lldb_command`, which now prepend warnings (computed before execution so they surface even if the command wedges).
- Recovery + footgun note added to `Main.md` (kill -9 the target as the LLDB-free recovery path).

**Tests:** `BreakpointConditionAdvisorTests` (6) + `LLDBCommandTimeoutTests` flood-abort test — 9/9 passing.

**Break + capture affordance (requirement 3):** new `debug_capture_backtrace` tool sets an auto-continuing breakpoint (`--auto-continue true` + `--command "bt N"` + a sentinel marker) that prints the stack and resumes on its own, collects up to `max_hits` backtraces, then interrupts and removes the breakpoint. Bounded by a timeout and the same output byte cap, so it can't wedge the session — the safe replacement for hand-rolling a conditional breakpoint on a hot symbol. Registered in both the monolith and xc-debug (now 23 tools). `sqlite3_trace_v2` was not pursued: the auto-continue capture covers the same 'which call ran + stack' need without a separate tracing path.

### Files
- `Sources/Core/LLDBRunner.swift`
- `Sources/Core/BreakpointConditionAdvisor.swift` (new)
- `Sources/Tools/Debug/DebugLLDBCommandTool.swift`, `DebugBreakpointAddTool.swift`
- `Sources/Documentation.docc/Main.md`
- `Tests/BreakpointConditionAdvisorTests.swift` (new), `Tests/LLDBCommandTimeoutTests.swift`



### Additional files (requirement 3)
- `Sources/Tools/Debug/DebugCaptureBacktraceTool.swift` (new), `Sources/Servers/Debug/DebugMCPServer.swift`, `Sources/Server/XcodeMCPServer.swift`, `Sources/Core/ServerToolDirectory.swift`
- `LLDBRunner.captureBacktrace` + `LLDBSession.collectUntilMarker` in `Sources/Core/LLDBRunner.swift`
- Tests: `CaptureBacktraceCommandTests` in `Tests/BreakpointConditionAdvisorTests.swift`

---
# qk4-x99
title: debug_evaluate user-cancel on multi-line Swift expression with custom types
status: completed
type: bug
priority: normal
created_at: 2026-06-03T18:16:51Z
updated_at: 2026-06-03T18:26:25Z
sync:
    github:
        issue_number: "384"
        synced_at: "2026-06-03T18:32:24Z"
---

## What happened

`mcp__xc-debug__debug_evaluate` failed with `MCP error -32001: user-cancel`
when evaluating a multi-line Swift expression that:

- defined a local `struct CommentStub: Codable`
- walked `NSApp.windows` recursively to collect `NSTextView`s
- called `NSTextStorage.addAttribute(_:value:range:)` three times with
  the struct as the value
- ran while the debugged process was already running (LLDB
  auto-interrupted to evaluate, per the standard behaviour)

The prior call in the same session that *succeeded* was a similar
multi-line expression that only **read** from the text storage — that
one ran fine and returned the expected result. The failing call is the
first one in the session that **mutated** state.

## Repro outline

1. Build + launch any project's macOS app under `build_debug_macos`
2. Call `debug_evaluate` with a Swift expression that
   (a) defines a nested type (struct/enum) and
   (b) mutates AppKit/Foundation state on the running process
3. Tool returns `-32001 user-cancel` instead of an evaluation result or
   a real LLDB error

## Hypothesis

`-32001` reads like a JSON-RPC cancellation from the MCP transport, not
an LLDB error — i.e. the tool itself terminated the call rather than
the debugger refusing it. Possible causes worth checking:

1. **Timeout vs `--timeout 15000000`**: the wrapper sends `expr -l swift
   --timeout 15000000`, but the MCP transport may have its own shorter
   inactivity timeout that fires while LLDB is compiling the expression
   (multi-line + nested type definition is the slow path).
2. **Compile failure surfaced as cancel**: if LLDB's Swift expression
   evaluator rejects the nested struct (e.g. because Codable synthesis
   trips on the embedded process's module map), the wrapper may map the
   resulting non-zero exit to user-cancel instead of returning the
   compiler diagnostic.
3. **Auto-interrupt race**: the wrapper has to pause the process,
   evaluate, then resume. If the prior evaluation's resume hadn't
   completed before the next one's pause issued, the second pause might
   surface as a cancel.

## Useful next steps

- Capture LLDB's actual stderr/stdout for a failing call (the current
  tool response only shows the MCP-level error code)
- Compare to the equivalent direct `lldb` invocation on the attached
  pid — does the same multi-line expression compile and run there?
- Distinguish: is `-32001` always "user pressed cancel" or also "tool
  timed out"? If the latter, raise the inactivity timeout to match the
  declared `--timeout` value, or surface "evaluation timed out" as a
  distinct error code

## Workaround (caller side)

- Define no nested types — accept `Any` and cast inside, or skip the
  type and use `NSMutableDictionary` / raw `[String: Any]` instead of a
  struct
- Split into multiple smaller calls (one per mutation)
- Pre-define types in the source under debug and refer to them by name

## Surfaced from

`thesis` project, issue `e69-ylp` (editor scroll-gutter diagnostics
overlay). Used `debug_evaluate` to inject a synthetic `comment`
attribute into the running TestApp's text storage as a visual-test
fixture for the new gutter view. The injection expression failed; the
prior read-only inspection expression succeeded. Worked around by
falling back to the SwiftUI snapshot tests for visual verification.



## Summary of Changes

Added a periodic progress-notification heartbeat to `debug_evaluate` so the
MCP client (Claude Code) stops cancelling slow Swift-expression evaluations
with `-32001 user-cancel`.

The root cause we landed on: the failure surfaces as `-32001` because the
MCP SDK suppresses the response when a `notifications/cancelled` arrives;
Claude Code renders that as `user-cancel`. The most plausible trigger for
that cancel — given the slow path is a multi-line Swift expression that
defines `struct CommentStub: Codable` and then calls a Foundation mutator
three times on a process that was auto-interrupted at an arbitrary point
— is the client's own per-tool-call patience expiring while LLDB is still
JITing the expression. Without progress notifications the request looks
idle on the wire.

Fix:

- `Sources/Tools/Debug/DebugEvaluateTool.swift`: new `executeWithProgress`
  overload. It runs `execute` inside a `ProgressReporter.stream` and a
  background `Task` that calls `reporter.ingest("evaluating expression…
  (Ns)")` every 2 s. The reporter's poll task emits the heartbeat as a
  `notifications/progress` message, which keeps the client's tool-call
  timer fresh. Both the poll task and the heartbeat task are cancelled
  synchronously from `ProgressReporter`'s `onCancel`, so we don't fire a
  stale notification after the request was abandoned (the SIGPIPE/teardown
  hazard from `0xp-xz6`).
- `Sources/Servers/Debug/DebugMCPServer.swift` and
  `Sources/Server/XcodeMCPServer.swift`: when `params._meta?.progressToken`
  is present, route `debug_evaluate` through `executeWithProgress` and
  forward notifications via `server.notify`. Falls back to the original
  `execute` when no token was supplied.

What this does **not** address (carried over caveats, not regressions):

- LLDB's `--timeout 15000000` bounds *inferior* execution, not the Swift
  JIT compile. A pathological compile can still exceed the session's 30 s
  per-command read budget and surface as our structured
  `LLDBError.commandFailed("… did not return within 30s …")`, not as a
  cancel.
- Mutating AppKit/Foundation state on a process that was auto-interrupted
  outside a runloop tick can still wedge the inferior call. Callers should
  prefer the workarounds already documented in this issue (no nested
  types, split into multiple calls, or define the type in the source).
- Whether LLDB actually accepts a multi-line body sent verbatim through
  the PTY (vs. needing `command source` + multi-line-expression input
  mode) was not changed — the existing path worked for the read-only
  multi-line case the issue notes, so we did not touch it. If we see this
  bug recur on expressions that fit within the timeout, the next step is
  to route any expression containing `\n` through `command source` the
  same way `viewHierarchy` does (`Sources/Core/LLDBRunner.swift:1899`).

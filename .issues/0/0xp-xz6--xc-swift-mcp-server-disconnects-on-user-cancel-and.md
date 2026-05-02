---
# 0xp-xz6
title: xc-swift MCP server disconnects on user-cancel and never reconnects
status: completed
type: bug
priority: high
created_at: 2026-05-01T23:49:50Z
updated_at: 2026-05-02T00:02:57Z
sync:
    github:
        issue_number: "303"
        synced_at: "2026-05-02T03:17:27Z"
---

## Symptom

Mid-session, all `mcp__xc-swift__*` tools went unavailable to the Claude Code agent. The harness reported:

```
The following deferred tools are no longer available (their MCP server disconnected). Do not search for them — ToolSearch will return no match:
mcp__xc-swift__clear_session_defaults
mcp__xc-swift__detect_unused_code
mcp__xc-swift__get_coverage_report
mcp__xc-swift__get_file_coverage
mcp__xc-swift__set_session_defaults
mcp__xc-swift__show_session_defaults
mcp__xc-swift__swift_diagnostics
mcp__xc-swift__swift_format
mcp__xc-swift__swift_lint
mcp__xc-swift__swift_package_build
mcp__xc-swift__swift_package_clean
mcp__xc-swift__swift_package_list
mcp__xc-swift__swift_package_run
mcp__xc-swift__swift_package_stop
mcp__xc-swift__swift_package_test
mcp__xc-swift__swift_symbols
```

After resuming the session (SessionStart:resume hook), the tools came back. Other MCP servers in the same session (xc-build, xc-project, xc-debug, chrome-devtools, etc.) stayed connected the whole time.

## Trigger

The disconnect appears to have been caused by **user-cancelling an in-flight tool call** (`swift_package_test`). The MCP error returned was:

```
MCP error -32001: user-cancel
```

Immediately after that error, the deferred-tool-removal notice appeared. The server did not reconnect on its own — only on session resume.

## Reproduction (suspected)

1. Start a Claude Code session in a Swift package.
2. Call `mcp__xc-swift__swift_package_test` (with a slow filter, or a build that takes long enough for cancellation to be plausible).
3. While the call is in flight, user-cancel the tool call from the Claude Code TUI.
4. Observe: the `xc-swift` server is dropped from the session and ALL of its tools become unavailable for the remainder of the session (until /resume).

## Impact

- Agent can't run tests/build/lint/format via MCP for the rest of the session.
- The `jig nope` hook still blocks plain `swift test` / `swift build`, so the agent has no fallback path.
- The user has to /resume to recover, which loses ephemeral state.

## Expected

A user-cancel on a single tool call should NOT terminate the MCP server connection. The server should remain alive and ready to handle the next call. If the running operation can't be cancelled cleanly, kill just that operation, not the whole stdio pipe.

## Environment

- Claude Code on macOS (Darwin 25.4.0)
- xc-swift MCP server (version unknown — whatever was running in this session)
- Session: long-running Swift package work in `/Users/jason/Developer/toba/swiftiomatic`
- Other MCP servers in the same session were unaffected (xc-build, xc-project, xc-debug, claude_ai_*, chrome-devtools)

## Suggested investigation

- Audit how cancellation is propagated in the xc-swift server's stdio loop. If a SIGINT/SIGTERM or pipe close is being treated as fatal, mark it recoverable.
- Add a watchdog / auto-reconnect path so a dead server can be restarted without /resume.
- Log the exit code/signal of the server process when it dies, so future repros can be diagnosed from logs.



## Summary of Changes

Two complementary fixes — the immediate, high-impact one is SIGPIPE handling.

`Sources/CLI.swift`: install `signal(SIGPIPE, SIG_IGN)` at the very top of `MulticallCLI.main()` (covers every focused server and the monolithic one). MCP servers run over stdio; when a client cancels an in-flight request and stops reading, any subsequent write — including a stale `notifications/progress` — triggers SIGPIPE and the default disposition kills the process. That matches the reported symptom (one cancel → server gone for the rest of the session, /resume needed). Ignoring SIGPIPE converts the failed write into an EPIPE return code that the SDK already swallows, so the server stays alive and ready for the next call.

`Sources/Core/ProgressReporter.swift`: tighten `stream(_:)` so the unstructured poll task is also cancelled synchronously from the `onCancel` handler, not only via the `defer` that runs after `body` unwinds. The poll task is captured in a `Mutex<Task<Void, Never>?>` so the cancellation handler can reach it. With both `retire()` and `pollTask.cancel()` firing immediately on cancel, the poll loop exits before its next `emitIfPending` iteration, closing the residual race where a snapshot prepared at `retired == false` could still reach `notify` after retirement was requested. Even if a notification did slip through, SIGPIPE is now handled.

Verified: `swift build` clean; full ProgressReporter + BuildOutputParser test suites pass (71/71). The fix is general — every server (xc-build, xc-debug, xc-project, xc-simulator, xc-strings, xc-swift, xc-device, xc-mcp) gets the SIGPIPE protection.

The issue's third investigation suggestion (log exit code/signal so future repros are diagnosable from logs) is best addressed by an external supervisor — the server can't log its own SIGPIPE death from inside the process. With SIGPIPE ignored that should no longer be the failure mode; if the server still dies the cause will be a real crash whose stack trace will land in the system Crash Reporter.

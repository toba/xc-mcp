---
# n9s-kny
title: MCP server stdio transport dies after request cancellation due to stale progress notifications
status: review
type: bug
priority: high
created_at: 2026-05-01T03:39:58Z
updated_at: 2026-05-01T03:53:53Z
sync:
    github:
        issue_number: "300"
        synced_at: "2026-05-01T04:16:25Z"
---

The xc-swift MCP server's STDIO transport drops permanently after a tool request is cancelled by the client. Subsequent tool calls fail because the server is gone.

## Repro from a Claude Code session

Session log: `~/Library/Caches/claude-cli-nodejs/-Users-jason-Developer-toba-swiftiomatic/mcp-logs-xc-swift/2026-05-01T01-31-34-593Z.jsonl`

Sequence:

1. `swift_package_test` invoked at 03:29:14.743Z, progress token 16 issued.
2. User cancels the request at 03:29:23.168Z → client returns `MCP error -32001: user-cancel`.
3. 1.6s later (03:29:24.778Z) the stdio connection drops:
   - `STDIO connection dropped after 5410s uptime`
   - `Connection error: Received a progress notification for an unknown token: {"method":"notifications/progress","params":{"progress":480,"message":"[10/22] Write swift-version--58304C5D6DBC2206.txt","progressToken":16}}`
   - `Closing transport (stdio transport error: Error)`
4. All `mcp__xc-swift__*` tools become unavailable for the rest of the Claude session.

## Root cause hypothesis

After the client cancels request 16, the server keeps running its in-flight `swift build`/`swift test` subprocess and continues to emit `notifications/progress` referencing `progressToken: 16`. The MCP client (Claude Code's `@modelcontextprotocol` SDK) treats progress for an unknown/cancelled token as a transport error and tears down the stdio pipe. Once stdin is closed on the server, every subsequent request errors and the parent has no path to relaunch — so the entire `xc-swift` tool surface is dead until the next Claude session.

Two reasonable server-side fixes (either is sufficient):

1. **Honor cancellation.** When the client sends `notifications/cancelled` for a request, the server should:
   - mark the progress token retired
   - stop emitting `notifications/progress` for that token
   - ideally also kill the underlying `swift` subprocess, since the user said "stop"
2. **Track active tokens defensively.** Before emitting any `notifications/progress`, check that the token is still associated with an in-flight request the *server* believes is alive; drop the notification otherwise.

A third hardening: even if the server emits a stale progress notification, losing the entire transport is a heavy-handed reaction. Consider adding a wrapper around the SDK transport in xc-mcp's process model so that swallowed progress notifications don't kill the connection — but the canonical fix is on the emitter side.

## Why this matters

Progress notifications are the *normal* output during long builds (5+ minute Swift builds emit dozens). Any user-cancel during a long build is very likely to land in a window where another progress notification is in flight or about to be emitted, deterministically killing the server. In a long Claude session this means losing access to all build/test/diagnostic tools until restart, which is exactly when an agent would otherwise want to recover and try a smaller filter.

## Affected tool surface (lost after disconnect)

All `mcp__xc-swift__*` tools: `swift_package_build`, `swift_package_test`, `swift_package_clean`, `swift_format`, `swift_lint`, `swift_diagnostics`, `swift_symbols`, `detect_unused_code`, etc.

## Suggested investigation

- Find where the server registers progress callbacks for the running `swift` subprocess and confirm what happens to that callback after a `notifications/cancelled` arrives.
- Check whether the SDK auto-handles `notifications/cancelled` or whether xc-mcp needs to wire it up explicitly. The MCP TypeScript/Swift SDKs typically expose a `CancellationToken` per request — if xc-mcp isn't observing it, that's the smoking gun.
- Verify the subprocess is also killed on cancel (otherwise the build keeps running to completion in the background even though no one will read the output).

## Related

- Same session shows multiple `still running (30s/60s/.../330s elapsed)` traces during a 5m40s build — the progress channel is hot the whole time, so the cancel race is wide.
- Also observed: `Channel notifications skipped: server did not declare claude/channel capability` (03:38:35.112Z) — unrelated but worth noting alongside the capability handshake.



## Summary of Changes

Root cause: `ProgressReporter.stream` spawns its progress poller via an unstructured `Task {}`. Unstructured tasks do not inherit cancellation from the surrounding task, so when the swift-sdk cancels the handler task in response to `notifications/cancelled` (Server.swift:967), the poller keeps firing every `interval` until `defer { pollTask.cancel() }` runs — which only happens after `body()` finishes unwinding (subprocess SIGKILL, output drain, etc.). That window matches the observed 1.6s gap between user-cancel and the fatal stale progress.

Fix in `Sources/Core/ProgressReporter.swift`:
- Added a `retired` flag to the reporter state.
- `stream(_:)` now wraps the body in `withTaskCancellationHandler` and retires synchronously in `onCancel`, so cancellation immediately stops emission instead of waiting for body unwind.
- `emitIfPending()` checks `retired` both at snapshot time and again immediately before `notify`, minimizing the snapshot→wire race window.
- `stream(_:)` also retires in defer for the success/throw paths.

Tests added (`Tests/ProgressReporterTests.swift`):
- `Retired reporter drops pending emission` — confirms `retire()` blocks `emitIfPending`.
- `Stream retires reporter when surrounding task is cancelled` — drives a streaming body, cancels mid-flight, verifies no further notifications are recorded after cancellation.

Both new tests pass. No changes needed to `SwiftMCPServer` / `XcodeMCPServer` call sites — the fix is entirely inside the shared `ProgressReporter`, so all current and future tools using it benefit.

Status set to `review` because the real validation is end-to-end: cancel a long `swift_package_test` from a Claude session and confirm the xc-swift transport survives.

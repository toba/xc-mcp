---
# ive-jzc
title: xc-swift MCP server disconnects mid-session after user-cancelled tool call
status: completed
type: bug
priority: normal
created_at: 2026-05-02T03:03:59Z
updated_at: 2026-05-02T03:11:50Z
sync:
    github:
        issue_number: "305"
        synced_at: "2026-05-02T03:17:28Z"
---

While iterating on a Swiftiomatic rule fix, the xc-swift MCP server disconnected mid-session. All xc-swift tools became unavailable (swift_package_build, swift_package_test, swift_diagnostics, swift_format, swift_lint, etc.).

Repro:
1. Open a Claude Code session in a Swift package project that uses xc-swift via MCP.
2. Edit a source file and run swift_package_test successfully.
3. Run swift_package_build with configuration release. The user cancels mid-build.
4. After cancel, all xc-swift tools become unavailable. The harness reports the MCP server has disconnected.

Impact: Agent is then unable to build or test the Swift package because the project-side hook config blocks direct invocations and mandates xc-mcp. The agent is stuck — it cannot bypass the hook and cannot use the MCP tools.

Expected: A user-cancelled tool call should not terminate the entire MCP server. The server should remain alive and ready for subsequent calls.

- [x] Reproduce locally
- [x] Identify why a tool cancel terminates the server process (vs. just aborting the in-flight request)
- [x] Ensure cancellation only aborts the active request

## Summary of Changes

The previous fix (`0xp-xz6`, commit 44cda28) closed the SIGPIPE-kills-process path but left a second disconnect path open. Found via the m13v comment on #303 ("the swift stdio handler still has to swallow that error instead of tearing down the channel").

Root cause: `Swift.Error.asMCPError()` wasn't special-casing `CancellationError`. On user-cancel:

1. `runSubprocess` rethrows `CancellationError` from the cancelled subprocess body.
2. Every tool's catch block did `throw error.asMCPError()`, converting the cancellation into `MCPError.internalError("CancellationError()\n\nBacktrace:\n<huge async backtrace>")` (backtrace appended on macOS 26+).
3. The MCP SDK's request handler caught this as a non-cancellation error and emitted an error response.
4. Per the [MCP cancellation spec](https://modelcontextprotocol.io/specification/2025-11-25/basic/utilities/cancellation), the server **MUST NOT** respond to a cancelled request — sending one is a protocol violation. Claude Code treats it as fatal and tears the stdio pipe down, exactly the disconnect symptom reported.

Fix in `Sources/Core/MCPErrorConvertible.swift`: `asMCPError()` is now `throws` and rethrows `CancellationError` unchanged. All 79 caller sites updated to `throw try error.asMCPError()` via sed. Cancellation now propagates up to the SDK's `catch is CancellationError` arm, which correctly skips the response.

Added `Tests/MCPErrorConvertibleTests.swift` with three regression tests:
- `asMCPError rethrows CancellationError` — locks in the fix.
- `asMCPError returns existing MCPError unchanged` — guards the passthrough path.
- `asMCPError wraps arbitrary errors as internalError` — guards the default path.

All ProgressReporter tests still pass (12/12). Full clean build.

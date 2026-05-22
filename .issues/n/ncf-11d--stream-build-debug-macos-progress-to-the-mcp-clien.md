---
# ncf-11d
title: Stream build_debug_macos progress to the MCP client
status: completed
type: feature
priority: normal
created_at: 2026-05-22T23:09:44Z
updated_at: 2026-05-22T23:14:02Z
sync:
    github:
        issue_number: "328"
        synced_at: "2026-05-22T23:19:50Z"
---

Split out from b1b-k93. `BuildDebugMacOSTool` passes `onProgress: { line in logger.info(line) }`, so cold-build output goes only to the server log. The MCP client sees nothing until the tool returns, making a legitimate multi-minute cold build indistinguishable from a hang (callers cancel it). Plumb a progress token through `execute()` and emit periodic `notifications/progress` (see `Sources/Core/ProgressReporter.swift` and its use in `SwiftPackageBuildTool`/`SwiftPackageTestTool`). Must respect the MCP cancellation rules in CLAUDE.md (retire reporters synchronously on cancel).


## Summary of Changes

Streamed `build_debug_macos` build output to the MCP client via `notifications/progress`, reusing the existing `ProgressReporter` infrastructure (so cancellation/retirement semantics required by CLAUDE.md are already handled).

1. **`BuildDebugMacOSTool.execute()`** — added an optional `onProgress: (@Sendable (String) -> Void)?` parameter; the build's existing progress closure now forwards each line to it (in addition to the server log).
2. **`DebugMCPServer.swift`** — `build_debug_macos` dispatch wraps execution in a `ProgressReporter` when the client supplies `params._meta?.progressToken`, mirroring the `swift_package_build`/`swift_package_test` pattern.
3. **`XcodeMCPServer.swift`** (monolith) — same dispatch wrapping.

Build green (`swift_package_build`). `ProgressReporter` tests pass; the one failing test in that file (`extraArgsFromEnvironment is empty when env var unset`) is a pre-existing parallel-execution env-var isolation flake in a sibling `SwiftRunner` test, unrelated to this change.

(The two stale SourceKit "Extra argument 'onProgress'" diagnostics were index lag before the tool's new parameter was picked up — the compiler accepts the calls.)

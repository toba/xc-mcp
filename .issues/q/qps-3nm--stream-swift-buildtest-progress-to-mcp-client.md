---
# qps-3nm
title: Stream swift build/test progress to MCP client
status: completed
type: feature
priority: normal
created_at: 2026-04-30T16:03:15Z
updated_at: 2026-04-30T16:51:40Z
sync:
    github:
        issue_number: "298"
        synced_at: "2026-04-30T17:20:52Z"
---

Today, swift_package_build and swift_package_test buffer all output until the process exits, so a 10-minute swift-syntax compile looks like a hang. Pipe periodic last-line snapshots (e.g. 'Compiling SwiftSyntax SyntaxNodes02.swift') back to the client via MCP progress notifications or a tail-style status field on the next tool result. No speedup — pure UX. Builds on the partial-output capture already in `XcodebuildRunner.timeout(duration:partialOutput:)`.

Follow-up to tc2-9jv.

## Summary of Changes

Streams `swift_package_build` and `swift_package_test` progress to MCP clients via `notifications/progress` last-line snapshots. A 10-minute swift-syntax compile no longer looks like a hang.

**Implementation**

- `Sources/Core/ProgressReporter.swift` (new) — `Sendable` reporter that tracks total output bytes and the most recent non-empty line under a `Mutex`. `stream(_:)` runs a body while a background `Task` polls every `interval` (default 2s) and emits a `ProgressNotification` only when the line has changed. Long lines are truncated to 200 chars. Notify errors are swallowed so progress delivery cannot fail the underlying tool call. `emitIfPending()` is exposed for deterministic testing.
- `Sources/Core/ProcessResult.swift` — `runSubprocess` and `collectTail` accept an optional `onProgress: (String) -> Void` callback that fires with each decoded stdout/stderr chunk.
- `Sources/Core/SwiftRunner.swift` — `run`/`build`/`test` thread `onProgress` through to `runSubprocess`.
- `Sources/Tools/SwiftPackage/SwiftPackageBuildTool.swift` and `SwiftPackageTestTool.swift` — `execute` accepts an optional `onProgress` callback and forwards to the runner.
- `Sources/Servers/Swift/SwiftMCPServer.swift` and `Sources/Server/XcodeMCPServer.swift` — `swift_package_build` and `swift_package_test` handlers extract `params._meta?.progressToken`, build a `ProgressReporter` that calls `server.notify(...)`, and wrap the tool call in `reporter.stream { ... }`. When no token is present, the existing zero-overhead path runs unchanged.

**Tests** — `Tests/ProgressReporterTests.swift` covers last-line extraction, suppression of duplicate lines, byte-count accumulation, whitespace handling, 200-char truncation, `stream(_:)` body propagation, and an end-to-end `SwiftRunner.run(arguments: ["--version"], onProgress: ...)` smoke test that verifies real subprocess streaming.

**Notes**

- The `XcodebuildRunner` already has a streaming `onProgress` callback. Wiring it up to `notifications/progress` for `xcodebuild`-based tools (build/test/run) is a natural next step that this work makes trivial.

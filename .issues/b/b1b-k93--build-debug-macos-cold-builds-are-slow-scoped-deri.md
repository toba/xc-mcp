---
# b1b-k93
title: 'build_debug_macos cold builds are slow: scoped DerivedData isolates it from Xcode''s warm cache'
status: completed
type: bug
priority: critical
created_at: 2026-05-22T23:05:47Z
updated_at: 2026-05-22T23:09:54Z
sync:
    github:
        issue_number: "329"
        synced_at: "2026-05-22T23:19:50Z"
---

## Symptom

`build_debug_macos` takes minutes on a "cold" build even when an Xcode Run of the *same* commit completes in seconds. With no streamed progress, it looks like a hang, so callers cancel it.

## Root cause (primary): scoped DerivedData is isolated from Xcode's warm cache

`DerivedDataScoper` injects `-derivedDataPath ~/Library/Caches/xc-mcp/DerivedData/<Project>-<hash>` (race avoidance across agents). Confirmed both dirs coexist for one clone:

- xc-mcp:  `~/Library/Caches/xc-mcp/DerivedData/Thesis-4019ecb6511d`
- Xcode:   `~/Library/Developer/Xcode/DerivedData/Thesis-ddfqsiuxmcpnzhcbomdlbbstfbci`

Because the path differs, xc-mcp shares **neither build products nor `ModuleCache.noindex`** with Xcode. So the first `build_debug_macos` after a user has only ever built in Xcode is **fully cold**: it recompiles every Swift module *and* the expensive `GRDBCustom`/`SQLiteLib` C amalgamation (`sqlite3.c`), which alone is minutes. Xcode's incremental Run reuses its own warm cache and is seconds. This is by design but punishes the common single-agent "I just built in Xcode, now run under LLDB" workflow.

Existing escape hatch: `XC_MCP_DISABLE_DERIVED_DATA_SCOPING=1` (falls back to Xcode's shared DerivedData) — undocumented at the tool level.

## Contributing factor: no progress surfaced to the client

`BuildDebugMacOSTool` passes `onProgress: { line in Self.logger.info(line) }` — build output goes to the server log, not the MCP client. The client sees nothing until the tool returns, so a legitimate multi-minute cold build is indistinguishable from a hang and gets cancelled.

## Contributing factor: extra pre-build `showBuildSettings`

`execute()` runs `xcodebuildRunner.showBuildSettings(...)` (Step 1, to get the bundle id) before the build. That's an extra xcodebuild invocation + package-graph resolution on every launch, adding latency before compilation starts.

## Suggested fixes

1. For single-agent use, reuse Xcode's DerivedData (or auto-detect single agent), or at minimum document `XC_MCP_DISABLE_DERIVED_DATA_SCOPING=1` in the `build_debug_macos` tool description so cold builds inherit Xcode's warm cache.
2. Surface build progress to the client (periodic notifications / partial output), or return early with a "build in progress" affordance, so cold builds aren't mistaken for hangs.
3. Cache/reuse the bundle id (or fold it into a single xcodebuild pass) to drop the extra `showBuildSettings` round-trip.

## Not the cause

The Thesis project sets `ONLY_ACTIVE_ARCH = YES` for Debug, so `destination=platform=macOS` is not building a universal binary. Ruled out.

## Repro

1. Build + Run the project in Xcode (warms `~/Library/Developer/Xcode/DerivedData`).
2. Call `build_debug_macos` (scheme Standard) → fully cold build into `~/Library/Caches/xc-mcp/DerivedData`, minutes, no progress output.


## Update — measured comparison (re-ranks causes)

User data point: **Xcode cold build of this project = 47.4s.** So a cold build is legitimately ~47s; if `build_debug_macos` takes minutes, the separate-DerivedData "cold" story is *not the whole picture* — there is xc-mcp-specific overhead stacked on top. Re-ranking:

### Likely-dominant cause: pre-build full `-showBuildSettings`
`BuildDebugMacOSTool.execute()` Step 1 calls `showBuildSettings(scheme:)` **before** building, only to read `PRODUCT_BUNDLE_IDENTIFIER` (+ later app path / `EXECUTABLE_NAME`). That invocation is `xcodebuild -scheme <s> -configuration Debug -showBuildSettings -json` with **no `-destination`**, which forces resolution of the **entire SPM package graph + every target's settings** (and can trigger package resolution) — tens of seconds on a project with SPM deps + the GRDB/SQLite submodule. This runs on *every* launch, serially before compilation. Total ≈ showBuildSettings(slow) + build(~47s) + LLDB attach, which reads as "minutes / hung."

Fixes: (a) pass a concrete `-destination platform=macOS` to `-showBuildSettings` to narrow resolution; (b) reuse the build's own settings instead of a separate pre-pass; (c) cache bundle id/app path per (project, scheme, config) mtime; or (d) derive bundle id without a full scheme settings dump.

### Still relevant
- Separate scoped DerivedData (cold vs Xcode's warm cache) — explains why it can't match Xcode's *incremental* Run; mitigated by `XC_MCP_DISABLE_DERIVED_DATA_SCOPING=1` (undocumented at tool level).
- No progress streamed to client (`onProgress` → `logger.info` only) → cold builds look like hangs and get cancelled.

### Suggested triage order
1. Time `xcodebuild … -showBuildSettings -json` alone (no destination) vs with `-destination platform=macOS` on this project — likely the bulk of the excess.
2. Eliminate/narrow the pre-build settings pass.
3. Surface progress.


## Summary of Changes

Addressed the two dominant, low-risk causes; split progress-streaming into follow-up `ncf-11d`.

1. **Narrowed the pre-build `-showBuildSettings` pass** (`BuildDebugMacOSTool.execute()`): the destination (`platform=macOS[,arch=…]`) is now computed up front and passed to `showBuildSettings`, so xcodebuild resolves only the macOS platform's settings instead of the entire SPM package graph for every target. This was the likely-dominant excess latency on launch.
   - **Regression guard**: an iOS-only scheme can't resolve `-destination platform=macOS`, which would return an empty settings dump and skip the friendly "scheme does not support macOS" check. Added a fallback that retries `showBuildSettings` *without* a destination only when the fast pass yields neither `PRODUCT_BUNDLE_IDENTIFIER` nor `SUPPORTED_PLATFORMS`, preserving the friendly error path.
2. **Documented `XC_MCP_DISABLE_DERIVED_DATA_SCOPING=1`** in the `build_debug_macos` tool description, so callers in the common single-agent "just built in Xcode, now run under LLDB" workflow can opt into Xcode's warm DerivedData cache instead of a fully-cold scoped build.
3. **Deferred**: streaming build progress to the client → follow-up `ncf-11d` (requires plumbing a progress token through `execute()`).

Build green (`swift_package_build`).

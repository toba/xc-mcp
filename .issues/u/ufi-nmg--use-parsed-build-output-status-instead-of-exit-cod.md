---
# ufi-nmg
title: Use parsed build output status instead of exit code alone to determine build success
status: completed
type: bug
priority: normal
created_at: 2026-02-21T23:54:43Z
updated_at: 2026-02-22T00:03:16Z
---

## Problem

`BuildMacOSTool.swift:79` uses `result.succeeded` (which is just `exitCode == 0` from `ProcessResult.swift:30`) to determine build success. But xcodebuild can return a non-zero exit code for builds that succeed with warnings — particularly when run script phases (like SwiftLint) return non-zero, or certain warning configurations cause xcodebuild to exit non-zero despite the build actually succeeding.

This causes `build_macos` to throw `MCPError.internalError("Build failed:...")` even when the output says "Build succeeded (118 warnings)".

## Root Cause

The `BuildOutputParser` already parses output and produces a `BuildResult.status` of `"success"` or `"failed"` based on actual errors/failures — but this is only consulted *after* the exit code has already decided the result is an error, for formatting the error message. The parser's status determination is never used for the success/failure decision.

## Fix

Parse output first, then use `buildResult.status == "success"` as a fallback when exit code is non-zero:

```swift
// Before (broken)
if result.succeeded {
    return CallTool.Result(...)
} else {
    let errorOutput = ErrorExtractor.extractBuildErrors(from: result.output)
    throw MCPError.internalError("Build failed:\n\(errorOutput)")
}

// After
let buildResult = ErrorExtractor.parseBuildOutput(result.output)

if result.succeeded || buildResult.status == "success" {
    return CallTool.Result(...)
} else {
    let errorOutput = BuildResultFormatter.formatBuildResult(buildResult)
    throw MCPError.internalError("Build failed:\n\(errorOutput)")
}
```

`ErrorExtractor.parseBuildOutput` already exists (line 87-89 of `ErrorExtraction.swift`).

## Affected Tools

Apply the same fix to all build tools that use `result.succeeded`:

- [x] `BuildMacOSTool.swift`
- [x] `BuildRunMacOSTool.swift`
- [x] `BuildSimTool.swift`
- [x] `BuildDeviceTool.swift`
- [x] `BuildDebugMacOSTool.swift`
- [x] `SwiftPackageBuildTool.swift`
- [x] `CleanTool.swift`

## Summary of Changes

All 7 build tools now consult `ErrorExtractor.parseBuildOutput()` to check the parsed build status alongside the process exit code. If either `result.succeeded` or `buildResult.status == "success"`, the tool reports success. Error paths reuse the already-parsed `BuildResult` via `BuildResultFormatter.formatBuildResult()` instead of re-parsing with `extractBuildErrors`. 528 tests pass.

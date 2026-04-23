---
# 228-mii
title: Surface verbose compiler output on signal crashes
status: completed
type: feature
priority: normal
created_at: 2026-04-23T17:02:47Z
updated_at: 2026-04-23T17:10:13Z
sync:
    github:
        issue_number: "283"
        synced_at: "2026-04-23T17:10:55Z"
---

When `swift_package_build` or `swift_diagnostics` encounters a compiler crash (signal 6 / SIGABRT), the error output only shows:

```
compile command failed due to signal 6 (use -v to see invocation)
```

The tool should automatically retry with `-v` (or capture the crash report) to surface which file and line triggered the compiler crash. Currently the agent has no way to determine the crashing file without running the build command directly in a shell.

## Acceptance
- [x] Detect signal 6/11 crashes in build output
- [x] Re-run or parse verbose output to identify the crashing compilation unit
- [x] Include the crashing file path and compiler backtrace (if available) in the error response


## Summary of Changes

- Added `ErrorExtractor.detectCompilerCrash(in:)` to detect signal crashes (6, 11, etc.) in build output
- Added `ErrorExtractor.extractCrashDetails(from:signal:)` to parse verbose output for crashing file, compiler invocation, and stack trace
- Added `verbose` parameter to `SwiftRunner.build()`
- `swift_package_build` now auto-retries with `-v` on compiler crash and includes crash details in the error
- `swift_diagnostics` now auto-retries with `-v` on compiler crash and shows a Compiler Crash section
- Added 9 tests in `CompilerCrashDetectionTests`

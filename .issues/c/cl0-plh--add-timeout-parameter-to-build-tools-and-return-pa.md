---
# cl0-plh
title: Add timeout parameter to build tools and return partial diagnostics on timeout
status: completed
type: feature
priority: normal
created_at: 2026-03-28T15:49:00Z
updated_at: 2026-03-28T15:52:28Z
sync:
    github:
        issue_number: "245"
        synced_at: "2026-03-28T15:53:58Z"
---

When a build hangs (keeps producing output but never finishes), the agent can't see any diagnostics because:
1. `build_macos` and `build_run_macos` have no `timeout` parameter — agent can't set a shorter timeout
2. When timeout fires, `XcodebuildError.toMCPError()` formats partial output poorly (no projectRoot, no showWarnings)
3. The result is an MCPError (isError=true) rather than a proper formatted build result

## Plan
- [x] Add `timeout` parameter to `build_macos` tool schema and execution
- [x] Add `timeout` parameter to `build_run_macos` tool schema and execution  
- [x] Catch `XcodebuildError` (timeout/stuckProcess) in build tools and format partial output as proper diagnostics
- [x] Use `isError: true` but with properly formatted build diagnostics (projectRoot, showWarnings)


## Summary of Changes

Added `timeout` parameter to `build_macos`, `build_run_macos` tools. Added `XcodebuildError.formatPartialDiagnostics()` method that produces properly formatted build diagnostics from partial output. All build/test tools now catch `XcodebuildError` and return formatted diagnostics instead of opaque error messages. `DiagnosticsTool` also catches timeout and continues with partial diagnostics.

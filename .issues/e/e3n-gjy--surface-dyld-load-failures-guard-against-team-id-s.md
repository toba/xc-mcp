---
# e3n-gjy
title: Surface dyld load failures + guard against Team-ID signing mismatches
status: completed
type: feature
priority: normal
created_at: 2026-05-27T03:11:12Z
updated_at: 2026-05-27T03:17:37Z
sync:
    github:
        issue_number: "345"
        synced_at: "2026-05-27T03:19:04Z"
---

## Context

While using xc-mcp debug tools to launch TestApp (a macOS app with SPM package-product frameworks: ZIPFoundation, etc.), I hit a chain of friction worth addressing in tooling. Root cause was a code-signing Team-ID mismatch (app signed with a real Apple Development identity; SPM package frameworks ad-hoc / `TeamIdentifier=not set`), which dyld rejects under library validation. But the tools made it hard to diagnose.

## Gaps observed

1. **`build_debug_macos` with `skip_build: true` crashes at launch (dyld) without DYLD_FRAMEWORK_PATH.** The relaunch path apparently doesn't set the framework search env that the full build path does, so a skip-build relaunch of a debug app with non-embedded frameworks aborts in dyld before `main`. Either set the same env on the skip-build relaunch, or document/warn that skip_build can't be used for apps relying on DYLD_FRAMEWORK_PATH.

2. **`debug_process_status` shows only a generic SIGABRT backtrace for a dyld load failure** (`dyld __abort_with_payload`), not the actual reason. The real message (`Library not loaded … not valid for use in process: … different Team IDs`) only came from manually grepping ~/Library/Logs/DiagnosticReports. Tooling could detect a dyld termination (`fatalDyldError` / `DYLD` namespace, `Library missing`) and surface the `reasons` / `details` from the crash payload directly in process status / launch failure output.

3. **No guard/warning for Team-ID signing mismatches between the app and its embedded/linked frameworks.** A pre-launch (or post-build) check comparing `codesign -dvv` TeamIdentifier across the app executable and PackageFrameworks/*.framework would catch this class of failure with an actionable message (`app signed <team>, ZIPFoundation framework ad-hoc → library validation will reject`) instead of a cryptic dyld abort.

4. **`debug_view_hierarchy` / `debug_evaluate` returned empty on a *running* (not paused) process** with no indication that the process must be stopped first to evaluate lldb expressions. Either auto-interrupt-then-resume for read-only inspection, or return a clear "process must be paused to evaluate" message.

## Notes
- The signing mismatch in my case was self-inflicted (a raw build CLI invocation against the xc-mcp scoped DerivedData re-signed the app with the dev identity while frameworks stayed ad-hoc). A Team-ID consistency check (#3) would have flagged it immediately.
- Workaround that fixed launch: rebuild via build_debug_macos with `CODE_SIGN_IDENTITY=-` so app + frameworks are uniformly ad-hoc.


## Summary of Changes

- **New `CodeSignInspector` (Sources/Core/CodeSignInspector.swift)**: parses `codesign -dvv` output (Team ID / authority, `not set` → ad-hoc), evaluates app-vs-framework Team-ID consistency (only flags when the app carries a real Team ID and a bundled framework differs), and emits an actionable warning. Filesystem helpers `inspect()` and `checkBundleConsistency()` walk `Contents/Frameworks`.
- **Gap 3 (Team-ID guard)**: `build_debug_macos` now appends the consistency warning on the launch-crash path so a signing mismatch is named directly instead of requiring a manual DiagnosticReports grep.
- **Gap 2 (surface dyld failures)**: the launch-crash branch of `build_debug_macos` now appends parsed crash reports (`CrashReportParser.appendCrashReports`) with termination reasons/details, so a dyld `__abort_with_payload` shows the real `Library not loaded … different Team IDs` reason.
- **Gap 1 (skip_build relaunch)**: `AppBundlePreparer.prepare` now forces a `disable-library-validation` re-sign when an otherwise-unmodified bundle (e.g. a skip_build relaunch with pre-existing symlinks) is found to have a Team-ID mismatch, recovering launchability.
- **Gap 4 (running process)**: `LLDBRunner.evaluate` and `viewHierarchy` now call `requireStopped(pid:)` up front, so a running target returns a clear "Process is running. Interrupt it first…" message instead of empty output.
- **Tests**: added `CodeSignInspectorTests` (6 tests); existing AppBundlePreparer / LLDBProcessState / CrashReportParser suites still pass.

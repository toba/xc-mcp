---
# orz-ud2
title: debug_attach_sim should support macOS apps by bundle_id (not just simulators)
status: completed
type: feature
priority: normal
created_at: 2026-02-26T00:11:26Z
updated_at: 2026-02-26T00:30:00Z
sync:
    github:
        issue_number: "140"
        synced_at: "2026-02-26T00:30:35Z"
---

## Problem

`debug_attach_sim` requires a simulator UDID when using `bundle_id`. For macOS app debugging, you must manually find the PID via `pgrep` and pass it — there's no convenient bundle_id-based attach for native macOS apps.

## Observed During

Thesis session: trying to attach LLDB to a running macOS app (`com.thesisapp.debug`) to set a breakpoint on `_NSDetectedLayoutRecursion`. The tool rejected the call because no simulator was specified.

## Suggestion

Either:
- Allow `debug_attach_sim` to work without a simulator when the target is a macOS app (resolve PID from bundle_id via `NSRunningApplication` or `pgrep`)
- Or add a `debug_attach_macos` tool (or rename `debug_attach_sim` to `debug_attach` and make it platform-aware)

## TODO

- [x] Support attaching to macOS apps by bundle_id without requiring simulator

## Summary of Changes

Modified `DebugAttachSimTool` to support macOS apps by bundle_id without requiring a simulator:

- When `bundle_id` is provided and no simulator is available (none passed, none in session), the tool now resolves the PID via `pgrep` and attaches directly — no simulator required
- Split `findAppPID` into `findSimulatorAppPID` and `findMacOSAppPID` for clarity
- Updated tool description and simulator parameter docs to explain macOS usage
- Error message for macOS apps suggests `build_run_macos` or `launch_mac_app`

**File changed:** `Sources/Tools/Debug/DebugAttachSimTool.swift`

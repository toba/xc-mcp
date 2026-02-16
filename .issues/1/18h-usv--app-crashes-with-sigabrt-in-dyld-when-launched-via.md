---
# 18h-usv
title: App crashes with SIGABRT in dyld when launched via LLDB process launch
status: completed
type: bug
priority: normal
created_at: 2026-02-15T22:05:26Z
updated_at: 2026-02-15T23:01:04Z
sync:
    github:
        issue_number: "9"
        synced_at: "2026-02-15T23:05:21Z"
---

## Problem

When `build_debug_macos` launches a macOS app via LLDB's `process launch` command, the app crashes with `SIGABRT` in `dyld` (`__abort_with_payload`). The same app launches fine via `open` or Xcode's Run button.

## Steps to Reproduce

1. Build Thesis app with `build_debug_macos(project_path: "Thesis.xcodeproj", scheme: "Standard")`
2. Build succeeds, LLDB launches the process
3. App window appears briefly, then crashes

## Observed Behavior

```
Process 50481 stopped
* thread #1, stop reason = signal SIGABRT
    frame #0: 0x0000000192976660 dyld`__abort_with_payload + 8
```

The app is visible on screen momentarily before crashing.

## Expected Behavior

App should launch and remain running under the debugger, like Xcode's Run button.

## Analysis

LLDB's `process launch` differs from `open` / Launch Services in several ways:
- Does not go through Launch Services (no proper app activation)
- May not inherit the correct sandbox/entitlement context
- The executable is launched directly, not via the app bundle wrapper

## Possible Fixes

- [ ] Investigate using `process launch` with `--working-dir` set to the app bundle
- [ ] Try launching via `open` + attaching via LLDB instead of `process launch`
- [ ] Check if `DYLD_FRAMEWORK_PATH` / `DYLD_LIBRARY_PATH` env vars conflict with the app's embedded frameworks
- [ ] Get full dyld crash reason (use `thread backtrace` and `register read` on the SIGABRT frame)
- [ ] Compare Xcode's launch environment/arguments with our LLDB launch to find differences


## Summary of Changes

Fixed SIGABRT in dyld by switching from `process launch` to `open` + LLDB `--waitfor` attach. Also fixed non-embedded frameworks with absolute install names by symlinking them into the bundle and rewriting references to `@rpath/`.

### Root causes identified
1. **Sandbox**: `process launch` bypasses Launch Services, so sandbox isn't initialized for sandboxed apps
2. **DYLD_FRAMEWORK_PATH stripped**: hardened runtime + SIP strips DYLD_* env vars, even via LSEnvironment
3. **Absolute install names**: framework targets with `INSTALL_PATH = /Library/Frameworks` produce absolute references that dyld can't resolve without DYLD_FRAMEWORK_PATH
4. **JSON parsing bug**: `showBuildSettings` returns JSON (`-json` flag), but extraction methods parsed text format — `BUILT_PRODUCTS_DIR` was always nil

### Changes
- `Sources/Core/LLDBRunner.swift`: Added `open` + `--waitfor` attach flow (`createOpenAndAttachSession`, `launchViaOpenAndAttach`)
- `Sources/Tools/Debug/BuildDebugMacOSTool.swift`:
  - Fixed `extractBuildSetting`/`extractAppPath` to parse JSON build settings
  - Added `prepareAppForDebugLaunch`: symlinks frameworks into bundle, rewrites absolute install names with `install_name_tool`, re-signs
  - Replaced `launchProcess()` with `launchViaOpenAndAttach()`

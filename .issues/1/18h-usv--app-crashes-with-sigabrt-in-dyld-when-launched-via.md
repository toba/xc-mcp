---
# 18h-usv
title: App crashes with SIGABRT in dyld when launched via LLDB process launch
status: ready
type: bug
priority: normal
created_at: 2026-02-15T22:05:26Z
updated_at: 2026-02-15T22:05:26Z
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

---
# qc1-f6z
title: 'build_run_macos / launch_mac_app: set DYLD_FRAMEWORK_PATH for debug builds'
status: completed
type: bug
priority: high
tags:
    - macOS
created_at: 2026-02-26T01:03:47Z
updated_at: 2026-02-26T01:16:19Z
sync:
    github:
        issue_number: "141"
        synced_at: "2026-02-26T01:16:50Z"
---

## Problem

When building with `build_macos` and then launching with `launch_mac_app` (or using `build_run_macos`), the app crashes with:

```
Library not loaded: @rpath/Ghost.framework/Versions/A/Ghost
Reason: tried: '…/ReexportedBinaries/Ghost.framework/…' (no such file)
```

Xcode automatically sets `DYLD_FRAMEWORK_PATH` to the DerivedData build products directory when launching debug builds. The xc-mcp launch tools don't do this, so frameworks that exist in DerivedData but aren't embedded in the app bundle can't be found at runtime.

## Workaround

Manual launch with:
```bash
DYLD_FRAMEWORK_PATH="…/DerivedData/…/Build/Products/Debug" "/path/to/App.app/Contents/MacOS/App"
```

## Suggested Fix

When launching a debug build, automatically set `DYLD_FRAMEWORK_PATH` to the build products directory (same directory containing the .app bundle).

## TODO

- [x] Set DYLD_FRAMEWORK_PATH in launch_mac_app when launching from DerivedData
- [x] Set DYLD_FRAMEWORK_PATH in build_run_macos
- [x] Set DYLD_FRAMEWORK_PATH in build_debug_macos


## Summary of Changes

Extracted the framework preparation logic from `BuildDebugMacOSTool` into a shared `AppBundlePreparer` utility in `Sources/Core/`. This utility symlinks non-embedded frameworks/dylibs from `BUILT_PRODUCTS_DIR` into the app bundle's `Contents/Frameworks/`, rewrites absolute `/Library/Frameworks/` install names to `@rpath/`, and re-signs the bundle.

Note: `DYLD_FRAMEWORK_PATH` cannot actually be set via the `open` command (Launch Services strips `DYLD_*` for hardened-runtime apps). The symlink+rewrite approach is what Xcode's build system effectively does and works reliably.

**Files changed:**
- `Sources/Core/AppBundlePreparer.swift` — new shared utility
- `Sources/Tools/MacOS/BuildRunMacOSTool.swift` — calls `AppBundlePreparer.prepare` after build
- `Sources/Tools/MacOS/LaunchMacAppTool.swift` — calls `AppBundlePreparer.prepare` when app path is in DerivedData
- `Sources/Tools/Debug/BuildDebugMacOSTool.swift` — delegates to shared `AppBundlePreparer` instead of private methods

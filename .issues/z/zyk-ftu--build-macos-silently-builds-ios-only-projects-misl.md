---
# zyk-ftu
title: build_macos silently builds iOS-only projects — misleading output and no warning
status: completed
type: bug
priority: low
created_at: 2026-03-13T23:55:53Z
updated_at: 2026-03-14T00:00:22Z
sync:
    github:
        issue_number: "207"
        synced_at: "2026-03-14T00:14:50Z"
---

## Context

During a session working on an iOS-only app (Gerg — Concept2 PM5 rowing games), the project's .mcp.json only configured xc-build, xc-project, xc-swift, and xc-debug servers. The xc-simulator server was not configured, so no iOS simulator build/run/test tools were available.

The agent used `build_macos` to verify the iOS app compiled. It succeeded, and the output said:

> Build succeeded for scheme 'Gerg' on macOS

But the project has `SUPPORTED_PLATFORMS = "iphoneos iphonesimulator"` and `SUPPORTS_MACCATALYST = NO` — it's iOS-only.

## Problems

1. **Misleading success message**: "Build succeeded ... on macOS" implies it was built for macOS, but the app is iOS-only. xcodebuild likely picked a simulator destination automatically, but the output doesn't reflect that.

2. **No warning about missing xc-simulator**: When an agent uses build_macos on an iOS-only project and xc-simulator tools aren't available, there's no hint that the agent should be using simulator tools instead. The agent has no way to know it's using the wrong tool.

## Observed During

Gerg project session (2026-03-13). The agent needed to verify Swift compilation after rewriting PM5 BLE parsing. Used `build_macos` because it was the only build tool available. Worked, but the experience was confusing.

## Possible Fixes

- `build_macos` could detect iOS-only projects and either warn or suggest using xc-simulator tools
- The success message could include the actual destination used (e.g., "iPhone 16 Simulator" vs "macOS")
- Or: `build_macos` could refuse to build iOS-only projects with a helpful error pointing to `build_sim`

## Summary of Changes

Added platform validation to all four macOS-targeted tools (`build_macos`, `build_run_macos`, `test_macos`, `build_debug_macos`). Before building, each tool now queries `SUPPORTED_PLATFORMS` from the scheme's build settings and rejects iOS-only projects with a clear error message:

> Scheme 'Gerg' does not support macOS (supported platforms: iphoneos, iphonesimulator). Use the xc-simulator server's build/test tools for iOS projects, or add Mac Catalyst support in the Xcode project.

**Files changed:**
- `Sources/Core/BuildSettingExtractor.swift` — added `validateMacOSSupport()` static method
- `Sources/Tools/MacOS/BuildMacOSTool.swift` — call `validateMacOSSupport()` before building
- `Sources/Tools/MacOS/BuildRunMacOSTool.swift` — call `validateMacOSSupport()` before building
- `Sources/Tools/MacOS/TestMacOSTool.swift` — call `validateMacOSSupport()` before testing
- `Sources/Tools/Debug/BuildDebugMacOSTool.swift` — inline platform check after existing `showBuildSettings` call (avoids redundant query)

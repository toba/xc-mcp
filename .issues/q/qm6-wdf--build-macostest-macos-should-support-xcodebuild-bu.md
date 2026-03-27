---
# qm6-wdf
title: build_macos/test_macos should support xcodebuild build setting overrides
status: completed
type: feature
priority: high
tags:
    - xc-build
created_at: 2026-03-27T00:14:19Z
updated_at: 2026-03-27T01:06:15Z
sync:
    github:
        issue_number: "243"
        synced_at: "2026-03-27T01:08:28Z"
---

## Problem

There is no way to pass xcodebuild build setting overrides (e.g. \`SWIFT_ENABLE_EXPLICIT_MODULES=NO\`) through \`build_macos\`, \`test_macos\`, or any other build/test tool. This is needed to work around Xcode/compiler bugs where a project-level pbxproj setting is ignored at build time.

## Context: The Thesis Project Case

In Xcode 26, the build setting for Swift explicit modules was renamed:

- **Xcode 16**: \`_EXPERIMENTAL_SWIFT_EXPLICIT_MODULES\` (experimental, off by default)
- **Xcode 26**: \`SWIFT_ENABLE_EXPLICIT_MODULES\` (production, **on by default**)
- The old \`SWIFT_EXPLICIT_MODULES\` used in many projects is **silently ignored**

Source: Xcode 26 Beta 2 Release Notes — *"Starting from Xcode 26, Swift explicit modules will be the default mode for building all Swift targets. Projects experiencing severe issues can disable this by setting SWIFT_ENABLE_EXPLICIT_MODULES=NO."*

The Thesis project has code (parameter pack dual-pack join overloads) that triggers a Swift compiler bug under explicit modules — the compiler reports "cannot convert value of type X to expected argument type X" where both types are identical. This bug only manifests under Xcode's explicit module build mode, not SPM's \`-explicit-module-build\`.

### What happens

1. \`SWIFT_ENABLE_EXPLICIT_MODULES = NO\` is set at project level in pbxproj (all 3 configs: Debug, Release, Beta)
2. \`xcodebuild -showBuildSettings\` correctly reports \`SWIFT_ENABLE_EXPLICIT_MODULES = NO\`
3. \`mcp build_macos\` → **fails** with 7 parameter pack errors + 802 cascading linker errors (Core module fails to build, all downstream modules fail to link)
4. Raw \`xcodebuild build ... SWIFT_ENABLE_EXPLICIT_MODULES=NO\` (CLI override appended as a positional argument) → **succeeds** (no parameter pack errors)

The CLI override takes highest precedence in xcodebuild's setting resolution hierarchy, bypassing whatever mechanism is causing the pbxproj setting to be ignored during actual compilation.

### The MCP gap

\`XcodebuildRunner.build()\` constructs args as:

\`\`\`
-project <path> -scheme <scheme> -destination <dest> -configuration <config> <action>
\`\`\`

There is no way to append build setting overrides like \`SETTING=VALUE\` which xcodebuild supports as trailing positional arguments. The \`additionalArguments\` parameter exists on the \`build()\` method but is never exposed through the MCP tool interface.

## Proposed Solution

Add an optional \`build_settings\` parameter (object/dictionary) to \`build_macos\`, \`test_macos\`, and other build/test tools. Each key-value pair would be appended as \`KEY=VALUE\` positional arguments to the xcodebuild invocation.

Example MCP call:
\`\`\`json
{
  "build_settings": {
    "SWIFT_ENABLE_EXPLICIT_MODULES": "NO"
  }
}
\`\`\`

This would result in xcodebuild being invoked as:
\`\`\`
xcrun xcodebuild -project ... -scheme ... build SWIFT_ENABLE_EXPLICIT_MODULES=NO
\`\`\`

### Alternative: Session-level build settings

Could also be set via \`set_session_defaults\` so they persist across calls, similar to how \`env\` already works. The \`env\` parameter sets environment variables for the process, but build setting overrides are different — they're positional arguments to xcodebuild, not environment variables.

## Workaround

No longer needed — `build_settings` parameter is now available on all build/test tools.

## Affected Tools

All tools that call \`XcodebuildRunner.build()\` or \`XcodebuildRunner.test()\`:
- \`build_macos\`
- \`build_run_macos\`  
- \`test_macos\`
- \`build_sim\`
- \`build_run_sim\`
- \`test_sim\`
- \`build_debug_macos\`

## Implementation Notes

\`XcodebuildRunner.build()\` already has an \`additionalArguments: [String]\` parameter that is passed through to xcodebuild. The change is to:
1. Add \`build_settings\` to the MCP tool schema (object type, optional)
2. Convert to \`["KEY=VALUE", ...]\` array
3. Pass as \`additionalArguments\` to the runner

The \`additionalArguments\` parameter is already appended after the action verb in the args array, which is exactly where xcodebuild expects build setting overrides.


## Summary of Changes

Added `build_settings` parameter (object/dictionary) to all tools that invoke xcodebuild build or test. Each key-value pair is appended as a `KEY=VALUE` positional argument to the xcodebuild invocation, taking highest precedence in setting resolution.

### Files Changed

- **Sources/Core/ArgumentExtraction.swift** — added `getStringDictionary()`, `buildSettingOverrides()`, and `buildSettingsSchemaProperty` reusable schema
- **Sources/Core/TestToolHelper.swift** — added `additionalArguments` parameter to `runAndFormat()`
- **Sources/Tools/MacOS/BuildMacOSTool.swift** — added `build_settings` schema + pass to runner
- **Sources/Tools/MacOS/BuildRunMacOSTool.swift** — added `build_settings` schema + pass to runner
- **Sources/Tools/MacOS/TestMacOSTool.swift** — added `build_settings` schema + pass to runner
- **Sources/Tools/Debug/BuildDebugMacOSTool.swift** — added `build_settings` schema + pass to runner
- **Sources/Tools/Simulator/BuildSimTool.swift** — added `build_settings` schema + pass to runner
- **Sources/Tools/Simulator/BuildRunSimTool.swift** — added `build_settings` schema + pass to runner
- **Sources/Tools/Simulator/TestSimTool.swift** — added `build_settings` schema + pass to runner
- **Sources/Tools/Device/BuildDeviceTool.swift** — added `build_settings` schema + pass to runner
- **Sources/Tools/Device/BuildDeployDeviceTool.swift** — added `build_settings` schema + pass to runner
- **Sources/Tools/Device/TestDeviceTool.swift** — added `build_settings` schema + pass to runner



## Update: Not a missing feature — the setting IS being ignored

Further testing shows that `xcrun xcodebuild -project ... -scheme Standard -destination platform=macOS -configuration Debug build` (the exact command the MCP tool constructs) works correctly from the shell — no parameter pack errors, target-level `SWIFT_ENABLE_EXPLICIT_MODULES = NO` is respected.

The bug is specific to how the MCP tool invokes the process (via Swift `Subprocess`). Something in the `Subprocess.run(.name("xcrun"), arguments: ["xcodebuild"] + args, environment: environment)` call is causing the build setting to be ignored. Possible causes:
- Environment variables stripped or different in `Subprocess` context
- Working directory difference
- Process inheritance difference
- DerivedData cache corruption specific to MCP server process

The `build_settings` override feature is still useful as a general-purpose workaround, but the root cause is the MCP tool's process invocation not matching shell behavior.



## Investigation Results (2026-03-26)

### Key Finding: NOT an xc-mcp bug

The shell build fails identically to the MCP build. The original claim that "the identical command works from the shell" was incorrect.

### Test Matrix

| Test | Result |
|------|--------|
| MCP `build_macos` (no overrides) | FAIL — 5 param pack + 2 @SQLTable + 802 linker |
| Shell `xcrun xcodebuild ... build` (no overrides) | FAIL — identical errors |
| MCP with `SWIFT_ENABLE_EXPLICIT_MODULES=NO` | FAIL — same errors |
| MCP with both `SWIFT_ENABLE_EXPLICIT_MODULES=NO` + `COMPILATION_CACHE_ENABLE_CACHING=NO` | FAIL — same errors |
| Shell with both overrides + clean DerivedData | FAIL — same errors |
| All tests confirm: `export SWIFT_ENABLE_EXPLICIT_MODULES\=NO` IS applied | Overrides work, errors persist |

### Root Cause Analysis

1. **Parameter pack errors are a Swift 6.2/Xcode 26.4 compiler bug** — NOT caused by explicit modules. The errors ("cannot convert value of type X to expected argument type X" where both types are identical) occur regardless of explicit modules setting.

2. **Compilation caching overrides explicit modules** — `COMPILATION_CACHE_ENABLE_CACHING=YES` (set at project level in Thesis) forces `SWIFT_ENABLE_EXPLICIT_MODULES=YES` even when the Core target sets it to `NO`. xcodebuild emits: `warning: swift compiler caching requires explicit module build (SWIFT_ENABLE_EXPLICIT_MODULES=YES)`. However, this is a **separate issue** from the parameter pack errors.

3. **`SWIFT_ENABLE_EXPLICIT_MODULES=NO` is on Core target only, NOT project level** — project-level build settings don't have it. In Xcode 26 where the default is YES, this means all other targets build with explicit modules.

### Build Settings Audit (Thesis.xcodeproj)

| Setting | Level | Value |
|---------|-------|-------|
| `COMPILATION_CACHE_ENABLE_CACHING` | Project (all configs) | `YES` |
| `SWIFT_ENABLE_EXPLICIT_MODULES` | Core target (all configs) | `NO` |
| `SWIFT_ENABLE_EXPLICIT_MODULES` | Project level | NOT SET (Xcode 26 default = YES) |

### The `build_settings` Feature

The `build_settings` parameter added in commit d9feb8d works correctly — overrides are passed as positional args and xcodebuild applies them. However, the parameter pack errors are not fixed by any combination of overrides because they're a Swift compiler bug, not a build settings issue.

### References

- Xcode 26 Release Notes: "Starting from Xcode 26, Swift explicit modules will be the default mode for building all Swift targets."
- Compilation caching: "Compilation caching has been introduced as an opt-in feature" — it requires `SWIFT_ENABLE_EXPLICIT_MODULES=YES`
- The 39 build failures break down as: 5 parameter pack type errors + 2 @SQLTable macro crashes + 32 cascading linker errors (Core fails → all dependents fail to link)

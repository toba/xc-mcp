---
# 1hr-ekg
title: New targets should default ONLY_ACTIVE_ARCH=YES for Debug
status: completed
type: bug
priority: normal
created_at: 2026-03-01T06:46:03Z
updated_at: 2026-03-01T07:04:33Z
sync:
    github:
        issue_number: "151"
        synced_at: "2026-03-01T07:04:37Z"
---

## Context

When creating targets with `add_target` or `add_app_extension`, the `ONLY_ACTIVE_ARCH` build setting is not set, defaulting to `NO`. This means Debug builds compile for all architectures (arm64 + x86_64).

## Problem

When a target depends on a local SPM package, the SPM package only builds for the active architecture. The Xcode target then fails to find the module for the non-active architecture (x86_64 on Apple Silicon), producing:

```
Unable to find module dependency: 'Swiftiomatic'
lstat(.../Objects-normal/x86_64/SwiftiomaticExtension.swiftmodule): No such file or directory
```

## Expected

`ONLY_ACTIVE_ARCH = YES` should be set for Debug configuration on all new targets. This matches Xcode's default for new projects created through the GUI and avoids unnecessary cross-compilation during development.

## Workaround

```
set_build_setting(target, configuration: "Debug", setting_name: "ONLY_ACTIVE_ARCH", setting_value: "YES")
```

Related: z23-qhd (other xc-project tool issues from same session)


## Summary of Changes

Added `ONLY_ACTIVE_ARCH = YES` to Debug build settings in all target-creation tools:

- `AddTargetTool` — `debugSettings` dictionary
- `AddAppExtensionTool` — `debugSettings` dictionary
- `ScaffoldIOSProjectTool` — `createAppTargetBuildSettings(debug: true)`
- `ScaffoldMacOSProjectTool` — `createAppTargetBuildSettings(debug: true)`

This matches Xcode's default behavior for new projects and prevents cross-compilation failures when targets depend on SPM packages that only build for the active architecture.

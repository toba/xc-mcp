---
# z23-qhd
title: Fix xc-project MCP tool issues found during Swiftiomatic extension setup
status: completed
type: bug
priority: high
created_at: 2026-03-01T06:28:44Z
updated_at: 2026-03-01T06:36:40Z
sync:
    github:
        issue_number: "150"
        synced_at: "2026-03-01T06:37:51Z"
---

## Context

While using xc-project tools to create an Xcode project for a Source Editor Extension (host app + extension target + local SPM package), several issues were found.

## Issues

### 1. `create_xcodeproj` creates orphan default target
When creating a project, it creates a default application target with the project name (e.g. "Swiftiomatic") that isn't needed and must be manually removed with `remove_target`. The tool should either skip the default target or let the caller specify what to create.

### 2. `add_swift_package` doesn't add product to Frameworks build phase
When adding a local SPM package with `target_name` and `product_name`, the tool correctly sets `packageProductDependencies` on the native target, but does NOT add a `PBXBuildFile` entry to the target's `PBXFrameworksBuildPhase`. This causes "Unable to find module dependency" errors at build time because the package is resolved and built, but never linked into the consuming target.

Expected: a `PBXBuildFile` referencing the package product should be added to the target's Frameworks build phase, similar to how `add_framework` adds its framework.

### 3. `add_framework` uses wrong sourceTree for developer frameworks
Adding XcodeKit (which lives in `$(DEVELOPER_FRAMEWORKS_DIR)`) creates:
```
path = System/Library/Frameworks/XcodeKit.framework; sourceTree = SDKROOT;
```
This is incorrect — XcodeKit is at `/Applications/Xcode.app/Contents/Developer/Library/Frameworks/XcodeKit.framework`, not in the SDK. The tool should detect developer frameworks and use `sourceTree = DEVELOPER_DIR` with the correct relative path, or at minimum the `FRAMEWORK_SEARCH_PATHS` should include `$(DEVELOPER_FRAMEWORKS_DIR)`.

Workaround: manually set `FRAMEWORK_SEARCH_PATHS = $(inherited) $(DEVELOPER_FRAMEWORKS_DIR)`.

### 4. `add_target` sets `TARGETED_DEVICE_FAMILY = 1` for macOS targets
When creating a macOS target with `platform: macOS`, the build settings include `TARGETED_DEVICE_FAMILY = 1` (iPhone). This setting is iOS-specific and should not be set for macOS targets.

### 5. Missing `ALWAYS_SEARCH_USER_PATHS = NO` default
Neither `add_target` nor `add_app_extension` sets `ALWAYS_SEARCH_USER_PATHS = NO`, which causes Xcode to emit deprecation warnings:
> "Traditional headermap style is no longer supported; please migrate to using separate headermaps and set 'ALWAYS_SEARCH_USER_PATHS' to NO."

This should default to NO for all new targets.

## Reproduction

```
create_xcodeproj → creates unwanted default target
add_target (macOS app) → TARGETED_DEVICE_FAMILY = 1
add_app_extension (custom, macOS) → no ALWAYS_SEARCH_USER_PATHS
add_swift_package (local, with target_name) → missing Frameworks build phase entry
add_framework (XcodeKit) → wrong sourceTree for developer framework
```


## Summary of Changes

### 1. `create_xcodeproj` — skip orphan default target
Added `skip_default_target` boolean parameter. When true, the project is created with no targets, allowing callers to add targets separately via `add_target`.

### 2. `add_swift_package` — add product to Frameworks build phase
When adding a package product to a target, a `PBXBuildFile` referencing the `XCSwiftPackageProductDependency` is now added to the target's Frameworks build phase (creating the phase if needed). This ensures the package is actually linked, not just resolved.

### 3. `add_framework` — developer framework handling
Developer frameworks (XcodeKit, XCTest, SpriteKit, SceneKit) now use `sourceTree = DEVELOPER_DIR` with `path = Library/Frameworks/` instead of `SDKROOT`. Also automatically sets `FRAMEWORK_SEARCH_PATHS = $(inherited) $(DEVELOPER_FRAMEWORKS_DIR)` on the target.

### 4. `add_target` — no TARGETED_DEVICE_FAMILY for macOS
`TARGETED_DEVICE_FAMILY` is no longer set for macOS targets. It is only set for iOS ("1,2"), tvOS, and watchOS.

### 5. `add_target` / `add_app_extension` — ALWAYS_SEARCH_USER_PATHS = NO
Both tools now set `ALWAYS_SEARCH_USER_PATHS = NO` in all build configurations, preventing Xcode deprecation warnings. Also fixed `add_app_extension` to omit `TARGETED_DEVICE_FAMILY` for macOS.

### Tests
Added 5 new tests covering all fixes (42 total across the 5 tool test suites, all passing).

---
# pk9-npt
title: Integration test previewCapture_IceCubesApp fails
status: completed
type: bug
priority: normal
created_at: 2026-02-18T01:30:08Z
updated_at: 2026-02-18T03:53:40Z
sync:
    github:
        issue_number: "67"
        synced_at: "2026-02-18T01:30:12Z"
---

The IceCubesApp preview capture integration test fails because swift-frontend crashes during compilation of the IceCubesApp fixture. Blocked by the SILGen crash bug.

## Root Cause

The preview host target injected into IceCubesApp.xcodeproj had no `IPHONEOS_DEPLOYMENT_TARGET` set when the source file belonged to a local Swift package (no native target). This caused:

1. iOS Simulator build to fail (deployment target defaulted to ancient version, incompatible with packages requiring iOS 18+)
2. Fallback to macOS build, which also failed (deployment target defaulted to 10.13, below SPM package requirements)
3. UIKit and other iOS-only modules unavailable on macOS

The SILGen crash (tt6-eyu) was a separate issue that was resolved by pinning the simulator to iOS 18.x instead of the iOS 26 beta.

## Fix

- Parse the iOS deployment target from the local package's `Package.swift` (e.g. `.iOS(.v18)` → `18.0`)
- Return it from `findLocalPackageModule` alongside the module/product names
- Apply it to the injected preview host target's `IPHONEOS_DEPLOYMENT_TARGET` build setting
- Added `extractProjectDeploymentTarget` fallback that checks project-level settings and app targets

## Summary of Changes

- `PreviewCaptureTool.swift`: Added `parseIOSDeploymentTarget(packageDir:)` to extract platform version from Package.swift, `extractProjectDeploymentTarget(from:)` for project-level fallback, updated `findLocalPackageModule` to return deployment target
- All 431 tests pass including `previewCapture_IceCubesApp`

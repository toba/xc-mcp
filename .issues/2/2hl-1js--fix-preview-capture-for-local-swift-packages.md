---
# 2hl-1js
title: Fix preview_capture for local Swift packages
status: completed
type: bug
priority: normal
created_at: 2026-02-18T01:58:23Z
updated_at: 2026-02-18T02:03:18Z
sync:
    github:
        issue_number: "71"
        synced_at: "2026-02-18T03:57:20Z"
---

findOwningTarget returns nil for files in local Swift packages, causing build failures. Need to add findLocalPackageModule fallback and local package dependency linking in injectTarget.

## Summary of Changes

### PreviewCaptureTool.swift
- Added `findLocalPackageModule` method that checks both `XCLocalSwiftPackageReference` entries (Xcode 15+) and wrapper file references for local package ownership
- Added `inferModuleName` helper that extracts target name from `Sources/<TargetName>/...` path convention
- Updated `execute()` flow to call `findLocalPackageModule` as fallback when `findOwningTarget` returns nil
- Updated `injectTarget` to accept `localPackageProductName` parameter and add `XCSwiftPackageProductDependency` when set
- Added `CODE_SIGNING_ALLOWED=NO` to build args to prevent macOS fallback from failing on signing certs

### scripts/fetch-fixtures.sh (already done in prior commit)
- IceCubesApp pinned to tag 2.1.3
- xcconfig template copy logic added

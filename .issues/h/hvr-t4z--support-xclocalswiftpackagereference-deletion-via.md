---
# hvr-t4z
title: Support XCLocalSwiftPackageReference deletion via XcodeProj 9.9.0
status: completed
type: feature
priority: normal
created_at: 2026-02-24T18:29:37Z
updated_at: 2026-02-24T18:48:53Z
sync:
    github:
        issue_number: "108"
        synced_at: "2026-02-24T18:57:45Z"
---

XcodeProj 9.9.0 (released 2026-02-24) adds delete support for `XCLocalSwiftPackageReference` in `PBXObjects.swift`.

## Context

- Upstream PR: tuist/xcodeproj#1044
- Release: tuist/xcodeproj 9.9.0 (`77ee072`)
- Our current pin: ≥9.7.2

## Tasks

- [x] Update XcodeProj dependency to ≥9.9.0 in Package.swift
- [x] Audit existing project tools in Sources/Tools/Project/ for local Swift package reference handling
- [x] Add tool(s) for deleting local Swift package references if not already covered
- [x] Ensure add/list/show tools handle `XCLocalSwiftPackageReference` consistently
- [x] Add tests for local package reference CRUD operations


## Summary of Changes

### Package.swift
- Bumped XcodeProj dependency from ≥9.7.2 to ≥9.9.0 (resolves to 9.9.0)
- This brings `XCLocalSwiftPackageReference` delete support in `PBXObjects`

### AddSwiftPackageTool.swift
- Added `package_path` parameter for local packages (mutually exclusive with `package_url`)
- `requirement` is now only required for remote packages
- Refactored into `addRemotePackage` / `addLocalPackage` private methods
- Extracted `addProductToTarget` helper shared by both paths
- Duplicate detection for local packages by `relativePath`

### RemoveSwiftPackageTool.swift
- Added `package_path` parameter for local packages (mutually exclusive with `package_url`)
- Refactored into `removeRemotePackage` / `removeLocalPackage` private methods
- Extracted `removeProductDependencies` helper for remote package cleanup
- Local package deletion now correctly calls `pbxproj.delete(object:)` which is supported in XcodeProj 9.9.0

### ListSwiftPackagesTool.swift
- No changes needed — already listed both remote and local packages

### Tests (8 new tests)
- AddSwiftPackageToolTests: add local package, duplicate local, local to target, both URL+path error, neither URL nor path error
- RemoveSwiftPackageToolTests: remove local package, remove non-existent local, both URL+path error
- Updated description expectations and param validation tests for new tool schemas
- All 28 SwiftPackage tests pass, 576/578 full suite pass (2 pre-existing integration failures)

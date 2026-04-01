---
# fwk-6tv
title: remove_package_product corrupts pbxproj — PBXContainerItemProxy buildPhase crash
status: completed
type: bug
priority: critical
created_at: 2026-03-31T23:55:49Z
updated_at: 2026-03-31T23:57:37Z
sync:
    github:
        issue_number: "249"
        synced_at: "2026-04-01T00:15:35Z"
---

GitHub issue #248. `remove_package_product` corrupts the Xcode project file by leaving dangling references when deleting SPM package product dependencies.

## Steps to Reproduce
1. Have a target with packageProductDependencies (e.g. SwiftSyntax, SwiftParser)
2. Call remove_package_product for each product
3. Project becomes unreadable by Xcode

## Root Cause
When Xcode GUI adds SPM dependencies, it creates `PBXTargetDependency` entries with `productRef` pointing to the `XCSwiftPackageProductDependency`. The tool deleted the product dependency object but left these `PBXTargetDependency` entries dangling, corrupting the pbxproj.

## Tasks
- [x] Identify root cause
- [x] Fix RemovePackageProductTool.swift
- [x] Add tests
- [x] Verify fix


## Summary of Changes

Added cleanup of `PBXTargetDependency` entries (lines 99-105 in RemovePackageProductTool.swift) that reference the product being removed. These are created by Xcode GUI but not by our AddPackageProductTool, so the removal path didn't account for them. Added test covering this scenario.

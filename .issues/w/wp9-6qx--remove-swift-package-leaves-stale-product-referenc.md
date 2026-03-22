---
# wp9-6qx
title: remove_swift_package leaves stale product references in pbxproj
status: completed
type: bug
priority: high
created_at: 2026-03-22T02:15:58Z
updated_at: 2026-03-22T02:21:01Z
sync:
    github:
        issue_number: "234"
        synced_at: "2026-03-22T02:23:09Z"
---

When removing a local Swift Package via `remove_swift_package`, the package reference is removed but the product reference (`PBXSwiftPackageProductDependency`) and its `PBXBuildFile` entry remain in the project.

## Reproduction

1. Add a local package: `add_swift_package(package_path: "Core/Macros", product_name: "StorageMacros", target_name: "Core")`
2. Remove it: `remove_swift_package(package_path: "Core/Macros")`
3. Grep the pbxproj: `grep StorageMacros project.pbxproj` — still 5 references

## Stale entries after removal

```
PBXBuildFile:     /* StorageMacros in Frameworks */
Frameworks list:  /* StorageMacros in Frameworks */
packageProductDependencies: /* StorageMacros */
PBXSwiftPackageProductDependency: /* StorageMacros */ = { productName = StorageMacros; }
```

## Expected

All references to the package product should be removed when the package is removed.

## Impact

Leaves the project in an unbuildable state ("Missing package product 'StorageMacros'"). Manual pbxproj editing or re-adding the package under a different name requires workarounds.

## Summary of Changes

Added `removeBuildFiles` helper to `RemoveSwiftPackageTool` that removes `PBXBuildFile` entries referencing the product dependency from all build phases. Called from both the remote package (`removeProductDependencies`) and local package removal paths. Added test for local package build file cleanup and strengthened existing remote package test to verify no stale build files remain.

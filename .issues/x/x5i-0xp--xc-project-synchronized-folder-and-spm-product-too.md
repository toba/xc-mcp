---
# x5i-0xp
title: 'xc-project: synchronized folder and SPM product tooling gaps'
status: review
type: bug
priority: high
created_at: 2026-03-21T03:50:48Z
updated_at: 2026-03-21T04:14:19Z
sync:
    github:
        issue_number: "227"
        synced_at: "2026-03-21T04:15:28Z"
---

Multiple issues discovered during a Thesis session where I needed to add `MockHTTPTransport.swift` to the `TestSupport` target and add `HTTPTypes` SPM product as a dependency.

## Issues

### 1. `list_files` misrepresents `membershipExceptions` as "excludes"

When a synchronized folder has a `PBXFileSystemSynchronizedBuildFileExceptionSet` with `membershipExceptions`, `list_files` labels them as "excludes: file1, file2, ...". But `membershipExceptions` means these files are **included** in the target as exceptions — the opposite of what "excludes" suggests.

This caused significant confusion: I thought `MockHTTPTransport.swift` was in the TestSupport target (not listed in "excludes") when it actually wasn't (not listed in `membershipExceptions` = not included).

**Expected**: The output should clarify the semantics. Something like "included via exceptions: file1, file2" or show the effective membership (which files ARE compiled) rather than the raw exception list with a misleading label.

### 2. No tool to add an existing SPM package product to a different target

`add_swift_package` adds a new remote package reference. But when a package (e.g. `swift-http-types`) is already in the project and linked to one target (Core), there's no way to add its product (`HTTPTypes`) to another target (TestSupport) via MCP tools.

Had to manually edit `project.pbxproj` to:
- Create a new `PBXBuildFile` entry
- Create a new `XCSwiftPackageProductDependency` entry  
- Add it to the target's `packageProductDependencies` array
- Add it to the target's Frameworks build phase

**Suggestion**: Add an `add_package_product` tool or extend `add_framework` to handle SPM products:
```
add_package_product(project_path, target_name, package_name, product_name)
```

### 3. `remove_synchronized_folder_exception` can't find auto-created exception sets

When Xcode auto-creates a `PBXFileSystemSynchronizedBuildFileExceptionSet` (e.g. for a new file that shouldn't be in a target), `remove_synchronized_folder_exception` fails with "No exception set found for target X on synchronized folder Y". The exception set existed at `AA00000000000000000D1B03` in the pbxproj.

Had to manually edit the pbxproj to remove the entry and its reference in the folder's `exceptions` array.

## Reproduction

1. Create a synchronized folder with files
2. Add a file that Xcode auto-excludes via membershipExceptions
3. Try `list_files` — observe misleading "excludes" label
4. Try `remove_synchronized_folder_exception` — observe "not found" error
5. Try to add an existing SPM product to a new target — no tool available


## Summary of Changes

### 1. `list_files` — fixed misleading "excludes" label

`formatSyncGroup` now takes a `targetOwnsSyncGroup` parameter:
- **Target owns folder** (`fileSystemSynchronizedGroups`): `membershipExceptions` = files NOT compiled. Label: "membership exceptions — not compiled: ..."
- **Exception-only association**: `membershipExceptions` = files that ARE compiled. Label: "membership exceptions — compiled as exceptions: ..."

Disk file listing now correctly filters based on ownership semantics.

### 2. New `add_package_product` tool

Links an existing SPM product to a different target. Parameters: `project_path`, `target_name`, `product_name`. Automatically finds the package reference from other targets, creates `XCSwiftPackageProductDependency`, `PBXBuildFile`, and adds to the Frameworks build phase.

Registered in xc-project, xc-mcp (monolithic), and ServerToolDirectory.

### 3. `remove_synchronized_folder_exception` — improved target matching

- Resolves the target by name first, then matches exception sets by identity (`===`) or name
- Falls back to searching all `PBXFileSystemSynchronizedBuildFileExceptionSet` objects in the project when the sync group's resolved exceptions array doesn't contain the match
- Validates that the target exists before attempting removal

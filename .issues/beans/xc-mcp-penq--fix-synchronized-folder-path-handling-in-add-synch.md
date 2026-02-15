---
# xc-mcp-penq
title: Fix synchronized folder path handling in add_synchronized_folder
status: completed
type: bug
priority: normal
created_at: 2026-01-27T00:31:46Z
updated_at: 2026-01-27T00:34:04Z
sync:
    github:
        issue_number: "6"
        synced_at: "2026-02-15T22:08:23Z"
---

When adding a synchronized folder to a group that has a `path` attribute, the tool incorrectly creates the folder path as an absolute path from project root instead of relative to the parent group.

## Reproduction

1. Have a group `DOM` with `path = DOM`
2. Call `add_synchronized_folder(folder_path: "DOM/Sources", group_name: "DOM", target_name: "DOM")`
3. Result: Creates `PBXFileSystemSynchronizedRootGroup` with `path = DOM/Sources`
4. Expected: Should create with `path = Sources` (relative to parent group)

## Impact

The synchronized folder resolves to `DOM/DOM/Sources` on disk which doesn't exist, causing the target to have no source files.

## Fix

When the folder is added inside a group that has a `path`, calculate the relative path from that group rather than using the full `folder_path`.

**Resolution:** Fixed in `Sources/Tools/Project/AddFolderTool.swift` by:
1. Finding the target group before calculating the relative path
2. Getting the target group's full path using XcodeProj's `fullPath(sourceRoot:)` method
3. Calculating the folder path relative to the group's location when the folder is inside the group's directory

Added test `addsFolderWithRelativePathToParentGroup` in `Tests/AddFolderToolTests.swift` to verify the fix.

## Workaround

Manually edit pbxproj to change:
```
path = DOM/Sources;
```
to:
```
path = Sources;
```

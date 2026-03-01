---
# 184-2cs
title: add_file path doubling when used with groups that have a filesystem path
status: completed
type: bug
priority: high
created_at: 2026-03-01T18:16:20Z
updated_at: 2026-03-01T18:21:35Z
sync:
    github:
        issue_number: "155"
        synced_at: "2026-03-01T18:23:55Z"
---

## Bug

When `add_file` is called with a file in a group that has a `path` property (created by `create_group` with a `path` argument), the resulting `PBXFileReference` has an incorrect path that doubles up the directory structure.

### Reproduction

1. Create a group under an existing group:
   ```
   create_group(group_name: "Models", parent_group: "SwiftiomaticApp", path: "Models")
   ```
2. Add a file to that group:
   ```
   add_file(file_path: "SwiftiomaticApp/Models/AppModel.swift", group_name: "Models", target_name: "SwiftiomaticApp")
   ```
3. Build fails with:
   ```
   Build input files cannot be found: '.../Xcode/Models/SwiftiomaticApp/Models/AppModel.swift'
   ```

### Root Cause

In `AddFileTool.swift` (lines ~93–127), when creating the `PBXFileReference`:

- `sourceTree` is set to `.group` (path is relative to the group's location)
- But `path` is set to `makeRelativePath()` which returns the path relative to the **project root**, not the group
- Xcode interprets `sourceTree = <group>` by prepending the group's own `path` property, causing the double path

### Expected Behavior

`add_file` should compute the file reference path **relative to the group's filesystem location**, not the project root. When a group at `SwiftiomaticApp/` has a child group `Models` with `path: "Models"`, a file at `SwiftiomaticApp/Models/AppModel.swift` should have a file reference path of just `AppModel.swift`.

### Affected Files

- `Sources/Tools/Project/AddFileTool.swift` — file reference path computation
- `Sources/Core/PathUtility.swift` — `makeRelativePath()` doesn't account for group hierarchy

## Summary of Changes

Fixed `AddFileTool` to compute file reference paths relative to the target group's filesystem location instead of the project root:

- **`Sources/Tools/Project/AddFileTool.swift`**: Moved group lookup before file reference creation. After finding the target group, computes its full filesystem path via `fullPath(sourceRoot:)` (same pattern as `AddFolderTool`), then strips the group path prefix from the file path. This produces a path relative to the group — which is what Xcode expects when `sourceTree = .group`.
- **`Tests/TestProjectHelper.swift`**: Fixed `createTestProject` — the `testsGroup` was created but never added as a child of `mainGroup`, causing `fullPath` to fail. Also pre-existing from previous issue.
- **`Tests/AddFileToolTests.swift`**: Added regression test that creates a nested group hierarchy (`App/Models`) with `path` properties and verifies the file reference path is `AppModel.swift` (not `App/Models/AppModel.swift`).

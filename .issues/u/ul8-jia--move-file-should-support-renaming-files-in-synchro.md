---
# ul8-jia
title: move_file should support renaming files in synchronized folder exception sets
status: completed
type: feature
priority: normal
created_at: 2026-04-02T03:10:14Z
updated_at: 2026-04-02T03:16:11Z
sync:
    github:
        issue_number: "254"
        synced_at: "2026-04-02T03:20:24Z"
---

## Context

When a synchronized folder has `membershipExceptions` (files excluded from a target via `PBXFileSystemSynchronizedBuildFileExceptionSet`), the `move_file` tool cannot find or rename those entries. It reports "File not found in project" because it only searches standard `PBXFileReference` entries.

## Problem

Renaming a file that appears in a synchronized folder exception set requires a 3-step workaround:

1. `remove_synchronized_folder_exception` for the old file name
2. `add_synchronized_folder_exception` for the new file name
3. The caller must know the target name and folder path

This is error-prone and non-obvious. The `move_file` tool should handle this case automatically.

## Expected Behavior

`move_file` should:
1. Check both standard file references AND synchronized folder exception sets
2. When a file path matches an exception set entry, update the entry to the new path
3. Update all exception sets across all targets that reference the file

## Reproduction

```
# Files already renamed on disk via git mv
mcp__xc-project__move_file(
  project_path: "Thesis.xcodeproj",
  old_path: "TestSupport/Snapshots/Conformances/NSViewController.swift",
  new_path: "TestSupport/Snapshots/Conformances/NSViewController+snapshot.swift"
)
# Returns: "File not found in project: NSViewController.swift"
```

## Workaround

```
mcp__xc-project__remove_synchronized_folder_exception(folder_path: "TestSupport", target_name: "TestSupport", file_name: "Snapshots/Conformances/NSViewController.swift")
mcp__xc-project__add_synchronized_folder_exception(folder_path: "TestSupport", target_name: "TestSupport", files: ["Snapshots/Conformances/NSViewController+snapshot.swift"])
```

- [x] Extend `move_file` to search synchronized folder exception sets
- [x] Update all matching exception sets across all targets
- [x] Add test case for renaming within exception sets


## Summary of Changes

Extended `MoveFileTool.execute()` to iterate over all `PBXFileSystemSynchronizedBuildFileExceptionSet` entries in the project. When a `membershipExceptions` entry matches the old path, it is updated to the new path. The success message indicates when exception sets were updated. Added a test case that creates a project with a sync folder exception and verifies the rename.

---
# ctk-v8a
title: Synchronized folder exception operations corrupt pbxproj
status: ready
type: bug
priority: normal
created_at: 2026-04-03T22:14:08Z
updated_at: 2026-04-03T22:14:08Z
sync:
    github:
        issue_number: "256"
        synced_at: "2026-04-03T22:16:06Z"
---

The add_synchronized_folder_exception, remove_synchronized_folder_exception, add_target_to_synchronized_folder, and remove_target_from_synchronized_folder tools corrupt the pbxproj when modifying exception sets.

## Observed behavior

1. Re-creates exception sets with new IDs instead of modifying existing ones; orphans old references
2. Adds spurious fields to unrelated PBXCopyFilesBuildPhase entries (buildActionMask, runOnlyForDeploymentPostprocessing, empty dependencies)
3. Strips human-readable comments from exception set references (e.g. Exceptions for TestSupport folder in TestSupport target becomes PBXFileSystemSynchronizedBuildFileExceptionSet)
4. Collapses multi-line entries into single-line format for the synchronized root group
5. Alters membership exception lists; files get moved between exception sets incorrectly

## Steps to reproduce

1. Have a project with PBXFileSystemSynchronizedRootGroup and multiple exception sets (e.g. TestSupport folder with exceptions for TestSupport, CoreTests, and Core targets)
2. Call remove_synchronized_folder_exception to remove the entire exception set for one target
3. Call add_synchronized_folder_exception to recreate it with the same files
4. Diff the pbxproj; numerous unrelated changes appear

## Workaround

git restore the pbxproj after tool operations and make manual edits, or avoid these tools entirely.

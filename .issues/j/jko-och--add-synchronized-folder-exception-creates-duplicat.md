---
# jko-och
title: add_synchronized_folder_exception creates duplicate exception sets
status: completed
type: bug
priority: high
tags:
    - enhancement
created_at: 2026-03-12T05:04:00Z
updated_at: 2026-03-12T05:06:31Z
sync:
    github:
        issue_number: "203"
        synced_at: "2026-03-12T05:07:56Z"
---

## Context

When calling `add_synchronized_folder_exception` on a synchronized folder that already has an existing `PBXFileSystemSynchronizedBuildFileExceptionSet` for the same target, the tool creates a **second, duplicate exception set** instead of adding the file to the existing one. This leaves the pbxproj in a broken state with two exception sets targeting the same target.

## Steps to Reproduce

1. A synchronized folder (e.g. `TestSupport`) already has an exception set for target `TestSupport` with 26 files excluded
2. Call `add_synchronized_folder_exception` to add `ScaleDocumentFactory.swift` to the exclusion list for the same target
3. Result: a NEW `PBXFileSystemSynchronizedBuildFileExceptionSet` is created with only `ScaleDocumentFactory.swift`, and the root group's `exceptions` array now references both exception sets

## Expected Behavior

The file should be appended to the existing exception set's `membershipExceptions` array for that target.

## Actual Behavior

A second `PBXFileSystemSynchronizedBuildFileExceptionSet` is created targeting the same target. The root group references both:

```
exceptions = (
    962093D72EDD2B1000765575 /* original set */,
    973908416231855CDEE9A47E /* duplicate set */,
);
```

## Additional Issue

`remove_synchronized_folder_exception` with `file_name` parameter returns "File not found in exception set" when the file is in the duplicate (second) set — it only checks the first exception set for the target.

## Impact

- The duplicate exception set caused Xcode to misinterpret file membership
- Attempting to fix this manually required editing pbxproj directly
- The broken state cascaded: TestSupport module failed to build, which broke ALL test targets

## Summary of Changes

- **AddSynchronizedFolderExceptionTool**: check for an existing exception set for the target before creating a new one; append files to the existing set (skipping duplicates) instead of creating a second set
- **RemoveSynchronizedFolderExceptionTool**: search all exception sets for the target when removing a file (not just the first one); remove all exception sets for the target when removing the entire set (handles pre-existing duplicates)
- Added 2 new tests: merge-into-existing behavior and duplicate-file skipping

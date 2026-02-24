---
# a5u-ug2
title: list_files missing files from PBXFileSystemSynchronizedRootGroup targets
status: completed
type: bug
priority: normal
tags:
    - xc-project
created_at: 2026-02-22T22:53:57Z
updated_at: 2026-02-22T23:01:47Z
sync:
    github:
        issue_number: "106"
        synced_at: "2026-02-24T18:57:45Z"
---

## Problem

`list_files` doesn't show files contributed by `PBXFileSystemSynchronizedRootGroup` entries when the group-to-target association is via `PBXFileSystemSynchronizedBuildFileExceptionSet` rather than `target.fileSystemSynchronizedGroups`.

### Observed behavior

```
mcp__xc-project__list_files(project: "Thesis.xcodeproj", target: "TestSupport")
→ Files in target 'TestSupport':
  Sources:
    - TestSupport/WithTestManuscript.swift    ← only explicitly added file
  Frameworks:
    - XCTest.framework
    - Testing.framework
```

TestSupport has ~25 Swift files on disk, but only the one added via `add_file` appears. The synchronized folder and its contents are invisible.

### Root cause

In `ListFilesTool.swift:92`, the code checks `target.fileSystemSynchronizedGroups`, but `PBXFileSystemSynchronizedRootGroup` entries in the project associate with targets through exception sets in their `exceptions` array, not through the target's `fileSystemSynchronizedGroups` property.

The pbxproj structure looks like:

```
964343952EDD21FB006F24E8 /* TestSupport */ = {
    isa = PBXFileSystemSynchronizedRootGroup;
    exceptions = (
        962093D72EDD2B1000765575 /* Exceptions for "TestSupport" folder in "TestSupport" target */,
    );
    path = TestSupport;
};
```

The exception set references the target, but `list_files` never walks `PBXFileSystemSynchronizedRootGroup` entries in the project to find this association.

### Expected behavior

For synchronized root groups, `list_files` should:
1. Find all `PBXFileSystemSynchronizedRootGroup` entries that have exception sets referencing the target
2. Enumerate `.swift` files on disk in that folder
3. Subtract `membershipExceptions` (which are EXCLUDED files)
4. Show the result under "Synchronized folders" with included file count or file list

### Impact

During a Thesis session, the agent couldn't determine which files were compiled into TestSupport, leading to confusion about whether a new file was included in the target. This caused multiple failed build attempts.

### Context

Issue nan-0qi previously addressed this but the fix only covered `fileSystemSynchronizedGroups` (the target property), not `PBXFileSystemSynchronizedRootGroup` (the project-level synchronized root group with exception-based target association).

## Tasks

- [x] Walk all `PBXFileSystemSynchronizedRootGroup` entries to find exception sets referencing the target
- [x] Enumerate disk files in the group's path, subtract `membershipExceptions`
- [x] Include results in the "Synchronized folders" section of list_files output
- [x] Add test with a fixture that uses `PBXFileSystemSynchronizedRootGroup` + exception sets


## Summary of Changes

- **ListFilesTool.swift**: Added a second pass that walks all `PBXFileSystemSynchronizedRootGroup` entries in the project (via `pbxproj.fileSystemSynchronizedRootGroups`) and checks if their exception sets reference the target. Previously only `target.fileSystemSynchronizedGroups` was checked, missing groups associated via exception sets. Also added disk file enumeration for sync folders (with exclusion of `membershipExceptions`) so the output shows actual files, not just the folder name.
- **ListFilesToolTests.swift**: Added `listFilesWithSyncGroupViaExceptionSet` test that creates a sync group associated with a target only via an exception set (not via `target.fileSystemSynchronizedGroups`), puts files on disk, and verifies the tool discovers the folder and correctly excludes membership exceptions.

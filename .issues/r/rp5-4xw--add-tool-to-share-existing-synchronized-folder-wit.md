---
# rp5-4xw
title: Add tool to share existing synchronized folder with another target
status: completed
type: feature
priority: normal
created_at: 2026-02-18T04:14:40Z
updated_at: 2026-02-18T04:21:11Z
---

## Problem

`add_synchronized_folder` always creates a NEW `PBXFileSystemSynchronizedRootGroup`. When two targets need to share the same source folder (e.g. ThesisApp and DiagnosticApp both need App/Sources), there's no way to add the existing synchronized group to the second target's `fileSystemSynchronizedGroups`.

Manually editing pbxproj to work around this led to project corruption.

## Proposed Tools

### 1. `add_target_to_synchronized_folder`

Given an existing synchronized folder (identified by path within the project hierarchy), add it to a target's `fileSystemSynchronizedGroups`.

**Parameters:**
- `project_path` (required): Path to .xcodeproj
- `folder_path` (required): Path to the synchronized folder (e.g. "App/Sources") — matches against existing `PBXFileSystemSynchronizedRootGroup` entries
- `target_name` (required): Target to add the sync group to

**Implementation:** Find the existing `PBXFileSystemSynchronizedRootGroup` by walking the group hierarchy, then append it to the target's `fileSystemSynchronizedGroups` array.

### 2. `add_synchronized_folder_exception`

Add a `PBXFileSystemSynchronizedBuildFileExceptionSet` to exclude specific files from a specific target within a synchronized folder.

**Parameters:**
- `project_path` (required): Path to .xcodeproj
- `folder_path` (required): Path to the synchronized folder
- `target_name` (required): Target to exclude files from
- `files` (required): Array of file names to exclude (relative to the sync folder)

**Implementation:** Create a `PBXFileSystemSynchronizedBuildFileExceptionSet` with `membershipExceptions` and add it to the sync group's `exceptions` array.

## Use Case

Two app targets sharing `App/Sources`:
```
add_target_to_synchronized_folder(folder_path: "App/Sources", target_name: "DiagnosticApp")
add_synchronized_folder_exception(folder_path: "App/Sources", target_name: "DiagnosticApp", files: ["ThesisApp.swift"])
add_synchronized_folder_exception(folder_path: "App/Sources", target_name: "ThesisApp", files: ["DiagnosticApp.swift"])
```


## Summary of Changes

Implemented two new MCP tools:

1. **`add_target_to_synchronized_folder`** — Adds an existing `PBXFileSystemSynchronizedRootGroup` to a target's `fileSystemSynchronizedGroups`, enabling folder sharing between multiple targets. Includes idempotency check to avoid duplicates.

2. **`add_synchronized_folder_exception`** — Creates a `PBXFileSystemSynchronizedBuildFileExceptionSet` with `membershipExceptions` to exclude specific files from a target within a shared synchronized folder.

### Files Added
- `Sources/Tools/Project/AddTargetToSynchronizedFolderTool.swift`
- `Sources/Tools/Project/AddSynchronizedFolderExceptionTool.swift`
- `Tests/AddTargetToSynchronizedFolderToolTests.swift` (6 tests)
- `Tests/AddSynchronizedFolderExceptionToolTests.swift` (6 tests)

### Files Modified
- `Sources/Server/XcodeMCPServer.swift` — registered both tools (enum, instantiation, list, dispatch)

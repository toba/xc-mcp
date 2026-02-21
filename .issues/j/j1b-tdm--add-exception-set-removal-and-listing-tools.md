---
# j1b-tdm
title: Add exception set removal and listing tools
status: ready
type: feature
created_at: 2026-02-21T20:39:58Z
updated_at: 2026-02-21T20:39:58Z
---

Exception sets (`PBXFileSystemSynchronizedBuildFileExceptionSet`) can be added via the unexposed `AddSynchronizedFolderExceptionTool`, but there's no way to remove them or list what exists.

## Problem

During the DiagnosticApp restructure, the agent had to:
1. Manually delete an exception set definition from the pbxproj
2. Manually remove the exception set reference from the synchronized root group's `exceptions` array
3. Later re-add it manually when realizing it was still needed

There was also no way to inspect what exception sets existed on a synchronized folder without reading raw pbxproj.

## Proposed tools

### `remove_synchronized_folder_exception`

**Parameters:**
- `project_path` (required)
- `folder_path` (required) — the synchronized folder
- `target_name` (required) — which target's exception set to remove
- `file_name` (optional) — remove a single file from the exception set instead of the whole set

**Behavior:**
1. Find the exception set for the given target on the synced folder
2. If `file_name` provided, remove just that entry from `membershipExceptions`
3. If no `file_name`, remove the entire exception set and its reference from the root group's `exceptions` array

### `list_synchronized_folder_exceptions`

**Parameters:**
- `project_path` (required)
- `folder_path` (required)

**Returns:** List of exception sets on the folder, showing target name and excluded files for each.

## Files

- New: `Sources/Tools/Project/RemoveSynchronizedFolderExceptionTool.swift`
- New: `Sources/Tools/Project/ListSynchronizedFolderExceptionsTool.swift`
- Modify: `Sources/Servers/Project/ProjectMCPServer.swift` (register)

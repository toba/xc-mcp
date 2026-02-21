---
# r7y-g9l
title: Add remove_target_from_synchronized_folder tool
status: ready
type: feature
created_at: 2026-02-21T20:39:48Z
updated_at: 2026-02-21T20:39:48Z
---

No tool exists to remove a target's reference to a synchronized folder. `add_synchronized_folder` can add one, but there's no way to unlink a target from a shared synced folder without editing pbxproj directly.

## Problem

During the DiagnosticApp restructure, `App/Sources` was shared between ThesisApp and DiagnosticApp targets. The agent needed to remove DiagnosticApp from `App/Sources`'s `fileSystemSynchronizedGroups` but had to manually edit the pbxproj to do it.

## Proposed tool: `remove_target_from_synchronized_folder`

**Parameters:**
- `project_path` (required)
- `folder_path` (required) — the synchronized folder path
- `target_name` (required) — target to unlink

**Behavior:**
1. Find the `PBXFileSystemSynchronizedRootGroup` for the folder
2. Find the target's `fileSystemSynchronizedGroups` array
3. Remove the synced group reference from the target
4. Clean up any orphaned exception sets that referenced this target

## Files

- New: `Sources/Tools/Project/RemoveTargetFromSynchronizedFolderTool.swift`
- Modify: `Sources/Servers/Project/ProjectMCPServer.swift` (register)

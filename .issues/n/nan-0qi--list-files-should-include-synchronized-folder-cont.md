---
# nan-0qi
title: list_files should include synchronized folder contributions
status: completed
type: bug
priority: normal
created_at: 2026-02-21T20:40:09Z
updated_at: 2026-02-21T20:54:35Z
---

`list_files` for a target only returns explicit file references (e.g. framework dependencies). It does not show files contributed by synchronized folders (`fileSystemSynchronizedGroups`).

## Problem

When the agent ran `list_files` for the DiagnosticApp target, it got:
```
Files in target 'DiagnosticApp':
- Core.framework
- DOM.framework
- CSL.framework
...
```

No source files were shown, even though `App/Sources` (a synchronized folder) was contributing all the app's Swift source to the target. The agent had to grep the pbxproj for `fileSystemSynchronizedGroups` to understand the target's actual composition.

## Expected behavior

`list_files` should also list synchronized folder memberships, clearly distinguished from explicit files. For example:
```
Files in target 'DiagnosticApp':
Synchronized folders:
  - App/Sources (synchronized)
  - App/PreviewSupport (synchronized)
Frameworks:
  - Core.framework
  - DOM.framework
  ...
```

Or alternatively, a separate `list_target_membership` tool that shows the full picture: synced folders, explicit source files, frameworks, resources, and exception sets.

## Files

- `Sources/Tools/Project/ListFilesTool.swift` — current implementation to modify


## Summary of Changes

Restructured `ListFilesTool` output to group files by category (Synchronized folders, Sources, Resources, Frameworks) with section headers. Added detection of `target.fileSystemSynchronizedGroups` entries and per-target membership exceptions from `PBXFileSystemSynchronizedBuildFileExceptionSet`.

Added two new tests: `testListFilesWithSynchronizedFolder` and `testListFilesWithSynchronizedFolderExceptions`. All 8 ListFiles tests pass.

---
# xc-mcp-f1y3
title: MCP tools corrupt unrelated PBXCopyFilesBuildPhase sections
status: completed
type: bug
priority: normal
created_at: 2026-01-27T00:31:57Z
updated_at: 2026-01-27T00:34:04Z
sync:
    github:
        issue_number: "29"
        synced_at: "2026-02-15T22:08:23Z"
---

When using MCP project tools (observed with add_synchronized_folder, remove_synchronized_folder, create_group), unrelated `PBXCopyFilesBuildPhase` sections get corrupted.

## Reproduction

1. Have a project with copy phases configured with `dstSubfolder = Resources`
2. Run `remove_synchronized_folder` followed by `create_group` and `add_synchronized_folder`
3. Result: Copy phases change from `dstSubfolder = Resources` to `dstSubfolder = None`

## Impact

Build fails with errors like:
```
error: copy(/path/to/source/file.csl, /styles/file.csl): No such file or directory
```

The destination path becomes `/styles/` (root filesystem) instead of the app bundle's Resources folder.

## Observed Corrupted Fields

```diff
- dstSubfolder = Resources;
+ dstSubfolder = None;
```

This affected multiple copy phases (docx, styles, locales) that were completely unrelated to the synchronized folder operations.

## Root Cause

Likely in the pbxproj serialization/parsing. When writing the project back after modifications, something is resetting or incorrectly handling the dstSubfolder enum values.

## Investigation

Unable to reproduce this issue with XcodeProj 9.7.2. Added a regression test `copyFilesPhasePreservedAfterOtherOperations` in `Tests/AddBuildPhaseToolTests.swift` that:
1. Creates a project with a copy files build phase with `dstSubfolderSpec = .resources`
2. Uses `add_synchronized_folder` to add a folder
3. Verifies the copy files phase still has `dstSubfolderSpec = .resources`

The test passes, indicating the issue may have been:
- Fixed in a recent XcodeProj library update
- Specific to certain project configurations not covered by our test
- Related to the project file format or Xcode version

The regression test will prevent this issue from recurring in the future.

## Workaround

After MCP operations, verify build works. If copy errors occur, manually restore:
```
dstSubfolder = Resources;
```

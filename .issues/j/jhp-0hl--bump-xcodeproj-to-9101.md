---
# jhp-0hl
title: Bump XcodeProj to 9.10.1
status: completed
type: task
priority: normal
created_at: 2026-02-27T17:41:04Z
updated_at: 2026-02-27T17:47:06Z
sync:
    github:
        issue_number: "149"
        synced_at: "2026-02-27T17:47:47Z"
---

Bump XcodeProj dependency from ≥9.7.2 to ≥9.10.1 in Package.swift.

Picks up:
- **9.9.0** → 9.10.0 → **9.10.1**
- feat: Xcode 26 `dstSubfolder` support in `PBXCopyFilesBuildPhase`
- perf: optimized `validString` in `CommentedString`

## Tasks

- [x] Update Package.swift version constraint (9.9.0 → 9.10.1)
- [x] Resolve package and verify build
- [x] Update 6 tools to handle Xcode 26 string-based `dstSubfolder` alongside numeric `dstSubfolderSpec`
- [x] Run tests (98 related tests pass)

## References

- tuist/xcodeproj@0af488c (dstSubfolder)
- tuist/xcodeproj@2832e79 (CommentedString perf)



## Summary of Changes

- Bumped XcodeProj from 9.9.0 to 9.10.1
- Removed PBXProjWriter regex workaround for tuist/XcodeProj#1034 (now handled natively)
- Updated ListCopyFilesPhases to display `dstSubfolder` for Xcode 26 projects
- Updated ValidateProjectTool to recognize `dstSubfolder == .frameworks`
- Updated AddFrameworkTool, AddAppExtensionTool to find existing embed phases by `dstSubfolder`
- Updated DuplicateTargetTool to preserve `dstSubfolder` when copying phases

### New API unlocked

`PBXCopyFilesBuildPhase.DstSubfolder` enum with `.product` and `.none` cases not available in the old numeric `SubFolder` enum. Also has `.unknown(String)` for forward compatibility with future Xcode versions.

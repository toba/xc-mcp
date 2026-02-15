---
# xc-mcp-qem0
title: set_build_setting drops dstSubfolder fields from PBXCopyFilesBuildPhase
status: completed
type: bug
priority: high
created_at: 2026-01-31T02:27:46Z
updated_at: 2026-01-31T03:39:11Z
sync:
    github:
        issue_number: "31"
        synced_at: "2026-02-15T22:08:23Z"
---

When using the set_build_setting tool, it rewrites the entire pbxproj file and drops `dstSubfolder` fields from `PBXCopyFilesBuildPhase` sections, causing copy file build phases to target `/` instead of Resources.

## Root cause

Xcode 26 writes `dstSubfolder = Resources;` (string) instead of `dstSubfolderSpec = 7;` (numeric) in `PBXCopyFilesBuildPhase`. XcodeProj 9.7.2 only recognizes `dstSubfolderSpec` — the string variant is silently dropped during read/write, corrupting copy file build phases.

Upstream: tuist/XcodeProj#1034 (open, PRs #1038 and #1043 pending)

## Fix

Created `PBXProjWriter` utility that wraps `writePBXProj` to preserve `dstSubfolder` entries that XcodeProj would drop:

1. Before write: snapshot `dstSubfolder` entries from existing pbxproj (keyed by object ID)
2. Write: let XcodeProj write normally
3. After write: patch back any lost `dstSubfolder` entries after the `dstPath` line

All 20 project-modifying tools now use `PBXProjWriter.write()` instead of calling `writePBXProj` directly.

## Checklist

- [x] Investigate the serialization pipeline in XcodeProj
- [x] Add regression test for set_build_setting + dstSubfolderSpec preservation
- [x] Reproduce with an actual Xcode-created project (need sample pbxproj that triggers the bug)
- [x] Create PBXProjWriter workaround utility
- [x] Update all 20 project tools to use PBXProjWriter
- [x] Add test for Xcode 26 string-based dstSubfolder round-trip preservation
- [x] All 243 tests pass, 0 lint violations

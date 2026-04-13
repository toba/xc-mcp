---
# g42-71x
title: Handle Xcode 26 objectVersion 100 project format (synchronized folders)
status: review
type: feature
priority: normal
created_at: 2026-04-13T17:07:41Z
updated_at: 2026-04-13T17:21:27Z
sync:
    github:
        issue_number: "282"
        synced_at: "2026-04-13T17:25:02Z"
---

## Context

When Xcode 26 opens a project with objectVersion 60, it offers to migrate to objectVersion 100 — the new "synchronized folders" format (`PBXFileSystemSynchronizedRootGroup`). This migration:

- Replaces explicit `PBXFileReference` / `PBXBuildFile` entries with `(null)` placeholders
- Converts `PBXGroup` to `PBXFileSystemSynchronizedRootGroup`
- Removes deprecated keys (`buildActionMask`, `runOnlyForDeploymentPostprocessing`, `compatibilityVersion`, etc.)
- Adds `PBXFileSystemSynchronizedBuildFileExceptionSet` for excluded files (e.g. Info.plist)

After this migration, local SPM package products (`XCLocalSwiftPackageReference`) may fail to resolve, producing errors like:
> Missing package product 'FooKit' (in target 'Bar' from project 'Baz')

## What's missing in xc-mcp

- [x] `CreateXcodeprojTool` hardcodes `preferredProjectObjectVersion: 56` — should use a modern default (77 or 100) or make it configurable
- [x] No tool to **validate project integrity** after Xcode auto-migration (detect orphaned `(null)` build files, missing package links, etc.)
- [x] `PBXProjWriter` and all project tools need testing against objectVersion 100 projects to ensure they can read/write without corruption
- [x] Consider a `migrate_project` or `repair_project` tool that can fix common post-migration issues (re-link package products, clean up null references)

## Observed in

toba/swiftiomatic — Xcode project opened in Xcode 26, auto-migrated, then failed to build due to missing package products. The committed objectVersion 60 format builds fine.


## Summary of Changes

### objectVersion default updated (56 → 77)
- `CreateXcodeprojTool` now defaults to objectVersion 77 (Xcode 15+) and accepts an `object_version` parameter for 56/77/100
- `ScaffoldIOSProjectTool`, `ScaffoldMacOSProjectTool` updated to 77
- `TestProjectHelper` updated to 77
- compatibilityVersion updated to "Xcode 15.0"

### validate_project gains post-migration checks
- Detects null file references in build phases (common Xcode 26 migration artifact)
- Detects orphaned synchronized folders not linked to any target
- Detects broken package product references (missing package link)

### New tool: repair_project
- Removes build files with null file references from all build phases
- Removes orphaned PBXBuildFile entries not in any build phase
- Supports `dry_run` mode to preview fixes without writing
- Registered in both monolithic and xc-project focused servers

### Tests
- 6 new RepairProjectTool tests (tool creation, missing params, clean project, null removal, dry run, orphan removal)
- 3 new ValidateProjectTool tests (null file refs, orphaned sync folder, linked sync folder passes)
- All 53 affected tests pass (17 validate, 6 repair, 4 create, 6 scaffold iOS, 8 scaffold macOS, 12 scaffold module)

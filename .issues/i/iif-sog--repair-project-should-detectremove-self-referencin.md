---
# iif-sog
title: repair_project should detect/remove self-referencing sub-project entries
status: ready
type: bug
priority: normal
created_at: 2026-05-22T05:34:46Z
updated_at: 2026-05-22T05:34:46Z
sync:
    github:
        issue_number: "326"
        synced_at: "2026-05-22T05:42:38Z"
---

## Problem

`detect_unused_code` (Periphery) fails when an .xcodeproj contains `projectReferences` entries that point at the project **itself** (a project nested inside itself). Periphery aborts with a cryptic error and exit code 1:

```
Error: Cannot calculate full path for file element "Thesis.xcodeproj" in source root: "/Users/jason/Developer/toba/thesis"
```

This blocks any unused-code scan until the entries are removed by hand.

## Root cause

The pbxproj accumulated 4 bogus self-references (likely from a stray Xcode operation). Each consisted of:
- a `PBXFileReference` with `path = Thesis.xcodeproj`, `lastKnownFileType = "wrapper.pb-project"`
- an empty `PBXGroup` named Products
- a `projectReferences` entry pairing the two (`ProjectRef` + `ProductGroup`)

None were wired to any target dependency (no `containerItemProxy` referenced them) — pure dead/circular junk.

## Asks

1. `repair_project` should detect and remove `projectReferences` entries whose `ProjectRef` resolves to the containing project (self-reference), along with their orphaned empty Products groups and file references. Current `repair_project --dry-run` reports 'No issues found' for this case.
2. `detect_unused_code` should surface a clearer, actionable error when Periphery fails to resolve a project file element, pointing at likely self-reference / circular sub-project corruption.

## Repro

Add a sub-project reference from a project to itself, then run `detect_unused_code`.

## Workaround

Manually delete the self-referencing `projectReferences`, file references, and empty Products groups from project.pbxproj.

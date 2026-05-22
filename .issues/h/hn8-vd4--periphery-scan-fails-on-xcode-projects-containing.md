---
# hn8-vd4
title: Periphery scan fails on Xcode projects containing self-referencing sub-project entries
status: completed
type: bug
priority: normal
created_at: 2026-05-22T05:34:02Z
updated_at: 2026-05-22T05:41:49Z
sync:
    github:
        issue_number: "327"
        synced_at: "2026-05-22T05:42:38Z"
---

detect_unused_code (and the underlying Periphery invocation) exits with code 1 when a project.pbxproj contains a sub-project reference pointing at itself:

```
Error: Cannot calculate full path for file element "Thesis.xcodeproj" in source root: "/Users/jason/Developer/toba/thesis"
```

Repro: A pbxproj with projectReferences entries whose ProjectRef is a PBXFileReference of lastKnownFileType = "wrapper.pb-project" and path = <SelfProject>.xcodeproj (i.e. the project nested inside itself). In the Thesis project there were 4 such bogus entries plus their empty Products groups and file references. These can be introduced accidentally by Xcode operations and are not caught by repair_project.

Impact: The scan is completely blocked — no partial results.

## Suggested fixes
1. Have repair_project detect and offer to remove self-referencing sub-project entries (file ref + projectReferences entry + orphaned empty Products group).
2. In detect_unused_code, surface a clearer error that names the offending self-reference and points to repair_project, rather than passing through Periphery's raw "Cannot calculate full path" message.
3. Optionally have validate_project flag self-referential projectReferences.

## Workaround used
Manually removed the 4 self file-references, their 4 empty Products groups, and the 4 projectReferences entries from project.pbxproj; `plutil -lint` passed and the scan proceeded.

## Summary of Changes

All three suggested fixes implemented.

- **New shared helper** `Sources/Tools/Project/SelfProjectReference.swift`: `detect(in:projectPath:)` finds `projectReferences` entries whose `ProjectRef` basename matches the project's own `.xcodeproj`; `remove(from:projectPath:)` deletes the file reference (detached recursively from mainGroup), the `projectReferences` entry, and the empty Products group.
- **repair_project**: detects and removes self-referencing sub-project entries (honors `dry_run`), reporting the count and names.
- **validate_project**: new project-level `[error]` diagnostic naming each self-reference and pointing to `repair_project`.
- **detect_unused_code**: intercepts Periphery's `Cannot calculate full path for file element` exit, and when the project is an .xcodeproj, reads it to name the offending self-reference(s) and direct the caller to `repair_project` instead of passing through the raw message.
- **Tests** (+6): `TestProjectHelper.injectSelfProjectReferences` fixture builder; 2 RepairProjectTool tests (remove + dry-run), 1 ValidateProjectTool test, 1 DetectUnusedCodeTool guidance test. 75/0 across affected suites.

---
# uqz-3vb
title: Consolidate Core/ProjectFile pbxproj parsing helpers
status: completed
type: task
priority: normal
created_at: 2026-07-08T16:25:27Z
updated_at: 2026-07-08T16:41:41Z
sync:
    github:
        issue_number: "418"
        synced_at: "2026-07-08T16:42:51Z"
---

Swift review of Sources/Core/ProjectFile found duplicated pbxproj parsing. Extract shared PBXProjParsing utility (file read + splitLines + 24-char identifier test) reused by PBXProjTextEditor, PBXTargetMap, PBXProjReferenceAudit; add leadingIndent helper; micro-perf on generateUUID and extractLeadingUUID. Deferred: batch split/join edit API (needs its own design across 7 tool files).


## Summary of Changes

- New `Sources/Core/ProjectFile/PBXProjParsing.swift`:
  - `pbxprojPath(forProject:)` — single source for the `<proj>/project.pbxproj` path
  - `readText(projectPath:)` — shared UTF-8 read (replaces 3 inline copies)
  - `identifierLength` (24), `isIdentifier(_:requireUppercase:)`, `isHexByte(_:requireUppercase:)` — one 24-char object-identifier test (replaces 4 divergent implementations)
  - `String.splitLines()` — promoted here from PBXProjTextEditor
- `PBXProjTextEditor`: shared path helper; private `leadingIndent(of:)` dedupes 4 inline `prefix(while:)` sites; `generateUUID` writes into `String(unsafeUninitializedCapacity:)`.
- `PBXProjReferenceAudit`: `isReferenceToken` delegates to `PBXProjParsing.isIdentifier` (removed local `isHexByte`).
- `PBXTargetMap`: `buildMap`/`findUUID` use shared `readText` + `splitLines`; `extractLeadingUUID` uses `isIdentifier(requireUppercase:)` and drops the O(n) full-line `count`; regex length from `identifierLength`.

Behavior-preserving. Build succeeds; 113 affected tests pass. Format + lint clean.

## Deferred

Batch split/join edit API for `PBXProjTextEditor` (each mutator re-splits/re-joins the whole file; AddFrameworkTool chains 15 edits). Real, but touches the public signature of every mutator across 7 tool files on a delicate path; project mutation runs once per invocation, not in a hot loop. Warrants its own design.


## Follow-up: batch split/join edit API (previously deferred — now done)

Added `PBXProjEditor`, a value type holding the pbxproj as `[String]` lines. It owns the real edit logic (block/array/reference/section/build-setting mutations); the existing `PBXProjTextEditor.*` static `String -> String` methods are now thin wrappers over a single-edit `PBXProjEditor`, so all prior callers and tests are unchanged.

Migrated the 6 tools that chain 2+ edits to a single `PBXProjEditor` instance (split + join once instead of per edit):
- AddFrameworkTool (15 edits — largest win)
- RemoveSynchronizedFolderExceptionTool (5)
- RemoveFileTool (4)
- AddSynchronizedFolderExceptionTool (3)
- AddSynchronizedFolderPhaseMembershipTool (3)
- RemoveTargetFromSynchronizedFolderTool (3)

AddTargetToSynchronizedFolderTool (1 edit) left on the static wrapper — no benefit.

Behavior-preserving. Build clean; 117 affected tests pass; format + lint clean.

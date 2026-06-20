---
# y0n-gch
title: 'add_synchronized_folder/move_group: child folders break when parent group re-pathed; new framework targets need manual link + group cleanup'
status: completed
type: bug
priority: normal
created_at: 2026-06-20T21:23:58Z
updated_at: 2026-06-20T21:35:32Z
sync:
    github:
        issue_number: "393"
        synced_at: "2026-06-20T21:36:11Z"
---

Hit while scaffolding a new `Integrations/GoogleDocs` framework module in the Thesis project (mirroring `AsciiDoc`). Several project-tool rough edges in the new-framework-module flow:

## 1. move_group --new-path on a parent cascades and breaks child synchronized folders (main bug)
Repro:
1. create_group GoogleDocs under Integrations (with a wrong path that doubled the prefix — see #2) -> parent group renders RED in Xcode (path resolves to Integrations/Integrations/GoogleDocs).
2. add_synchronized_folder Integrations/GoogleDocs/Sources + .../Tests -> children render blue/correct at this point.
3. move_group group_path=Integrations/GoogleDocs new_parent=Integrations new_path=GoogleDocs -> parent fixed (white), BUT now Sources and Tests render red — the re-path cascaded onto the children and left them unresolved.

Workaround that worked: remove_synchronized_folder both, then add_synchronized_folder again now that the parent path is correct. After re-add, list_files shows Sources with Compiled files (3) (previously it showed the raw Integrations/GoogleDocs/Sources label with no files = unresolved).

Expected: re-pathing a parent group should recompute/preserve child synchronized-folder resolution, or move_group should warn that child sourceTree/path needs rewriting.

## 2. create_group path semantics silently produce a broken (red) doubled-path group
create_group(parent_group=Integrations, path="Integrations/GoogleDocs") resolves to Integrations/Integrations/GoogleDocs because path is relative to the parent. No error/warn — the group just renders red. Suggest validating that the resolved on-disk path exists (or warning when it does not).

## 3. add_target (framework + unitTestBundle) leaves placeholder subgroups + omits framework essentials
- Creates empty placeholder subgroups GoogleDocs/GoogleDocs and GoogleDocs/GoogleDocsTests that must be manually remove_group-d before wiring real Sources/Tests synchronized folders.
- Omits build settings every sibling integration framework sets: DEFINES_MODULE=YES, SUPPORTED_PLATFORMS="iphoneos iphonesimulator macosx", SKIP_INSTALL=YES. Had to set_build_setting each manually.

## 4. add_dependency adds the target-dependency edge but not the Link Binary entry
After add_dependency(GoogleDocs -> Core, DOM), validate_project showed "Has dependency on Core but does not link ThesisShared.framework" and list_frameworks_phase GoogleDocs was empty — vs AsciiDoc which links Core.framework/DOM.framework. Had to call add_framework separately for each. Consider an option on add_dependency to also add the framework to the Link Binary phase (the common case for framework targets).

Environment: Xcode 26.2; target project uses the group + Sources/Tests synchronized-folder pattern across ~28 integration modules.

## Summary of Changes

Addressed all four reported rough edges in the new-framework-module flow.

### 1. move_group cascade (main bug) — fixed
`move_group` now snapshots where every synchronized folder resolves on disk *before* the move, then rewrites the `path` of any child whose parent's accumulated path changed so it keeps resolving to the same directory (move_group never moves files on disk). Re-pathing a parent to fix a doubled prefix collapses the child to a clean leaf (e.g. `Sources`); moving to a new parent preserves resolution via a relative path. The result message reports how many child synchronized folders were preserved.

### 2. create_group doubled-path validation — fixed
When `path` is supplied, `create_group` computes the directory the group resolves to (path is relative to the *parent group*, so `parent_group=Integrations, path=Integrations/GoogleDocs` → `Integrations/Integrations/GoogleDocs`) and appends a `Warning:` to the result when that directory does not exist on disk, explaining the prefix doubling.

### 3. add_target framework essentials + placeholder group — fixed
- Framework / staticFramework targets now get `DEFINES_MODULE=YES` and `SKIP_INSTALL=YES`. (`SUPPORTED_PLATFORMS` is intentionally left to project defaults since it is platform-specific; set it explicitly via `set_build_setting` or use `scaffold_module`.)
- New optional `create_group` boolean (default true). Pass `create_group: false` to skip the empty placeholder navigator group when you'll wire your own Sources/Tests synchronized folders.

### 4. add_dependency Link Binary entry — fixed
New optional `link_binary` boolean (default false). For in-project dependencies it also adds the dependency's product to `target_name`'s Link Binary With Libraries phase. Re-running with `link_binary: true` links a dependency that was previously added without a link (the exact reported case). Cross-project dependencies report that linking must go through `add_framework`.

### Implementation notes
- Added `Sources/Tools/Project/OnDiskPath.swift` — shared helpers (`normalize`, `join`, `relativize`, `accumulated(of:in:)`, `syncResolutions(in:)`) for the on-disk-path arithmetic, reused by move_group and create_group.
- Tests added: 2 move_group cascade tests, 2 create_group warning tests, 3 add_target tests (framework settings, app exclusion, create_group=false), 2 add_dependency link_binary tests. All passing; build clean; `sm`-formatted.

Note: `scaffold_module` remains the recommended one-call path for the whole framework-module flow; these fixes harden the individual tools for ad-hoc use.

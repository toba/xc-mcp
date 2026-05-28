---
# pj7-9fu
title: Support PBXFileSystemSynchronizedGroupBuildPhaseMembershipExceptionSet
status: completed
type: feature
priority: normal
created_at: 2026-05-28T16:00:37Z
updated_at: 2026-05-28T16:09:15Z
sync:
    github:
        issue_number: "358"
        synced_at: "2026-05-28T16:15:02Z"
---

The current `mcp__xc-project__*` tools do not support modifying `PBXFileSystemSynchronizedGroupBuildPhaseMembershipExceptionSet` — the structure Xcode uses to opt specific files from a synchronized root group into a particular `PBXCopyFilesBuildPhase` (or other build phase).

## Concrete scenario that exposed this

Thesis bundles XML style templates by:

1. A synchronized root group `Integrations/DocX/DefaultStyles/` shared across targets.
2. A `PBXCopyFilesBuildPhase` on the ThesisApp target with `dstPath = docx; dstSubfolder = Resources;`.
3. A `PBXFileSystemSynchronizedGroupBuildPhaseMembershipExceptionSet` that names the files from the synced folder to include in that Copy Files phase:

```
96CB25D12F285E1F00EB8FE5 = {
    isa = PBXFileSystemSynchronizedGroupBuildPhaseMembershipExceptionSet;
    buildPhase = 9608E2CE2E930062002D730E /* CopyFiles */;
    membershipExceptions = (
        \"word-16-custom.xml\",
        \"word-16.xml\",
    );
};
```

To add a new file (`word-16-vellum.xml`) we need to append it to `membershipExceptions`. Today this can't be done via MCP:

- `mcp__xc-project__add_to_copy_files_phase` returns \"phase not found\" because the phase has no `name` and the MCP lookup is by name only.
- `mcp__xc-project__add_synchronized_folder_exception` only handles `PBXFileSystemSynchronizedBuildFileExceptionSet` (target membership exclusion), not the build-phase variant.
- `mcp__xc-project__list_synchronized_folder_exceptions` reports `Unknown exception set type: PBXFileSystemSynchronizedGroupBuildPhaseMembershipExceptionSet`.

## Proposed shape

Two complementary additions:

1. **List**: extend `mcp__xc-project__list_synchronized_folder_exceptions` to also report `PBXFileSystemSynchronizedGroupBuildPhaseMembershipExceptionSet` sets, including the linked build phase's `dstPath`, `dstSubfolder`, and current member files.
2. **Mutate**: new tool `mcp__xc-project__add_synchronized_folder_phase_membership` (or extend `add_to_copy_files_phase` to look up phases by `dstPath` when `phase_name` is absent) that appends a file to the synced-folder build-phase membership exceptions. Should auto-create the exception set if missing.

## Workaround used in the meantime

Patch the pbxproj via sed (one-off; not sustainable).

## Originating issue

Thesis p1n-5a5 (Vellum DocX template). Lives at `/Users/jason/Developer/toba/thesis/.issues/p/p1n-5a5--*.md`.



## Summary of Changes

- Added `add_synchronized_folder_phase_membership` MCP tool that creates or extends a `PBXFileSystemSynchronizedGroupBuildPhaseMembershipExceptionSet` to opt sync-folder files into a target's build phase. Phase lookup priority: `phase_name` → `dst_path` → target's sole Copy Files phase.
- Extended `list_synchronized_folder_exceptions` to also report `PBXFileSystemSynchronizedGroupBuildPhaseMembershipExceptionSet` entries with their phase name, dstPath, dstSubfolder, members, and attributesByRelativePath.
- Added `PBXProjTextEditor.insertGroupBuildPhaseMembershipExceptionSetBlock` helper for surgical pbxproj insertion of the new section (with auto-creation in alphabetical position).
- Registered the new tool in both `ProjectMCPServer` (xc-project) and `XcodeMCPServer` (monolithic xc-mcp).
- New tests: `AddSynchronizedFolderPhaseMembershipToolTests` (10 cases) covering creation, append, dedupe, lookup-by-name, lookup-by-dst_path, single-phase fallback, and failure modes.

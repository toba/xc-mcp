---
# 4fb-icg
title: Let remove_synchronized_folder_exception remove dstPath build-phase-routing sets
status: completed
type: feature
priority: normal
created_at: 2026-07-26T07:22:59Z
updated_at: 2026-07-26T07:26:37Z
sync:
    github:
        issue_number: "437"
        synced_at: "2026-07-26T07:30:26Z"
---

Follow-up from pas-2jg. remove_synchronized_folder_exception only handles PBXFileSystemSynchronizedBuildFileExceptionSet (exclusion sets keyed by target); it cannot locate or remove PBXFileSystemSynchronizedGroupBuildPhaseMembershipExceptionSet (dstPath phase-routing sets), which are keyed by build phase, not target. Add optional phase_name/dst_path params so the tool can target a routing set and remove a single membership file or the whole set.

## Summary of Changes

`remove_synchronized_folder_exception` (`Sources/Tools/Project/RemoveSynchronizedFolderExceptionTool.swift`) now handles build-phase routing sets in addition to target exclusion sets:

- Added optional `phase_name` and `dst_path` params. Presence of either switches the tool into "routing-set mode", where it locates the `PBXFileSystemSynchronizedGroupBuildPhaseMembershipExceptionSet` whose `buildPhase` matches the phase resolved on `target_name` (via a `locatePhase` helper mirroring `AddSynchronizedFolderPhaseMembershipTool`: phase_name → dst_path → sole Copy Files phase).
- Both exception-set kinds carry `membershipExceptions` and are referenced from the sync group's `exceptions` array, so the removal logic (remove one file, or remove the whole set + reference, or auto-remove when the last file goes) is shared — only the located block UUID differs. Default (no phase_name/dst_path) behavior is unchanged.
- Because the two classes are distinct siblings under `PBXFileSystemSynchronizedExceptionSet`, the existing target-keyed `findExceptionSet` never matches a routing set and vice versa, so the two modes can't cross-contaminate.
- Registration required no change (tool was already wired in both servers).
- Tests: 5 added to `Tests/RemoveSynchronizedFolderExceptionToolTests.swift` (schema advertises the new params; remove whole routing set by dst_path; remove single membership file by phase_name; auto-remove routing set when last file removed; not-found when no routing set matches) — 16 total pass.

This completes the second half of pas-2jg's secondary gap: a `dstPath` routing set can now be removed standalone, not only as a side effect of removing its Copy Files phase.

---
# pas-2jg
title: Support declared input/output paths (and dependencyFile) on run-script build phases
status: completed
type: feature
priority: normal
created_at: 2026-07-26T07:06:18Z
updated_at: 2026-07-26T07:19:54Z
sync:
    github:
        issue_number: "436"
        synced_at: "2026-07-26T07:20:49Z"
---

## Problem

The project tools expose no way to set a `PBXShellScriptBuildPhase`'s incremental-build metadata: `inputPaths`, `outputPaths`, `inputFileListPaths`, `outputFileListPaths`, or `dependencyFile`. `add_build_phase` (phase_type `run_script`) accepts only `phase_name` + `script`; `list_run_script_phases` can *read* these fields (it reports `dependencyFile=<none>`, input/output paths) but nothing can *write* them, and there is no update/set tool for an existing run-script phase.

Consequence: a run-script phase with no declared outputs is always out-of-date and runs on every incremental build. There is no tool-driven path to make one skippable, and direct project-file edits are (correctly) blocked by the modification guard, so the whole class of "declare I/O so Xcode can skip this phase" fixes is unreachable.

This blocked the Thesis CSL resource-compression redesign (thesis ndp-5sj): the intended fix — declare the compress phase's source inputs + `.deflate` outputs (or a generated `.d` dependencyFile) so Xcode skips it when no style changed — could not be applied. It fell back to a script-level self-skip (still Xcode-invoked every build, just does ~0 work), which is strictly weaker than a real build-graph skip.

## Ask

Add tool support to set incremental metadata on a run-script phase, either as new params on `add_build_phase`/a new `add_run_script_phase`, or a dedicated setter (e.g. `set_run_script_phase_io`):

- `input_paths` (array)
- `output_paths` (array)
- `input_file_list_paths` (array, `.xcfilelist`)
- `output_file_list_paths` (array, `.xcfilelist`)
- `dependency_file` (path)
- `always_out_of_date` (bool) — already reported by list; expose a writer

## Secondary gap (related, lower priority)

Removing a Copy Files phase that is referenced by a synchronized-folder membership-exception set fails with a dangling-reference guard, and `remove_synchronized_folder_exception` only handles exclusion sets, not `dstPath` phase-routing sets (it reports "No exception set found"). So a raw Copy Files phase fed by a synced-folder routing exception cannot be removed via tools. Consider: teach `remove_copy_files_phase` to also drop the routing exception set that references the phase, and/or let `remove_synchronized_folder_exception` remove `dstPath` routing sets.

## Summary of Changes

Primary ask — new `set_run_script_phase_io` tool:

- Added `Sources/Tools/Project/SetRunScriptPhaseIOTool.swift`. Sets incremental-build metadata on an existing `PBXShellScriptBuildPhase`: `input_paths`, `output_paths`, `input_file_list_paths`, `output_file_list_paths`, `dependency_file`, and `always_out_of_date`.
- Only fields present in the request are modified (omitted → untouched). An empty array clears a paths field; an empty string clears `dependency_file`; empty `.xcfilelist` arrays are stored as `nil` so the key is omitted from `project.pbxproj`. A call that provides no I/O field is rejected with a clear error rather than a no-op "success".
- Locates the phase by name, treating an unnamed phase as the default `"ShellScript"` (mirrors `remove_run_script_phase`), and refuses ambiguous matches.
- Registered in both the monolithic server (`XcodeMCPServer.swift`) and the focused `xc-project` server (`ProjectMCPServer.swift`), including the monolith's workflow-category switch.
- Tests: `Tests/SetRunScriptPhaseIOToolTests.swift` (10 tests) covering set/clear/partial-update semantics, file-list paths, unnamed-phase matching, not-found, ambiguity, and validation.

Secondary gap — routing-exception cleanup on `remove_copy_files_phase`:

- `Sources/Tools/Project/RemoveCopyFilesPhase.swift` now drops any `PBXFileSystemSynchronizedGroupBuildPhaseMembershipExceptionSet` whose `buildPhase` references the phase being removed, detaching it from its sync group's `exceptions` and deleting the object. This clears the dangling-reference guard that previously made such phases unremovable. The success message reports how many routing sets were also removed.
- Sync groups are collected from the target's `fileSystemSynchronizedGroups` plus a recursive walk of the project's group tree (deduped by UUID).
- Test added to `Tests/CopyFilesPhaseToolTests.swift` (`Removes phase fed by a synchronized-folder routing exception set`).

Deferred: the other half of the secondary gap — teaching `remove_synchronized_folder_exception` to also remove `dstPath` phase-routing sets — was not implemented. The concrete blocker (removing a Copy Files phase fed by a routing exception) is resolved via `remove_copy_files_phase`, so the standalone-removal path is a lower-value follow-up.

---
# opn-8ec
title: Setter for Copy Files phase subpath (or rename-in-place)
status: completed
type: feature
priority: normal
created_at: 2026-06-03T16:40:57Z
updated_at: 2026-06-03T16:46:40Z
sync:
    github:
        issue_number: "383"
        synced_at: "2026-06-03T16:47:59Z"
---

## The gap

There's no way to change a Copy Files build phase's `dstPath` (subpath) after creation. The current tools support:
- `add_copy_files_phase` — creates a phase with a subpath
- `list_copy_files_phases` — reads them back
- `remove_copy_files_phase` — removes by `phase_name` (REQUIRED)
- `add_to_copy_files_phase` / `add_synchronized_folder_phase_membership` — populate

The missing operation is **mutate an existing phase's subpath in place**.

Workaround today is remove + recreate + relink. That fails when:
1. The phase has no name (`phase_name` required, no `dst_path` fallback like `add_synchronized_folder_phase_membership` has). Many phases in the wild are unnamed, especially auto-generated ones.
2. The phase has accumulated synchronized-folder membership exception sets across multiple targets — recreating loses those linkages until each is rebuilt explicitly.

## Concrete case

Thesis project, issue `02l-eb5`: DocX/CSL framework Copy Files phases use subpath `docx` / `csl`, which collide with the framework binary name (`DocX.framework/DocX` vs `DocX.framework/docx`) on case-insensitive APFS during iOS archive. Fix is to rename subpath to something case-distinct (e.g. `DefaultStyles`). Currently:

- `DocX` target has a NAMED phase "Copy Default Styles" with `dstPath: docx` — removable.
- `ThesisApp` target has an UNNAMED Copy Files phase with `dstPath: docx` — **not removable via xc-project** because `phase_name` is required.

The DocX framework subpath rename can be done by remove+add, but the ThesisApp side can't follow suit, leaving the Swift lookup site (`Bundle.main.url(..., subdirectory: ...)`) needing two different subdirectory values per call — ugly.

## Proposed fix

Highest leverage: add a setter.

```
mcp__xc-project__set_copy_files_phase_subpath
  project_path
  target_name
  phase_name?     (one of these)
  dst_path?       (one of these — locates the phase the same way add_synchronized_folder_phase_membership does)
  new_subpath
```

Bonus: while in there, give `remove_copy_files_phase` the same `dst_path` alternate identifier so unnamed phases become addressable.

## Adjacent gap

`add_copy_files_phase` accepts `subpath` but no setter exists post-hoc. Consistent with the pattern of "every create-time-only param eventually needs a setter for rename/refactor passes." Worth a sweep.



## Summary of Changes

- Added `set_copy_files_phase_subpath` tool that mutates a Copy Files build phase's `dstPath` in place, locating the phase by `phase_name`, `dst_path`, or as the target's sole Copy Files phase. Preserves phase identity, files, name, destination, and synchronized-folder membership exception sets.
- Extended `remove_copy_files_phase` to accept `dst_path` as an alternate locator and made `phase_name` optional, mirroring `add_synchronized_folder_phase_membership`. Unnamed phases (e.g. auto-generated app-side Copy Files phases) are now removable.
- Extracted shared phase-lookup logic into `CopyFilesPhaseLocator` (Sources/Tools/Project/).
- Registered the new tool in both `xc-project` and the monolithic `xc-mcp` servers.
- Updated existing tests for the new schema (phase_name no longer required; lookup misses now throw `MCPError` instead of returning a result) and added four new tests covering rename by name, rename of unnamed phases via `dst_path`, ambiguous `dst_path` rejection, and `dst_path`-based removal. All 53 CopyFilesPhase tests pass.

Not done: the issue's "adjacent gap" sweep for other create-time-only params (e.g. `add_copy_files_phase`'s `destination`). Out of scope here — file a follow-up if needed.

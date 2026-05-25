---
# 44g-dgh
title: add_synchronized_folder_exception targets wrong sync group when leaf path is ambiguous
status: completed
type: bug
priority: high
created_at: 2026-05-25T16:18:43Z
updated_at: 2026-05-25T16:26:10Z
sync:
    github:
        issue_number: "334"
        synced_at: "2026-05-25T16:26:59Z"
---

## Summary

`add_synchronized_folder_exception` attaches the new exception set to the **wrong** `PBXFileSystemSynchronizedRootGroup` when multiple synchronized folders share the same leaf `path` (e.g. every module has a `Sources` folder). It also cannot be disambiguated via a full/relative path. The same leaf-name ambiguity affects `list_synchronized_folder_exceptions` and `remove_synchronized_folder_exception`.

## Reproduction (Thesis.xcodeproj)

The project has 16 distinct sync root groups all with `path = Sources` (one per module: Core, App, BibTeX, etc.).

1. `list_synchronized_folder_exceptions(folder_path: "Core/Sources")` → `Synchronized folder 'Core/Sources' not found` (full path not supported).
2. `add_synchronized_folder_exception(folder_path: "Sources", target_name: "Core", files: ["Dependency/Documentation.docc"])` → reports success.

## Actual behavior

The created exception set has the correct `target = Core`, but it was inserted into the **App** `Sources` sync group (the one already holding TestApp's `ThesisApp.swift` exception), NOT Core's `Sources` group (the one listed in the Core target's `fileSystemSynchronizedGroups`).

Because `membershipExceptions` paths resolve relative to the group they live in, `Dependency/Documentation.docc` resolved against `App/Sources/...` (nonexistent) and had no effect. The intended exclusion silently failed — the duplicate DocC catalog still built and the "Multiple commands produce Core.doccarchive" error persisted.

Looks like the tool matches sync groups by leaf `path` only and picks the first match / the one that already has an `exceptions` array, ignoring `target_name` for group selection (it's only used to fill the exception set's `target` field).

## Expected behavior

- When `target_name` is provided, select the sync root group that is actually a member of that target's `fileSystemSynchronizedGroups`.
- Accept a full/relative project path (e.g. `Core/Sources`) so callers can disambiguate folders that share a leaf name. Apply the same disambiguation to `list_` and `remove_` variants.
- Error (not silently mis-target) when `folder_path` is ambiguous and no target/path disambiguation resolves it.

## Workaround used

Relocated the offending catalog out of the synchronized folder on disk instead of using an exception set.


## Summary of Changes

Reworked `SynchronizedFolderUtility` into a disambiguating resolver:

- `collectSyncGroups(in:parentPath:)` walks the group tree and records each `PBXFileSystemSynchronizedRootGroup` with its **full project path** (e.g. `Core/Sources`).
- `resolveSyncGroup(folderPath:target:in:)` matches by leaf path, exact full path, or trailing component suffix; when a target is supplied it narrows candidates to that target's `fileSystemSynchronizedGroups` (the source of truth), and throws an explicit ambiguity error (listing candidate full paths) when it still cannot resolve to one group.
- `add_`/`remove_synchronized_folder_exception` now resolve the target first and pass it in, so the exception set attaches to the group actually bound to the target — fixing the silent mis-targeting.
- `list_synchronized_folder_exceptions` uses the same resolver (no target), so it accepts full paths and errors on ambiguity instead of returning "not found".

Added `TestProjectHelper.createTestProjectWithAmbiguousSyncFolders` and 7 tests covering target-based disambiguation, full-path disambiguation, and ambiguity errors across all three tools. All 29 SynchronizedFolderException tests pass.

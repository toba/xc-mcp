---
# qlc-4j9
title: remove_target leaves orphaned PBXTargetDependency/PBXContainerItemProxy when removing a dependent target
status: completed
type: bug
priority: normal
created_at: 2026-06-28T20:40:58Z
updated_at: 2026-06-28T20:46:25Z
sync:
    github:
        issue_number: "404"
        synced_at: "2026-06-28T20:47:29Z"
---

## Summary

`remove_target` on a **dependent** target (e.g. a unit-test bundle that depends on an app target) leaves orphaned `PBXTargetDependency` and `PBXContainerItemProxy` objects behind. The removed target's own *outgoing* dependency edge is not deleted. The orphan keeps pointing at the depended-on target, and later **blocks removal of that target**: the safe-write validation refuses with `write would introduce dangling object reference(s) …`.

## Repro

In a project where `AdminAppTests` (unit-test bundle) depends on `AdminApp` (app), and `AdminApp` depends on `AdminCore` (framework):

1. `remove_target(AdminAppTests, cascade: true)` → succeeds. But it leaves behind:
   - `PBXTargetDependency` `878E5F9D…` `{ name = AdminApp; target = <AdminApp id>; targetProxy = B36A8DDA… }`
   - `PBXContainerItemProxy` `B36A8DDA…` `{ remoteGlobalIDString = <AdminApp id>; remoteInfo = AdminApp }`

   Neither is referenced by any live target's `dependencies = (...)` array — they are pure orphans.
2. `remove_target(AdminApp, cascade: true)` → **fails**:
   ```
   Refusing to write an invalid project file: write would introduce dangling
   object reference(s) <AdminApp id>, B36A8DDA… — refusing to write a project
   Xcode could not load. The original file was left unchanged.
   ```
   Because the orphaned dependency + proxy still reference AdminApp.

## Expected

When `remove_target` removes a target, it must also delete that target's **own outgoing** `PBXTargetDependency` objects and their associated `PBXContainerItemProxy` objects — not just unlink the target from the project's `targets` list. Removing a dependent should leave no edges pointing out of it.

## Notes / impact

- The new pre-write validation that refuses to emit a dangling-reference project file is **working correctly and is a great safety net** — it caught this instead of corrupting the file. The bug is upstream: the orphan should never have been created.
- `repair_project` (dry run) reports **"No issues found"** — it does not detect orphaned `PBXTargetDependency` / `PBXContainerItemProxy` objects. Consider teaching `repair_project` to garbage-collect dependency edges/proxies whose owning target or whose `target`/`remoteGlobalIDString` no longer exists, so users can recover a project already left in this state without a manual git restore.
- **Workaround:** remove targets depended-on-first. Removing `AdminApp` (the depended-on app) *before* `AdminAppTests` lets `cascade` clean the test's incoming edge via the correct code path; the orphan only appears when the dependent is removed first.

## Suggested fixes

1. In `remove_target`: enumerate and delete the target's outgoing `PBXTargetDependency` objects + their `PBXContainerItemProxy` objects as part of removal.
2. In `repair_project`: add a pass that removes `PBXTargetDependency` objects not referenced by any target's `dependencies` array, and `PBXContainerItemProxy` objects not referenced by any dependency/build-file, plus any whose `remoteGlobalIDString`/`target` points to a non-existent object.

## Summary of Changes

1. **`TargetGraphCleanup.removeReferences`** now also deletes the target's *own outgoing*
   `PBXTargetDependency` objects and their `PBXContainerItemProxy` objects, and clears its
   `dependencies` array. Previously only *incoming* edges (other targets depending on this one)
   were cleaned, so removing a dependent target (e.g. a test bundle) stranded its outgoing edge as
   an orphan that later blocked removal of the depended-on target. Both `remove_target` and
   `remove_app_extension` funnel through this helper, so both are fixed.

2. **`repair_project`** gained a garbage-collection pass that removes `PBXTargetDependency` objects
   not referenced by any target's `dependencies` array (or whose `target` is gone) and
   `PBXContainerItemProxy` objects not referenced by any dependency/reference-proxy (or whose remote
   object is gone). This lets users recover a project already left in the orphaned state without a
   git restore.

Tests: added `Remove dependent target cleans up its own outgoing dependency and proxy` (verifies no
dangling reference survives and the depended-on target can then be removed) and
`Garbage-collects orphaned target dependency and proxy objects` for `repair_project`.

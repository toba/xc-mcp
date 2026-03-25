---
# 7o0-o68
title: remove_target leaves orphaned PBXContainerItemProxy and PBXTargetDependency entries
status: completed
type: bug
priority: normal
created_at: 2026-03-25T01:45:36Z
updated_at: 2026-03-25T01:50:49Z
sync:
    github:
        issue_number: "237"
        synced_at: "2026-03-25T01:51:32Z"
---

## Problem

When `remove_target` removes a target from the Xcode project, it cleans up the target definition, build configurations, framework link phases, and embed phases — but leaves behind orphaned:

- **PBXContainerItemProxy** entries that referenced the removed target (`remoteGlobalIDString` still points to the deleted target ID)
- **PBXTargetDependency** entries that referenced the removed target (both `target` and `targetProxy` fields point to stale IDs)

These are the dependency records that other targets used to express "I depend on target X". When target X is removed, `remove_target` should also scan for and remove any PBXTargetDependency whose `target` field matches the removed target's ID, plus the associated PBXContainerItemProxy entries.

## Reproduction

1. Have a project with target A depending on target B (B listed in A's `dependencies` array)
2. Call `remove_target` for target B
3. Observe: the PBXTargetDependency and PBXContainerItemProxy objects referencing B remain in the pbxproj, though the reference from A's `dependencies` array may be removed

## Expected

`remove_target` should:
- Remove all PBXTargetDependency entries where `target = <removed target ID>`
- Remove all PBXContainerItemProxy entries where `remoteGlobalIDString = <removed target ID>`
- Remove references to those PBXTargetDependency entries from any target's `dependencies` array

## Observed In

Removing GRDBQuery target from Thesis.xcodeproj — had to manually delete 2 PBXContainerItemProxy and 2 PBXTargetDependency entries after `remove_target` ran.


## Summary of Changes

Fixed `remove_target` to clean up orphaned PBXTargetDependency and PBXContainerItemProxy objects when a target is removed.

### Changes

- **RemoveTargetTool.swift**: When removing dependencies from other targets, now also deletes the `PBXTargetDependency` objects and their associated `PBXContainerItemProxy` from the project. Additionally scans for any remaining `PBXContainerItemProxy` entries whose `remoteGlobalID` matches the removed target. Also improved target lookup to use `project.targets` (all target types) instead of `nativeTargets` only.
- **RemoveTargetToolTests.swift**: Added test that creates a real dependency (AppTarget → LibTarget with PBXTargetDependency + PBXContainerItemProxy), removes LibTarget, and verifies both dependency objects are cleaned up.

---
# rm2-isk
title: remove_target leaves orphaned references in project.pbxproj
status: completed
type: bug
priority: normal
created_at: 2026-05-27T03:58:24Z
updated_at: 2026-06-03T00:19:18Z
sync:
    github:
        issue_number: "347"
        synced_at: "2026-06-03T01:54:37Z"
---

## Summary

`mcp__xc-project__remove_target` removes the PBXNativeTarget and its product/build-file references, but leaves several orphaned objects behind, requiring manual pbxproj surgery to fully excise a target.

## Reproduction

In the Thesis project, removing a scaffold framework target `TableView` (and its `TableViewTests`) via `remove_target` left the following orphans in `Thesis.xcodeproj/project.pbxproj`:

1. **Dangling `PBXTargetDependency`** — a `PBXTargetDependency` whose `target = <removed target>` and `targetProxy = <PBXContainerItemProxy>` remained (the proxy def itself had already been removed, leaving the dependency referencing a missing proxy). It was not referenced by any surviving target's `dependencies` array, i.e. fully orphaned.
2. **Orphaned `PBXGroup`** — the target's source group (`/* TableView */`) and its child `PBXFileSystemSynchronizedRootGroup`s (`Sources`, `Tests`) plus a `Documentation.docc` `PBXFileReference` were left, still listed as children of the parent `Components` group.
3. **Test-plan membership** — entries in `*.xctestplan` files referencing the removed test target (by identifier + name) were left behind, producing 'missing target' warnings.

## Expected

`remove_target` should cascade-remove:
- any `PBXTargetDependency` (+ its `PBXContainerItemProxy`) pointing at the removed target, and the entry in the depending target's `dependencies` list
- the target's `PBXGroup`/synchronized-root-group + child file refs (when not shared with another target) and its membership in the parent group's `children`
- optionally, surface a warning that `.xctestplan` files may still reference the removed target (these live outside the pbxproj)

## Notes

`validate_project` did not flag the dangling dependency or orphaned group afterward; consider adding checks for target-dependencies/proxies pointing at non-existent targets and for PBXGroups with no reachable target membership.

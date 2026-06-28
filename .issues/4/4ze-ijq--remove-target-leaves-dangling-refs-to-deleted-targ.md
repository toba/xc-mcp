---
# 4ze-ijq
title: remove_target leaves dangling refs to deleted target; add universal dangling-reference write-gate
status: completed
type: bug
priority: high
created_at: 2026-06-28T20:02:04Z
updated_at: 2026-06-28T20:29:31Z
sync:
    github:
        issue_number: "403"
        synced_at: "2026-06-28T20:30:30Z"
---

## Root cause (reproduced)

`remove_target AdminAppTests` on the thesis project leaves two dangling references to the deleted target 9624FE0E after the write:
- a `PBXFileSystemSynchronizedBuildFileExceptionSet` whose `target` is the removed target
- the `PBXProject.attributes.TargetAttributes` entry keyed by the removed target's UUID

A synchronized-folder exception set pointing at a non-existent target is the 'project won't load / crashes on open' class. The tool's post-op validator only scans .xctestplan/.xcscheme files for danglers, never the pbxproj itself, so it wrote a broken project and reported success.

Separately confirmed NON-issues: no framework data loss (the dropped build files were AdminAppTests's own link entries; the framework file references survive), and the large diff is cosmetic XcodeProj serializer churn (reproduces on a zero-mutation round-trip).

## Fix (correctness now, churn later)

- [x] Universal dangling-reference write-gate (PBXProjReferenceAudit, wired into SafeProjectWrite). Delta-based (newDanglingReferences vs on-disk baseline) so pre-existing/cross-project refs never block; excludes remoteGlobalIDString (legitimately cross-project).
- [x] Complete remove_target cleanup via shared TargetGraphCleanup helper (dependencies+proxies, container proxies, TargetAttributes, synchronized exception sets).
- [x] remove_target gains `cascade` param; refuses by default when another target depends on/embeds it. Same block-when-deps-remain applied to remove_swift_package (remove_from_targets=false now refuses if still used instead of leaving a dangling package ref).
- [x] Regression tests (PBXProjReferenceAuditTests + RemoveTargetTool exception-set/attributes + refusal tests; updated app-extension/package/cross-project tests).


## Summary of Changes

The gate also caught the SAME dangling-reference bug in `remove_app_extension` (orphaned PBXTargetDependency objects never deleted) and `remove_swift_package` (remove_from_targets=false). Both fixed via the shared `TargetGraphCleanup` helper / block-when-deps-remain refusal. Full suite: 1420 passed, 0 failed.

Confirmed non-issues: no framework data loss in the original incident (dropped build files were AdminAppTests's own link entries; the framework file references survive); the large diff was cosmetic XcodeProj serializer churn (reproduces on a zero-mutation round-trip) — deferred to a separate text-surgery effort.

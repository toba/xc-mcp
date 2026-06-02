---
# mhr-842
title: 'xc-project: cross-project add_dependency (PBXContainerItemProxy via fileReference to another .xcodeproj)'
status: completed
type: feature
priority: high
created_at: 2026-06-02T20:24:18Z
updated_at: 2026-06-02T20:28:33Z
sync:
    github:
        issue_number: "376"
        synced_at: "2026-06-02T20:31:16Z"
---

Hit while resolving thesis rzc-et2. add_dependency rejects cross-project targets with 'Dependency target not found in project':

  add_dependency(Thesis.xcodeproj, target=Core, dep=GRDBCustom)
  -> Dependency target 'GRDBCustom' not found in project

But Core links GRDBCustom across project boundaries: list_frameworks_phase(Core) shows

  GRDB.framework [kind=crossProject remoteGlobalID=F3BA805A1CFB2BB2003DC1BA remoteInfo=GRDBCustom containerPortal=fileReference(GRDB/GRDBCustom.xcodeproj) proxy=961FA21F2EDD34EE003CF903] ⚠ no PBXTargetDependency edge

So the build planner has no ordering edge to schedule GRDBCustom-for-iOS before Core-for-iOS during an iOS archive, and macOS-built GRDB modules leak in (the original rzc-et2 bug).

## Capability needed

add_dependency should accept cross-project deps when the consumer project already has a PBXFileReference to another .xcodeproj (the existing 'GRDB/GRDBCustom.xcodeproj' fileReference here). The tool should:

1. Look up the cross-project fileReference by name OR explicit path argument.
2. Read the remote project to find the named native target's guid + the canonical product name.
3. Create a PBXContainerItemProxy with containerPortal=<fileReference>, remoteGlobalIDString=<remote guid>, remoteInfo=<dep name>, proxyType=1.
4. Create a PBXTargetDependency with name + targetProxy.
5. Append to the consumer target's dependencies list.

Suggested signature: keep current add_dependency(project_path, target_name, dependency_name) and either:
- Auto-detect cross-project by walking the consumer project's fileReferences for any .xcodeproj that exposes a target with that name; or
- Add optional cross_project_path (e.g. 'Storage/GRDB/GRDBCustom.xcodeproj') to disambiguate.

## Why now

rzc-et2 is at the finish line: the duplicate-graph-node error is fixed (Crossref->Core PBXTargetDependency added via existing add_dependency). The remaining iOS-archive failure is exactly this missing Core->GRDBCustom cross-project edge. Without this MCP capability, the only way to add it is a hand edit of the pbxproj — exactly what xc-mcp exists to avoid.

## Related

- thesis rzc-et2 (paused at this gap)
- xc-mcp 7nu-9z7 (list_dependencies / remove_dependency - shipped)
- xc-mcp 0rc-1oh (list_frameworks_phase / dump_pif / why_target_id - shipped; surfaced this asymmetry)
- xc-mcp 7j5-2sm (doctor: detect duplicate edges + stale remoteInfo)

## Doctor follow-up

Doctor should ALSO flag any cross-project framework link in PBXFrameworksBuildPhase that lacks a matching PBXTargetDependency edge (the 'no PBXTargetDependency edge' annotation list_frameworks_phase already prints is the structural anti-pattern).



## Summary of Changes

- `Sources/Tools/Project/AddDependencyTool.swift`: when `dependency_name` is not a native target of the consumer project, fall back to scanning `rootObject.projects` (the consumer's `projectReferences`). For each `ProjectRef` PBXFileReference, resolve its absolute path via `fullPath(sourceRoot:)`, open the remote `.xcodeproj`, and look for a `PBXNativeTarget` whose `name` matches. Optional `cross_project_path` argument (absolute path, path relative to the consumer project's source root, or a trailing suffix like `GRDB/GRDBCustom.xcodeproj`) disambiguates when multiple referenced sub-projects expose a target with that name.
- On a unique match, create a `PBXContainerItemProxy` with `containerPortal=.fileReference(<projectRef>)`, `remoteGlobalID=.string(<remoteTargetUUID>)`, `proxyType=.nativeTarget`, `remoteInfo=<dependencyName>`, then a `PBXTargetDependency(name:, target: nil, targetProxy:)` (no local `target` reference since the dependency lives in a different .pbxproj). Append to the consumer target's `dependencies`. Duplicate detection compares the existing portal+remoteUUID pair so re-running the tool reports `already depends on`.
- Zero matches yields the existing 'not found' message but mentions both the project and sub-project scopes (and echoes `cross_project_path` when supplied). Multiple matches return a list and ask the caller to disambiguate.
- In-project behavior is unchanged; the in-project branch was extracted into a helper for readability.
- `Tests/AddDependencyToolTests.swift`: new test `Add cross-project dependency via projectReferences` that creates a consumer project, a sibling sub-project, wires the sub-project into `rootObject.projects`, invokes `add_dependency`, and asserts the resulting `PBXTargetDependency` has `target == nil`, `proxyType == .nativeTarget`, `remoteInfo == "SubFramework"`, `containerPortal == .fileReference(<Sub.xcodeproj>)`, and `remoteGlobalID.string == <sub target UUID>`. A second call returns `already depends on`.

Not in scope here: the doctor follow-up (cross-project link in `PBXFrameworksBuildPhase` lacking a matching `PBXTargetDependency` edge) — `list_frameworks_phase` already annotates the anti-pattern; promoting that into a `validate_project` finding is left to a follow-up issue if needed.

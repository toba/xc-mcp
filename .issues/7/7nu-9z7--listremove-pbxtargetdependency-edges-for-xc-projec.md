---
# 7nu-9z7
title: list/remove PBXTargetDependency edges for xc-project
status: completed
type: feature
priority: high
created_at: 2026-06-02T19:07:02Z
updated_at: 2026-06-02T19:15:34Z
sync:
    github:
        issue_number: "371"
        synced_at: "2026-06-02T19:16:31Z"
---

Working on thesis issue rzc-et2 (iOS scheme leaks macOS Core build via duplicate Core dependency edge). The fix requires:

1. **List PBXTargetDependency edges per target** — walk each of ThesisApp's explicit target deps to find which integration framework re-exposes Core, producing two paths from ThesisApp → Core.
2. **Remove a specific PBXTargetDependency edge** between two targets (without nuking the framework link in Frameworks build phase, and without touching Core itself).

xc-project currently exposes:
- add_dependency(target, dependency) — creates PBXTargetDependency edge
- remove_framework(target, framework_name) — removes from Frameworks build phase but NOT the PBXTargetDependency edge
- list_files, list_package_products, list_copy_files_phases, etc.

What's missing:
- list_dependencies(target) — return the PBXTargetDependency entries for a target (target name + remote info + container portal). Equivalent of the "Target Dependencies" section of the General tab.
- remove_dependency(target, dependency) — drop a specific PBXTargetDependency edge by target+dependency name (the inverse of add_dependency).

mcp__xc-build__show_build_dependency_graph only lists targets defined directly in the scheme (returned 'Targets (1): ThesisApp' for the iOS scheme — no transitive expansion), so it can't be used as a substitute.

## Why now

rzc-et2 is high-priority and blocks thesis-xsh0 (Xcode Cloud Workflow D 'iOS archive → TestFlight'). Without these two tools the only path is hand-editing project.pbxproj, which is error-prone and exactly what xc-project exists to avoid.

## Suggested API

list_dependencies(project_path, target_name) -> [{name, target_id, proxy_type}]
remove_dependency(project_path, target_name, dependency_name)

Both should round-trip cleanly with the existing add_dependency (same PBXContainerItemProxy + PBXTargetDependency representation).



## Summary of Changes

Added two PBXTargetDependency tools (round-trip with existing add_dependency):

- `list_dependencies(project_path, target_name)` — lists each PBXTargetDependency edge with its uuid, proxyType, remoteGlobalID, remoteInfo, and containerPortal (project / fileReference).
- `remove_dependency(project_path, target_name, dependency_name)` — drops only the PBXTargetDependency edge and its PBXContainerItemProxy. Leaves Frameworks build phase and the dependency target untouched. Matches by linked target, dep.name, or proxy.remoteInfo.

### Files

- New: `Sources/Tools/Project/ListDependenciesTool.swift`, `Sources/Tools/Project/RemoveDependencyTool.swift`
- New tests: `Tests/ListRemoveDependencyToolTests.swift` (8 tests, all passing)
- Wired into both servers: `Sources/Servers/Project/ProjectMCPServer.swift` and `Sources/Server/XcodeMCPServer.swift` (enum case, instantiation, list, switch, plus workflow grouping in the monolith).
- Added to `Sources/Core/ServerToolDirectory.swift` so cross-server hints resolve to xc-project.

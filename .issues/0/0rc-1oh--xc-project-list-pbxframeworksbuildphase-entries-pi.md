---
# 0rc-1oh
title: 'xc-project: list PBXFrameworksBuildPhase entries + PIF dump for diagnosing duplicate build-graph nodes'
status: completed
type: feature
priority: high
created_at: 2026-06-02T19:38:41Z
updated_at: 2026-06-02T19:45:44Z
sync:
    github:
        issue_number: "373"
        synced_at: "2026-06-02T20:02:36Z"
---

Hit this gap while diagnosing thesis rzc-et2. After exhausting the dependency-edge audit (list_dependencies / remove_dependency / add_dependency from 7nu-9z7), the duplicate Core build-graph node persisted with identical hash:

target-Core-2bace2f0c1ca98ebcd37f9b1dbb86b48cb3942481f4b12fa08e59af2d729e00c-SDKROOT:iphonesimulator:SDK_VARIANT:iphonesimulator

So PBXTargetDependency edges aren't the only path that produces a graph node. To diagnose further, two MCP tools are missing:

## 1. list_frameworks_phase(target_name)

Return the contents of a target's PBXFrameworksBuildPhase: each PBXBuildFile entry with whether it references a fileRef (local PBXFileReference), productRef (PBXReferenceProxy -> another target's product), or a cross-project reference. Reveals cases where one consumer reaches Core via target dep + frameworks-phase link, while another reaches Core only via frameworks-phase link (no ordering edge) - which is the asymmetry hypothesized in rzc-et2 (Crossref has zero PBXTargetDependency edges but its sources import Core, so it must be linking via the frameworks phase).

Suggested output:

list_frameworks_phase(project_path, target_name) -> [
  {file: 'Core.framework', kind: 'productRef'|'fileRef'|'crossProject', target_uuid, proxy_uuid},
  ...
]

## 2. PIF / build-graph dump or 'why duplicate' helper

When the xc-build/xc-simulator tools report 'Multiple targets in the build graph have the target ID X', a tool that walks the project + scheme and reports which (target, configuration, SDK) tuples could produce that identifier would be invaluable. Suggestion: a 'why' command that takes a target id hash from the error and reports the contributing graph paths, or a thin wrapper exposing -showBuildSettings -json (via xc-build, not Bash) for a scheme/SDK so contributors can be compared.

## Related

- thesis rzc-et2 (paused at this gap)
- xc-mcp 7nu-9z7 (list_dependencies / remove_dependency - shipped)
- xc-mcp 7j5-2sm (doctor: detect duplicate PBXTargetDependency + stale remoteInfo)



## Summary of Changes

Shipped **#1 list_frameworks_phase** and a related **validate_project** enhancement that catches the link-only asymmetry rzc-et2 was hunting for. Deferred **#2 PIF / why-duplicate helper** as a separately-scoped issue (bvd-v5s) because reproducing Xcode's internal target-ID hash / dumping PIF needs its own design.

### New tool

- `list_frameworks_phase(project_path, target_name)` (xc-project): lists each PBXFrameworksBuildPhase entry, classifying as `fileRef` (local file / system framework), `productRef` (SPM `XCSwiftPackageProductDependency`), `crossProject` (`PBXReferenceProxy` → another project's product), or `dangling`. crossProject entries that have no matching `PBXTargetDependency` edge are marked inline with "⚠ no PBXTargetDependency edge".

### Doctor (validate_project) enhancement

- New per-target check `checkReferenceProxyWithoutDependency`: emits a `[warn]` when a Frameworks phase links a target via PBXReferenceProxy but has no PBXTargetDependency edge for the same remote target. The link still produces a build-graph node for the remote target, so this is the exact asymmetry that can produce duplicate target-ID nodes under the explicit-modules planner — Crossref-reaches-Core-via-link-only in the rzc-et2 hypothesis.

### Files

- New: `Sources/Tools/Project/ListFrameworksPhaseTool.swift`
- New: `Tests/ListFrameworksPhaseToolTests.swift` (5 tests, including a hand-built PBXReferenceProxy cross-project entry that exercises both the new tool and the validate_project warning)
- Updated: `Sources/Tools/Project/ValidateProjectTool.swift` (new private check + wiring)
- Updated: `Tests/ValidateProjectToolTests.swift` is unchanged; the crossProject case is covered by the new test file.
- Wired into both servers: `Sources/Servers/Project/ProjectMCPServer.swift` and `Sources/Server/XcodeMCPServer.swift` (enum case, instantiation, list, switch, workflow grouping).
- Added `list_frameworks_phase` (and missing `remove_framework`) to `Sources/Core/ServerToolDirectory.swift`.

### Deferred

- bvd-v5s: PIF / `why_target_id` helper for diagnosing duplicate build-graph nodes whose root cause isn't in the .pbxproj (PIF-level).

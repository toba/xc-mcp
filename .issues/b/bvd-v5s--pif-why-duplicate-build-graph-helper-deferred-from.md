---
# bvd-v5s
title: PIF / 'why duplicate' build-graph helper (deferred from 0rc-1oh)
status: completed
type: feature
priority: high
created_at: 2026-06-02T19:45:16Z
updated_at: 2026-06-02T20:01:42Z
sync:
    github:
        issue_number: "374"
        synced_at: "2026-06-02T20:02:36Z"
---

Deferred from 0rc-1oh #2.

When xc-build / xc-simulator surface a 'Multiple targets in the build graph have the target ID target-<Name>-<hash>-SDKROOT:<sdk>:SDK_VARIANT:<sdk>' error, a tool that walks the project + scheme and reports which (target, configuration, SDK) tuples could produce that identifier would be invaluable. Two possible shapes:

1. **why_target_id(error_id)**: takes the target-ID hash from the error and reports the contributing graph paths. Requires reproducing Xcode's internal hash algorithm (SHA-256 over target name + selected build settings + SDK), which is not officially documented and may drift across Xcode versions.

2. **dump_pif(project, scheme, sdk)**: a thin wrapper that triggers Xcode's PIF (Project Interchange Format) generation and surfaces it as JSON. PIF is Xcode's internal build-graph format used between IDE and XCBuild; there's no public documentation but the artifacts can be found under `~/Library/Developer/Xcode/DerivedData/<scoped>/Build/Intermediates.noindex/XCBuildData/`.

`show_build_dependency_graph` already exists but only lists targets defined directly in the scheme (no transitive expansion), so it's not a substitute.

## Why deferred from 0rc-1oh

The list_frameworks_phase tool + the validate_project link-only check shipped in 0rc-1oh diagnose most of the cases that produce duplicate target-ID errors (PBXReferenceProxy without dependency, duplicate PBXTargetDependency edges, stale remoteInfo). The remaining 10% — where the duplication comes from PIF-level resolution that can't be inferred from pbxproj alone — needs its own design and is large enough to be its own issue.

## Related

- xc-mcp 0rc-1oh (parent — list_frameworks_phase + link-only check shipped)
- xc-mcp 7j5-2sm (duplicate dependency / stale remoteInfo checks)
- xc-mcp 7nu-9z7 (list/remove_dependency)
- thesis rzc-et2 (the use case)



## Plan

### Approach

The PIF cache () is written by Xcode after every build and contains the exact target GUIDs that appear in the 'Multiple targets in the build graph' error. The 64-char target hash from the error is the top-level `guid` field of a target's PIF JSON. Targets within the same .xcodeproj share a 32-char prefix that matches the project's `guid`.

So instead of reproducing Xcode's hashing algorithm, the tools just read the on-disk cache.

### Implementation

1. **`Sources/Core/PIFCacheReader.swift`** — pure-Swift utility:
   - Locates the most recent PIFCache for a given .xcodeproj path (`~/Library/Developer/Xcode/DerivedData/<ProjectName>-*/Build/Intermediates.noindex/XCBuildData/PIFCache/`), optionally taking an explicit `derived_data_path` override.
   - Indexes `target/*-json` files by top-level `guid` for fast lookup.
   - Surfaces parsed JSON as `[String: Any]` (or a minimal typed wrapper for the fields the tools use).

2. **`Sources/Tools/Project/DumpPIFTool.swift`** — `dump_pif(project_path, scope?: workspace|project|target, name?: <project_or_target_name>, derived_data_path?: ..., raw?: bool)`:
   - With no scope: returns a summary (workspace + projects + target counts).
   - With scope=target, name=Core: returns the matching target JSON (raw or summarized).
   - Includes a 'cache freshness' note (mtime of newest file) and a hint to build if cache is missing.

3. **`Sources/Tools/Project/WhyTargetIdTool.swift`** — `why_target_id(project_path, target_id, derived_data_path?: ...)`:
   - Parses target_id from either the raw 64-char hash or the full `target-<Name>-<hash>-SDKROOT:<sdk>:SDK_VARIANT:<sdk>` string.
   - Scans all target JSONs for matching `guid`. If multiple match → that's the duplicate-build-graph-node smoking gun.
   - For each match, reports project name + path, target name + product type, dependencies that point at the same GUID (and from which targets).

4. **Wiring**: both tools added to `ProjectMCPServer` enum, lookups, registration; mirrored in `XcodeMCPServer`; `ServerToolDirectory.projectTools` updated.

5. **Tests**: `Tests/DumpPIFToolTests.swift` + `Tests/WhyTargetIdToolTests.swift`. Construct fake PIFCache directory under a temp dir with hand-written workspace/project/target JSONs that include a deliberate duplicate target guid (two distinct projects both listing a target with the same Core guid), and verify both tools surface the collision.



## Summary of Changes

Shipped both tool shapes (`why_target_id` + `dump_pif`) on a shared `PIFCacheReader` that reads Xcode's on-disk PIFCache. Hash reproduction wasn't needed — the 64-char target-ID hash from `'Multiple targets in the build graph have the target ID …'` errors is literally the top-level `guid` field of a target's PIF JSON, written by Xcode to `<DerivedData>/<Project>-<hash>/Build/Intermediates.noindex/XCBuildData/PIFCache/target/` after every build.

### New utility

- `Sources/Core/PIFCacheReader.swift` — locates the most-recent matching DerivedData directory, indexes `workspace/`, `project/`, `target/` JSONs, groups targets by guid (a group with >1 entry is the duplicate build-graph node), and maps each target cache filename back to the project(s) that list it. Pure read-only; throws structured errors for `derivedDataNotFound` / `cacheMissing` / `decode`. `extractGuid(from:)` pulls the 64-char hash out of either the raw guid or the full `target-<Name>-<hash>-SDKROOT:<sdk>` string.

### New tools (xc-project)

- `dump_pif(project_path, scope?: summary|target|project|workspace, name?, derived_data_path?)` — summary lists workspaces/projects/targets and flags duplicate guids inline; scoped modes return the raw PIF JSON for inspection.
- `why_target_id(project_path, target_id, derived_data_path?)` — accepts the raw guid or the full error string, surfaces every PIF target with that guid plus the project(s) declaring them and every target that depends on the guid. >1 match = the colliding build-graph nodes.

### Files

- New: `Sources/Core/PIFCacheReader.swift`
- New: `Sources/Tools/Project/DumpPIFTool.swift`
- New: `Sources/Tools/Project/WhyTargetIdTool.swift`
- New: `Tests/PIFCacheReaderTests.swift` (6 tests + shared `TestPIFCacheFixture` builder)
- New: `Tests/DumpPIFToolTests.swift` (5 tests)
- New: `Tests/WhyTargetIdToolTests.swift` (5 tests)
- Wired into both servers: `Sources/Servers/Project/ProjectMCPServer.swift`, `Sources/Server/XcodeMCPServer.swift`
- `Sources/Core/ServerToolDirectory.swift`: added `dump_pif`, `why_target_id` to `projectTools`

### Verification

16 new tests + 25 sibling project tests pass (`PIFCacheReaderTests|DumpPIFToolTests|WhyTargetIdToolTests|ListFrameworksPhaseToolTests|ValidateProjectToolTests`). Fixture construction includes a deliberate duplicate target guid (two distinct projects each listing a `Core` target with the same guid) plus a consumer target that depends on that guid — exercises the duplicate-detection, project-lookup, and consumer-trace paths.

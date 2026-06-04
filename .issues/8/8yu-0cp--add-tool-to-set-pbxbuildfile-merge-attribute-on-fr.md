---
# 8yu-0cp
title: Add tool to set PBXBuildFile Merge attribute on frameworks phase
status: completed
type: task
priority: normal
created_at: 2026-06-04T18:04:39Z
updated_at: 2026-06-04T18:10:17Z
sync:
    github:
        issue_number: "388"
        synced_at: "2026-06-04T18:36:57Z"
---

Discovered while working Thesis hlz-txs (unify static-vs-dynamic strategy for Mergeable Libraries).

`xc-project` MCP has no tool for toggling the per-library "Merge Linked Library" attribute (PBXBuildFile `ATTRIBUTES = (Merge,)`) on entries inside a target's PBXFrameworksBuildPhase. Mergeable Libraries with `MERGED_BINARY_TYPE = manual` rely on this per-link-phase flag to decide which dependencies merge. Without a tool, agents must fall back to `MERGED_BINARY_TYPE = automatic` (merges everything mergeable) even when manual would be the right call.

## Tasks
- [x] Add `mcp__xc-project__set_framework_merge_attribute` (or similar): toggles the Merge attribute on a PBXBuildFile entry in a target's frameworks phase, keyed by (project_path, target_name, framework_name)
- [x] Mirror tool shape of `add_to_copy_files_phase` (already accepts an `attributes` array)
- [x] Extend `list_frameworks_phase` output to report the Merge flag per entry so callers can audit current state



## Summary of Changes

- Added `SetFrameworkMergeAttributeTool` (`Sources/Tools/Project/SetFrameworkMergeAttributeTool.swift`) — toggles the `Merge` entry in a PBXBuildFile's `ATTRIBUTES` array inside a target's `PBXFrameworksBuildPhase`. Takes `project_path`, `target_name`, `framework_name`, `merge` (bool). Matches against SPM `productName`, `PBXReferenceProxy` name/path (cross-project), or local file path / last-component (e.g. `MyLib`, `MyLib.framework`). Preserves any sibling attributes (e.g. `Weak`), clears the key entirely when the resulting array would be empty, refuses ambiguous matches, and no-ops with a clear message when already in the requested state.
- Extended `ListFrameworksPhaseTool` to append ` merge=true` to any frameworks-phase entry whose ATTRIBUTES contains `Merge`, so callers can audit `MERGED_BINARY_TYPE = manual` setups without re-parsing pbxproj by hand.
- Registered `set_framework_merge_attribute` in both `xc-project` and the monolithic `xc-mcp`, plus `ServerToolDirectory` for cross-server routing.
- Added 10 tests in `Tests/SetFrameworkMergeAttributeToolTests.swift` covering: tool metadata, missing-param validation, set-true on fileRef framework, set-false preserving sibling `Weak`, no-op when already set/cleared, framework-not-found, target-without-frameworks-phase, SPM productRef matching by `productName`, and the `list_frameworks_phase` merge=true marker. All pass.

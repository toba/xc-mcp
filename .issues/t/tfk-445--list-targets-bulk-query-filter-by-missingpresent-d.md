---
# tfk-445
title: 'list_targets bulk query: filter by missing/present dependency, settings, product type'
status: completed
type: task
priority: normal
created_at: 2026-06-03T01:49:41Z
updated_at: 2026-06-03T01:53:28Z
sync:
    github:
        issue_number: "380"
        synced_at: "2026-06-03T01:54:37Z"
---

Use case driven by Thesis workflow (toba/thesis thesis-xsh0): finding which test targets in a project are missing a specific PBXTargetDependency. Today `mcp__xc-project__list_dependencies` answers one target at a time, so the only way to find e.g. *all unit-test targets lacking a dependency on ThesisApp* is to spawn a sub-agent that greps pbxproj line-by-line — slow and error-prone.

## Concrete API sketch

Extend `mcp__xc-project__list_targets` with optional filters, OR add a new `mcp__xc-project__find_targets` tool:

```
list_targets(
  project_path,
  product_type: string? = nil,       // e.g. "com.apple.product-type.bundle.unit-test"
  has_dependency: string? = nil,     // target name; only return targets whose deps include this
  missing_dependency: string? = nil, // target name; only return targets whose deps DO NOT include this
  has_setting: { name: string, value: string }? = nil,   // e.g. SUPPORTED_PLATFORMS contains "iphoneos"
  missing_setting: string? = nil,    // e.g. find targets where MERGEABLE_LIBRARY isn't set
)
```

Returns: `[{ name, id, product_type, dependencies: [name], ... }]`.

## Why this matters

This exact pattern shows up repeatedly in Thesis's recent XCC work:
- ecb9c5bf9 needed "every framework target whose SUPPORTED_PLATFORMS is unset" (the 6 newer integration targets) and "every target whose MERGEABLE_LIBRARY=YES" — already filed as xc-mcp/q4u-ocl for bulk build settings query
- Today's fix (thesis: add ThesisApp dep to 11 test targets) needed "every unit-test target lacking dep on ThesisApp"

A single query API covers both. q4u-ocl could fold into this if the design lands.

## Out of scope

- Modifying targets in bulk (one-at-a-time is fine for the modify path; reads are the painful bit)
- Cross-project queries (single .xcodeproj is enough)



## Summary of Changes

Extended `list_targets` (Sources/Tools/Project/ListTargetsTool.swift) with optional bulk filter params instead of adding a new `find_targets` tool — the same code path now answers `list_targets(project_path)` (unfiltered, prior behavior) and bulk queries.

Filters:
- `product_type`: exact match on `productType.rawValue`
- `has_dependency` / `missing_dependency`: target name match against `dep.name ?? dep.target?.name ?? dep.product?.productName`
- `has_setting`: `{ name, value? }` — present in any configuration; optional value is a case-sensitive substring (matches against `.string` or any element of `.array`)
- `missing_setting`: setting name not defined in any configuration

When any filter is supplied, output upgrades from `- name (productType)` to `- name [id=… productType=… dependencies=[…]]` so callers don't need a second `list_dependencies` round-trip. Unfiltered output is byte-compatible with the previous version.

No new tool registration needed — `ListTargetsTool` is already wired through `ProjectMCPServer` and `XcodeMCPServer`. Tool description updated to document the filters.

Tests: 5 new filter tests in Tests/ListTargetsToolTests.swift (product_type include/exclude, has/missing dependency, has_setting+value, missing_setting). All 9 tests pass.

q4u-ocl is partially subsumed (per-target value substring match) but `find_build_settings` still wins for multi-setting bulk dumps with per-configuration rows — keep both.

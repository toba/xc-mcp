---
# zsc-vv7
title: scaffold_module nests test target in a sibling root group; need restructure-to-parent-group tool
status: completed
type: feature
priority: normal
created_at: 2026-05-28T18:09:04Z
updated_at: 2026-05-28T18:20:02Z
sync:
    github:
        issue_number: "361"
        synced_at: "2026-05-28T18:25:13Z"
---

## Problem

`mcp__xc-project__scaffold_module` creates the source/test layout as TWO top-level PBXGroups:

```
- Models           (PBXGroup)
  - Sources        (PBXFileSystemSynchronizedRootGroup, path = Models/Sources)
- ModelsTests      (PBXGroup)
  - Tests          (PBXFileSystemSynchronizedRootGroup, path = Models/Tests)
```

But most Thesis modules (Core, DOM, App, all Integrations) follow Apple's recommended convention where the test folder is a CHILD of the module group, not a sibling at root:

```
- Core             (PBXGroup, path = Core)
  - Documentation.docc
  - Tests          (PBXFileSystemSynchronizedRootGroup, path = Tests)
  - Sources        (PBXFileSystemSynchronizedRootGroup, path = Sources)
```

Result: scaffolded modules look out of place in the Xcode navigator and users have to hand-edit pbxproj to fix it (which is risky — pbxproj is in the agent-deny list for good reason).

## Reproduction

```
mcp__xc-project__scaffold_module(
  project_path: "Foo.xcodeproj",
  name: "Models",
  bundle_identifier: "com.example.Models",
  source_path: "Models/Sources",
  test_path: "Models/Tests",
  with_tests: true,
)
```

Creates `Models` and `ModelsTests` as siblings at project root, with synchronized folders carrying the parent path (`Models/Sources`, `Models/Tests`) instead of being relative to a parent `Models` group.

## Desired behavior — two options

**Option A: Fix scaffold_module to nest by default**

When `test_path` is a subdirectory of `source_path`'s parent (or matches the pattern `<name>/Tests` next to `<name>/Sources`), generate:

```
- Models           (PBXGroup, path = Models)
  - Tests          (PBXFileSystemSynchronizedRootGroup, path = Tests)
  - Sources        (PBXFileSystemSynchronizedRootGroup, path = Sources)
```

The test TARGET still exists at the same name (ModelsTests), only the project navigator hierarchy changes — Xcode handles this fine (Core/CoreTests do exactly this).

Add a `group_layout` parameter to opt in/out:
- `group_layout: "nested"` (proposed default) — single Models group with Sources + Tests children
- `group_layout: "sibling"` (current behavior, for users who want it)

**Option B: Add separate `move_group_into` / `restructure_module_groups` tool**

A general-purpose tool to move a PBXGroup or PBXFileSystemSynchronizedRootGroup from one parent to another, with the option to rewrite its `path` attribute (e.g. strip a `Models/` prefix when nesting under a parent that already has `path = Models`).

Signature:
```
mcp__xc-project__move_group(
  project_path: String,
  group_name: String,           // matches by name OR by ID  
  new_parent: String,           // group name or project root
  rewrite_path: String?,        // optional: replace the group's path attribute
)

mcp__xc-project__remove_group(
  project_path: String,
  group_name: String,           // empty groups removed safely; non-empty: error or force flag
)
```

Useful beyond this scaffold case — anywhere a user wants to reorganize the navigator hierarchy without touching pbxproj by hand.

## Recommendation

Both. Option A fixes the common case automatically, Option B gives an escape hatch and is independently useful.

## Context

Reported during the Thesis app's Core → Models + Sync split (jig issue r9i-xv0 in github.com/jsonleeapple/thesis). The agent's only path to fix the navigator hierarchy was to perl-edit pbxproj, which is in the project's agent-deny list — triggered a user halt. Adding these tools removes that footgun.



## Summary of Changes

- `scaffold_module` now defaults to a "nested" group layout: a single module `PBXGroup` (with `path = <name>`) containing `Sources` and `Tests` synchronized folders, matching Apple's recommended convention (Core, DOM, App, etc.). Default `source_path` / `test_path` adjust accordingly.
- Added `group_layout` parameter (`nested` | `sibling`) so callers can opt back into the legacy two-sibling layout.
- New `move_group` tool moves any `PBXGroup` or `PBXFileSystemSynchronizedRootGroup` under a different parent, with optional `new_path` rewrite. Registered in both `xc-project` and the monolithic `xc-mcp` server.
- Tests: updated `ScaffoldModuleToolTests` for the new default, added a `sibling` regression test, and added `MoveGroupToolTests` (reparent / path rewrite / move-to-main / self-move guard / missing-group).

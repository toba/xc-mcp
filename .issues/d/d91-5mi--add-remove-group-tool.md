---
# d91-5mi
title: Add remove_group tool
status: completed
type: feature
priority: normal
created_at: 2026-02-21T20:39:41Z
updated_at: 2026-02-21T21:07:59Z
---

There is no tool to remove a PBXGroup from the project. `create_group` exists but has no counterpart.

## Problem

During file restructuring, the agent had to manually find and delete three empty PBXGroup entries plus their references from parent group `children` arrays. This required multiple grep/read/edit cycles on the raw pbxproj.

## Proposed tool: `remove_group`

**Parameters:**
- `project_path` (required) — path to `.xcodeproj`
- `group_name` (required) — name or path of the group to remove
- `recursive` (optional, default false) — if true, also remove child groups and file references

**Behavior:**
1. Find the PBXGroup by name/path
2. Remove it from its parent group's `children` array
3. Delete the PBXGroup entry itself
4. If recursive, remove all child entries too
5. Error if group has children and `recursive` is false

## Files

- New: `Sources/Tools/Project/RemoveGroupTool.swift`
- Modify: `Sources/Servers/Project/ProjectMCPServer.swift` (register)

## Summary of Changes

- Added `RemoveGroupTool` at `Sources/Tools/Project/RemoveGroupTool.swift`
- Registered `remove_group` in `ProjectMCPServer.swift` (enum case, instantiation, tool list, call handler)
- Added 8 tests in `Tests/RemoveGroupToolTests.swift` covering: tool creation, missing params, remove empty group, non-existent group, children without recursive (blocked), recursive removal, and path-based lookup

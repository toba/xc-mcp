---
# r5e-pdy
title: Add in-place target renaming tool
status: completed
type: feature
priority: normal
created_at: 2026-02-21T21:49:58Z
updated_at: 2026-02-22T01:16:34Z
sync:
    github:
        issue_number: "117"
        synced_at: "2026-02-24T18:57:46Z"
---

## Problem

The MCP tools don't support in-place target renaming. The only current workaround is a recreate-from-scratch approach, which risks losing build settings, build phases, dependencies, and other target configuration.

## Proposed Solution

Add a `project_target_rename` tool that renames a target in-place, updating:

- [ ] Target name and product name
- [ ] All references from other targets (dependencies, embed phases)
- [ ] Scheme references (if applicable)
- [ ] Any build settings that reference the target by name

## Notes

- Should use XcodeProj to modify the target object directly rather than removing and recreating
- Must preserve all existing build settings, build phases, and dependencies

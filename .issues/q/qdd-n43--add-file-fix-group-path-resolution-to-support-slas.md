---
# qdd-n43
title: 'add_file: fix group path resolution to support slash-separated paths'
status: completed
type: bug
priority: high
created_at: 2026-03-07T18:55:41Z
updated_at: 2026-03-07T19:06:37Z
parent: xav-ojz
sync:
    github:
        issue_number: "172"
        synced_at: "2026-03-07T19:13:27Z"
---

\`add_file\` with \`group_name: "Components/TableView"\` fails ("Group not found"), but \`add_synchronized_folder\` with the same path succeeds. Inconsistent behavior.

## Fix
Unify group path resolution in add_file to use the same recursive path-walking pattern used in CreateGroupTool and AddFolderTool (split by "/", walk children from main group).

## Tasks
- [x] Replace flat group search with path-based recursive lookup
- [x] Add test: add_file to "Parent/Child" group path
- [x] Verify existing tests still pass


## Summary of Changes
Replaced flat group search with path-based recursive walk from mainGroup (split by "/", match name or path at each level). Updated existing tests to use full paths. Updated tool description to document path support.


## Summary of Changes
Replaced flat group search with path-based recursive walk from mainGroup (split by "/", match name or path at each level). Updated existing tests to use full paths. Updated tool description to document path support.

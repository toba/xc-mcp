---
# rpc-de1
title: 'add_target: add parent_group parameter'
status: completed
type: bug
priority: high
created_at: 2026-03-07T18:55:41Z
updated_at: 2026-03-07T19:06:34Z
parent: xav-ojz
sync:
    github:
        issue_number: "174"
        synced_at: "2026-03-07T19:13:27Z"
---

\`add_target\` creates the target's group at the project root. Users must then remove it and re-create under the correct parent.

## Fix
Add \`parent_group\` parameter to \`add_target\`. When omitted, current behavior (root). When set, nest the target's group under the specified group path (e.g. "Components").

## Tasks
- [ ] Add \`parent_group\` optional parameter to tool schema
- [ ] Use path-based group resolution (split by "/", walk from main group) — same pattern as CreateGroupTool
- [ ] Add test: target group created under specified parent
- [ ] Add test: omitting parent_group preserves current root behavior


## Summary of Changes
Added parent_group optional parameter to add_target. Uses path-based group resolution (split by "/"). Added tests for both valid parent group and invalid parent group error.

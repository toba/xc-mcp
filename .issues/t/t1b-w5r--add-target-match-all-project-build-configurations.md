---
# t1b-w5r
title: 'add_target: match all project build configurations'
status: completed
type: bug
priority: high
created_at: 2026-03-07T18:55:41Z
updated_at: 2026-03-07T19:06:33Z
parent: xav-ojz
sync:
    github:
        issue_number: "176"
        synced_at: "2026-03-07T19:13:27Z"
---

\`add_target\` only creates Debug/Release XCBuildConfiguration entries. Projects with additional configs (e.g. Beta) are left incomplete, requiring manual patching.

## Fix
Introspect the project-level XCConfigurationList and create a matching XCBuildConfiguration for every config, not just Debug/Release.

## Tasks
- [x] Read project-level XCConfigurationList to get all config names
- [x] Create an XCBuildConfiguration for each, applying appropriate settings (Debug-like for non-Release, Release-like for Release)
- [x] Add tests with a 3-config project fixture


## Summary of Changes
AddTargetTool now introspects the project-level XCConfigurationList and creates a matching XCBuildConfiguration for every config name found, not just Debug/Release.


## Summary of Changes
AddTargetTool now introspects the project-level XCConfigurationList and creates a matching XCBuildConfiguration for every config name found, not just Debug/Release.

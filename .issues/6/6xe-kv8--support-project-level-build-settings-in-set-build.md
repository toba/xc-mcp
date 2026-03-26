---
# 6xe-kv8
title: Support project-level build settings in set_build_setting tool
status: completed
type: feature
priority: normal
created_at: 2026-03-26T00:00:39Z
updated_at: 2026-03-26T00:28:30Z
sync:
    github:
        issue_number: "240"
        synced_at: "2026-03-26T00:28:51Z"
---

The `set_build_setting` MCP tool currently requires a `target_name` parameter — it doesn't support project-level build settings directly. Users must edit the pbxproj file manually for project-level changes.

## Requirements

- [x] Allow `set_build_setting` to work without a `target_name`, applying the setting at the project level
- [x] Update the tool's parameter schema to make `target_name` optional
- [x] When no target is specified, apply the build setting to the project-level build configuration(s)
- [x] Update tests to cover project-level build setting changes


## Summary of Changes

Made `target_name` optional in `set_build_setting`; when omitted, applies settings to project-level build configurations via `rootObject.buildConfigurationList`. Updated tool description, parameter schema, and added 2 new tests for project-level settings (single config and all configs).

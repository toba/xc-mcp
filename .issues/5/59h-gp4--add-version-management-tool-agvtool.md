---
# 59h-gp4
title: Add version management tool (agvtool)
status: completed
type: feature
priority: normal
created_at: 2026-04-06T23:17:28Z
updated_at: 2026-04-06T23:32:04Z
sync:
    github:
        issue_number: "262"
        synced_at: "2026-04-06T23:36:27Z"
---

Wrap `agvtool` as MCP tools for managing marketing version and build numbers.

## Tools

- [x] `get_version` — read current marketing version and build number
- [x] `set_version` — set marketing version (`agvtool new-marketing-version`) and/or build number (`agvtool new-version`)
- [x] `bump_build_number` — increment build number (`agvtool next-version -all`)

## Notes

- Useful for CI/CD workflows (bump version before archive/release)
- `agvtool` requires the project to use `CURRENT_PROJECT_VERSION` and `MARKETING_VERSION` build settings
- Must run from the directory containing the `.xcodeproj`
- Could combine get/set into a single tool with optional parameters

## Reference

Discovered via https://github.com/Terryc21/Xcode-tools catalog.


## Summary of Changes

Added `version_management` tool wrapping `xcrun agvtool`. Single tool with action parameter supporting get, set_marketing_version, set_build_number, and bump_build. Uses concurrent fetches for the get action. Registered in Build server and monolithic server.

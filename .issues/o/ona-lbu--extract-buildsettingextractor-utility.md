---
# ona-lbu
title: Extract BuildSettingExtractor utility
status: completed
type: task
priority: high
created_at: 2026-02-19T20:12:53Z
updated_at: 2026-02-19T20:26:22Z
sync:
    github:
        issue_number: "82"
        synced_at: "2026-02-19T20:42:41Z"
---

Consolidate duplicated build setting extraction functions. extractBundleId duplicated 4x, extractAppPath 3x, extractProductName 2x. BuildDebugMacOSTool already has a parametric extractBuildSetting(_:from:) that others should use.

- [ ] Create shared BuildSettingExtractor with generic key extraction
- [ ] Replace extractBundleId in GetAppBundleIdTool, GetMacBundleIdTool, BuildRunSimTool
- [ ] Replace extractAppPath in BuildRunMacOSTool, GetMacAppPathTool, BuildRunSimTool
- [ ] Replace extractProductName in GetAppBundleIdTool, GetMacBundleIdTool
- [ ] Consolidate build settings line-parsing loop (10 files)
- [ ] Verify tests pass

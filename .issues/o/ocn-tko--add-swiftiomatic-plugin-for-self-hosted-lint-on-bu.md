---
# ocn-tko
title: Add swiftiomatic-plugin for self-hosted lint-on-build
status: review
type: task
priority: normal
created_at: 2026-04-26T00:51:53Z
updated_at: 2026-04-26T00:57:39Z
sync:
    github:
        issue_number: "285"
        synced_at: "2026-04-26T01:38:47Z"
---

Wire up the swiftiomatic-plugins package (binary build-tool plugin) so xc-mcp lints with our own swiftiomatic config during build.



## Summary of Changes

- Added `swiftiomatic-plugins` package dependency (from 0.32.2) to `Package.swift`
- Applied `SwiftiomaticBuildToolPlugin` to the three source targets: `XCMCPCore`, `XCMCPTools`, and the `xc-mcp` executable
- Verified the plugin runs during `swift build` and emits lint warnings against `swiftiomatic.json`

Plugin is invoked correctly. Build currently surfaces pre-existing indentation warnings in `ScaffoldIOSProjectTool.swift` / `ScaffoldMacOSProjectTool.swift` (already-modified files) — not introduced by this change.

---
# fkw-148
title: Add remove_framework tool for Xcode projects
status: completed
type: feature
priority: normal
created_at: 2026-03-01T18:58:27Z
updated_at: 2026-03-01T19:02:04Z
sync:
    github:
        issue_number: "158"
        synced_at: "2026-03-01T19:05:28Z"
---

Implement RemoveFrameworkTool to remove framework references from Xcode projects. Completes add/remove symmetry with add_framework.

- [x] Create Sources/Tools/Project/RemoveFrameworkTool.swift
- [x] Register in Sources/Servers/Project/ProjectMCPServer.swift
- [x] Register in Sources/Server/XcodeMCPServer.swift
- [x] Create Tests/RemoveFrameworkToolTests.swift
- [x] swift build succeeds
- [x] swift test --filter RemoveFrameworkToolTests passes
- [x] swiftformat && swiftlint clean


## Summary of Changes

Added `remove_framework` tool that removes framework dependencies from Xcode projects. Supports removing system and custom frameworks (including embedded ones), from a specific target or all targets. Cleans up orphaned PBXFileReferences and group entries. Registered in both the focused xc-project server and the monolithic xc-mcp server. 9 tests cover all cases including parameter validation, multi-target scenarios, and name normalization.

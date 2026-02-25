---
# llb-90p
title: Implement validate_project tool (f6b-ert)
status: completed
type: feature
priority: normal
created_at: 2026-02-25T02:24:20Z
updated_at: 2026-02-25T02:27:42Z
sync:
    github:
        issue_number: "135"
        synced_at: "2026-02-25T02:29:03Z"
---

Add validate_project tool that checks Xcode project for embed phase issues, framework consistency, and dependency completeness.

## Summary of Changes

- **New file**: `Sources/Tools/Project/ValidateProjectTool.swift` — implements 3 check categories:
  - Embed phase validation (nil dstSubfolderSpec, empty phases, duplicate embeds)
  - Framework consistency (linked-not-embedded, embedded-not-linked)
  - Dependency completeness (missing target dependency, unused dependency)
- **Registration**: Added to ProjectToolName enum, ProjectMCPServer, XcodeMCPServer, ServerToolDirectory
- **Tests**: `Tests/ValidateProjectToolTests.swift` — 10 tests covering all checks and error paths

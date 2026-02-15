---
# xc-mcp-rpmm
title: Clean up unused files and update README
status: completed
type: task
priority: normal
created_at: 2026-01-21T06:01:57Z
updated_at: 2026-01-21T06:06:41Z
sync:
    github:
        issue_number: "28"
        synced_at: "2026-02-15T22:08:23Z"
---

Clean up project files, update README to reflect current state, and update LICENSE to credit sources.

## Checklist

- [x] Remove empty SPM directory
- [x] Remove badges from README
- [x] Update README to accurately describe the toba/xc-mcp project
- [x] Update LICENSE to credit original projects:
  - giginet/xcodeproj-mcp-server (original project this was forked from)
  - tuist/xcodeproj (Swift library for Xcode project manipulation)
  - modelcontextprotocol/swift-sdk (MCP Swift SDK)
- [x] Verify build still works

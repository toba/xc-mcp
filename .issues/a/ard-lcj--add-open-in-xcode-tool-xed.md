---
# ard-lcj
title: Add open-in-Xcode tool (xed)
status: completed
type: feature
priority: normal
created_at: 2026-04-06T23:17:31Z
updated_at: 2026-04-06T23:32:05Z
sync:
    github:
        issue_number: "267"
        synced_at: "2026-04-06T23:36:27Z"
---

Wrap `xed` as an MCP tool for opening files/projects in Xcode.

## Tool

- [x] `open_in_xcode` — open a file, project, or workspace in Xcode

## Capabilities

- `xed <file>` — open file in Xcode
- `xed --line <n> <file>` — open file at specific line
- `xed <project.xcodeproj>` — open project
- `xed <workspace.xcworkspace>` — open workspace

## Notes

- Trivial to implement but useful for "go look at this" workflows
- Lets the LLM direct the developer to a specific location after diagnosing an issue
- No output parsing needed — fire and forget

## Reference

Discovered via https://github.com/Terryc21/Xcode-tools catalog.


## Summary of Changes

Added `open_in_xcode` tool wrapping `/usr/bin/xed`. Supports opening files at specific lines, projects, and workspaces. Fire-and-forget with confirmation message. Registered in Build server and monolithic server.

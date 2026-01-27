---
# xc-mcp-7oon
title: Add Copy Files build phase management
status: completed
type: feature
priority: normal
created_at: 2026-01-27T02:44:06Z
updated_at: 2026-01-27T02:56:17Z
---

## Summary

Add tools to manage Copy Files build phases in Xcode projects, including:
- Adding files/folders to existing Copy Files phases
- Creating new Copy Files phases with destination paths
- Listing Copy Files phases and their contents
- Removing files from Copy Files phases

## Context

Copy Files build phases are used to copy resources (like CSL locales, styles, DocX templates) into specific locations within the app bundle. Currently xc-project MCP doesn't support managing these phases, making it impossible to fix broken Copy Files phases programmatically.

## Use Case

ThesisApp has empty Copy Files phases for:
- `styles` - should contain CSL style files
- `locales` - should contain CSL locale XML files  
- `docx` - should contain DocX default styles

These phases exist but have no files, causing tests to fail with "Locale file not found" errors.

## Checklist

- [x] Implement `list_copy_files_phases` tool
- [x] Implement `add_copy_files_phase` tool
- [x] Implement `add_to_copy_files_phase` tool
- [x] Implement `remove_copy_files_phase` tool
- [x] Register all tools in XcodeMCPServer.swift
- [x] Add unit tests for all tools
- [x] Run swift format and swiftlint
- [x] Run full test suite

## Implementation Notes

Each tool follows the pattern in Sources/Tools/Project/:
- Struct conforming to Sendable with PathUtility dependency
- `tool() -> Tool` method defining name, description, inputSchema
- `execute(arguments:) throws -> CallTool.Result` method with logic
- Registration in XcodeMCPServer.swift (ToolName enum, tool creation, ListTools, CallTool handler)
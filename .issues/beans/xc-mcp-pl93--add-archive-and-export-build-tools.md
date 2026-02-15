---
# xc-mcp-pl93
title: Add archive and export build tools
status: ready
type: feature
created_at: 2026-01-21T07:37:59Z
updated_at: 2026-01-21T07:37:59Z
---

Add tools to create .xcarchive and export to IPA/app.

## Tool Specifications

### archive_build
**Parameters:**
- project_path / workspace_path: string (optional, uses session default)
- scheme: string (optional, uses session default)
- archive_path: string (required) - output .xcarchive path
- destination: string (optional, default: "generic/platform=iOS")
- configuration: string (optional, default: "Release")

### export_archive
**Parameters:**
- archive_path: string (required) - path to .xcarchive
- export_path: string (required) - output directory
- export_options_plist: string (required) - path to exportOptions.plist

## Implementation

### Files to create:
- Sources/Tools/MacOS/ArchiveBuildTool.swift
- Sources/Tools/MacOS/ExportArchiveTool.swift

### Files to modify:
- Sources/Utilities/XcodebuildRunner.swift - add `archive()` and `exportArchive()` methods
- Sources/Server/XcodeMCPServer.swift - register tools

## Verification
- Build: swift build
- Run tests: swift test
- Manual test with a real project
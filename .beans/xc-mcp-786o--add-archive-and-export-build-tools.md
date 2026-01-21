---
# xc-mcp-786o
title: Add archive and export build tools
status: todo
type: feature
created_at: 2026-01-21T07:36:52Z
updated_at: 2026-01-21T07:36:52Z
---

Add MCP tools for creating archives and exporting for distribution: `archive_build`, `export_archive`.

## Commands
- `xcodebuild archive -scheme <scheme> -archivePath <path> -destination <dest>`
- `xcodebuild -exportArchive -archivePath <archive> -exportPath <output> -exportOptionsPlist <plist>`

## Implementation

### New files
- `Sources/Tools/MacOS/ArchiveBuildTool.swift`
- `Sources/Tools/MacOS/ExportArchiveTool.swift`

### XcodebuildRunner changes
Add methods:
```swift
func archive(
    projectPath: String?,
    workspacePath: String?,
    scheme: String,
    archivePath: String,
    destination: String = "generic/platform=iOS",
    configuration: String = "Release"
) async throws -> XcodebuildResult

func exportArchive(
    archivePath: String,
    exportPath: String,
    exportOptionsPlist: String
) async throws -> XcodebuildResult
```

### archive_build parameters
- `project_path` / `workspace_path`: string (optional, uses session default)
- `scheme`: string (optional, uses session default)
- `archive_path`: string (required) - output .xcarchive path
- `destination`: string (optional, default: "generic/platform=iOS")
- `configuration`: string (optional, default: "Release")

### export_archive parameters
- `archive_path`: string (required)
- `export_path`: string (required)
- `export_options_plist`: string (required) - path to exportOptions.plist

### exportOptions.plist example
```xml
<dict>
    <key>method</key>
    <string>app-store</string>
    <key>teamID</key>
    <string>TEAM_ID</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
```

## Checklist
- [ ] Add archive() method to XcodebuildRunner
- [ ] Add exportArchive() method to XcodebuildRunner
- [ ] Create ArchiveBuildTool.swift
- [ ] Create ExportArchiveTool.swift
- [ ] Register tools in XcodeMCPServer.swift
- [ ] Add tests
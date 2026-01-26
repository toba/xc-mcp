---
# xc-mcp-g4nw
title: 'Fix scheme deletion: use writePBXProj instead of write'
status: completed
type: bug
created_at: 2026-01-26T22:25:52Z
updated_at: 2026-01-26T22:25:52Z
---

When project-modifying tools call xcodeproj.write(), XcodeProj's writeSharedData() method deletes and rewrites the xcshareddata/xcschemes/ directory, causing scheme files to be permanently deleted.

## Solution
Use writePBXProj() instead of write() for all project modification tools. This method only writes the project.pbxproj file without touching workspace, shared data (schemes), or user data.

## Checklist
- [x] Update AddFileTool.swift
- [x] Update AddFrameworkTool.swift
- [x] Update AddBuildPhaseTool.swift
- [x] Update DuplicateTargetTool.swift
- [x] Update AddSwiftPackageTool.swift
- [x] Update RemoveAppExtensionTool.swift
- [x] Update RemoveFileTool.swift
- [x] Update AddFolderTool.swift
- [x] Update RemoveSwiftPackageTool.swift
- [x] Update RemoveTargetTool.swift
- [x] Update CreateGroupTool.swift
- [x] Update AddAppExtensionTool.swift
- [x] Update SetBuildSettingTool.swift
- [x] Update AddDependencyTool.swift
- [x] Update AddTargetTool.swift
- [x] Update MoveFileTool.swift
- [x] Run tests to verify
---
# lbn-ytp
title: Expose 6 implemented-but-unregistered project tools
status: ready
type: task
priority: high
created_at: 2026-02-21T20:39:33Z
updated_at: 2026-02-21T20:39:33Z
---

6 tools in `Sources/Tools/Project/` are fully implemented but not registered in `ProjectMCPServer.swift`:

1. **AddCopyFilesPhase** — create Copy Files build phase with destination
2. **ListCopyFilesPhases** — list all Copy Files phases in a target
3. **AddToCopyFilesPhase** — add files to existing Copy Files phase
4. **RemoveCopyFilesPhase** — remove Copy Files phase from target
5. **AddSynchronizedFolderExceptionTool** — create `PBXFileSystemSynchronizedBuildFileExceptionSet` to exclude specific files from a target in a synchronized folder
6. **AddTargetToSynchronizedFolderTool** — share a synchronized folder between multiple targets (add to existing target's `fileSystemSynchronizedGroups`)

## TODO

- [ ] Register all 6 tools in `ProjectMCPServer.swift`
- [ ] Add integration tests for each
- [ ] Update tool documentation/schema descriptions

## Context

Found during a DiagnosticApp restructuring session in Thesis. The agent had to manually edit the pbxproj to add exception sets and add a synchronized folder to an additional target — both operations that already have tool implementations but couldn't be used because they weren't exposed.

## Files

- `Sources/Servers/Project/ProjectMCPServer.swift` — registration site
- `Sources/Tools/Project/AddSynchronizedFolderExceptionTool.swift`
- `Sources/Tools/Project/AddTargetToSynchronizedFolderTool.swift`
- `Sources/Tools/Project/AddCopyFilesPhase.swift`
- `Sources/Tools/Project/ListCopyFilesPhases.swift`
- `Sources/Tools/Project/AddToCopyFilesPhase.swift`
- `Sources/Tools/Project/RemoveCopyFilesPhase.swift`

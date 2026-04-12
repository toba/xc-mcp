---
# dac-5qi
title: 'add_file: support Icon Composer .icon files and relative paths for files outside xcodeproj directory'
status: review
type: bug
priority: normal
created_at: 2026-04-12T19:50:45Z
updated_at: 2026-04-12T20:31:25Z
sync:
    github:
        issue_number: "278"
        synced_at: "2026-04-12T20:39:09Z"
---

## Problem

When using `add_file` to add an Icon Composer `.icon` file to a project, two issues occur:

### 1. Missing `lastKnownFileType` for `.icon` files

The generated `PBXFileReference` has no `lastKnownFileType`. It should be `folder.iconcomposer.icon`.

**Actual:**
```
{isa = PBXFileReference; name = AppIcon.icon; path = /abs/path/AppIcon.icon; sourceTree = "<absolute>"; };
```

**Expected (matches Xcode-generated reference):**
```
{isa = PBXFileReference; lastKnownFileType = folder.iconcomposer.icon; path = AppIcon.icon; sourceTree = SOURCE_ROOT; };
```

### 2. Absolute path instead of relative for files above xcodeproj

When the `.icon` file is at the repo root but the `.xcodeproj` is in a subdirectory (e.g. `Xcode/Project.xcodeproj`), the tool stores an absolute path with `sourceTree = "<absolute>"` instead of using `sourceTree = SOURCE_ROOT` with a relative path.

Using `../AppIcon.icon` as the file_path fails with "path is outside the allowed base path" because the tool resolves relative to the repo root, not the xcodeproj.

### Expected Behavior

- Recognize `.icon` extension → set `lastKnownFileType = folder.iconcomposer.icon`
- For files within the repo but above the xcodeproj directory, use `sourceTree = SOURCE_ROOT` with a path relative to the repo root (or `sourceTree = "<group>"` with a `../` relative path)

### Reproduction

```
# Repo structure:
# repo/
#   AppIcon.icon/
#   Xcode/Project.xcodeproj/

# This produces absolute path + missing lastKnownFileType:
add_file(project_path: "Xcode/Project.xcodeproj", file_path: "AppIcon.icon", target_name: "App")
```

### Reference

Thesis project at `~/Developer/toba/thesis` has a working Icon Composer icon reference created by Xcode.


## Impact

Without `lastKnownFileType = folder.iconcomposer.icon`, Xcode treats the `.icon` bundle as a generic folder resource copy. The icon is NOT compiled by the asset catalog compiler — the app falls back to a default/old icon. This is a build-correctness bug, not just cosmetic.

## Verified Behavior

1. `add_file` with absolute path `/Users/jason/.../AppIcon.icon` → produces `sourceTree = "<absolute>"` with no `lastKnownFileType`
2. `add_file` with relative path `../AppIcon.icon` (xcodeproj is in `Xcode/` subdir) → fails: "path is outside the allowed base path"
3. `add_file` with repo-relative path `AppIcon.icon` → same as #1

The built app gets a 142KB `AppIcon.icns` that is NOT derived from the `.icon` file (icon rendering is wrong — still shows old padded icon).

## Correct Reference (from Thesis project, created by Xcode)

```
{isa = PBXFileReference; lastKnownFileType = folder.iconcomposer.icon; path = AppIcon.icon; sourceTree = SOURCE_ROOT; };
```

Key differences:
- `lastKnownFileType = folder.iconcomposer.icon` (tells Xcode this is an Icon Composer bundle)
- `sourceTree = SOURCE_ROOT` with relative `path = AppIcon.icon`
- No `name` field needed when path basename matches the display name

## TODO

- [x] Add `.icon` → `folder.iconcomposer.icon` file type override in AddFileTool
- [x] Fix path resolution for files above xcodeproj but within repo root  
- [x] Create `CreateIconTool` — generates `.icon` bundle from a PNG
- [x] Register `create_icon` in XcodeMCPServer and BuildMCPServer
- [x] Add tests for all changes (71 total: 20 AddFile, 12 CreateIcon, 6 IconManifest, 6 ExportIcon, 27 IconTools)
- [x] Run tests — all pass

## Fix Scope

1. **File type mapping**: Add `.icon` → `folder.iconcomposer.icon` to the `lastKnownFileType` lookup table
2. **Path resolution**: When a file is inside the repo root but the xcodeproj is in a subdirectory, use `sourceTree = SOURCE_ROOT` with a path relative to the repo root, rather than falling back to absolute path or rejecting `../` paths


## Summary of Changes

### Bug fixes (dac-5qi)
1. **`.icon` file type**: Added `folder.iconcomposer.icon` override in `AddFileTool.fileType(forExtension:)` since XcodeProj's `Xcode.filetype(extension:)` doesn't know about `.icon`
2. **Path resolution**: When a file is above the xcodeproj but within the repo root (basePath), `add_file` now uses `sourceTree = SOURCE_ROOT` with a `../` relative path instead of falling back to absolute paths

### New: 9 icon tools in `Sources/Tools/Icon/`
Full Icon Composer tooling commensurate with [ethbak/icon-composer-mcp](https://github.com/ethbak/icon-composer-mcp):
- `create_icon` — create .icon bundle from PNG with fill, effects, dark mode, project wiring
- `export_icon` — render via ictool (moved from Utility/)
- `read_icon` — inspect bundle manifest and assets
- `add_icon_layer` — add layer to existing bundle (new group or existing)
- `remove_icon_layer` — remove layer/group with asset purging
- `set_icon_fill` — solid, automatic-gradient, linear-gradient, or clear
- `set_icon_effects` — specular, shadow, translucency, blur, lighting, blend mode
- `set_icon_layer_position` — scale and offset for layers/groups
- `set_icon_appearances` — dark/tinted mode fill specializations

### New: `IconManifest` Codable model
Full Codable representation of `icon.json` in `Sources/Core/IconManifest.swift` — groups, layers, fills (solid/gradient/automatic-gradient), shadows, translucency, positions, platform support, and dark mode specializations.

### Files changed
- `Sources/Tools/Project/AddFileTool.swift` — file type override + path resolution fix
- `Sources/Core/IconManifest.swift` — new Codable model
- `Sources/Tools/Icon/` — 9 icon tools (new directory)
- `Sources/Server/XcodeMCPServer.swift` — register create_icon
- `Sources/Servers/Build/BuildMCPServer.swift` — register create_icon
- `Tests/AddFileToolTests.swift` — 4 new tests
- `Tests/CreateIconToolTests.swift` — 12 new tests
- `Tests/IconManifestTests.swift` — 6 new tests

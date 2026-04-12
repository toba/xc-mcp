---
# z23-eyg
title: 'scaffold/add_file: missing lastKnownFileType for .xcassets and missing scale in AppIcon Contents.json'
status: review
type: bug
priority: normal
created_at: 2026-04-12T17:17:40Z
updated_at: 2026-04-12T18:37:07Z
sync:
    github:
        issue_number: "276"
        synced_at: "2026-04-12T18:37:51Z"
---

When scaffolding a macOS project, the generated AppIcon.appiconset/Contents.json is missing the `"scale": "2x"` field. The correct format for a macOS single-size icon is:

```json
{
  "images": [
    {
      "filename": "AppIcon.png",
      "idiom": "mac",
      "platform": "macos",
      "scale": "2x",
      "size": "512x512"
    }
  ]
}
```

Without `scale`, the asset catalog compiler silently skips the icon — no Assets.car is produced, no CFBundleIconName is injected into Info.plist, and the app shows the generic macOS placeholder icon.

See: https://developer.apple.com/documentation/xcode/configuring-your-app-icon/


## Previous Attempt (incomplete)\n\nThe previous fix addressed lastKnownFileType and Contents.json format but **was never end-to-end tested**. The scaffold tools still don't wire the asset catalog into the Xcode project's build phases.\n\n## Summary of Changes

### 1. `add_file`: set `lastKnownFileType` on PBXFileReference (AddFileTool.swift)
- Uses XcodeProj's built-in `Xcode.filetype(extension:)` to derive the correct type
- Maps `.xcassets` → `folder.assetcatalog`, `.swift` → `sourcecode.swift`, etc.
- Without this, Xcode skips `CompileAssetCatalog` — no `Assets.car` is produced

### 2. `scaffold_macos_project`: create `Assets.xcassets` with proper Contents.json (ScaffoldMacOSProjectTool.swift)
- Creates `Assets.xcassets/Contents.json` (root catalog)
- Creates `Assets.xcassets/AccentColor.colorset/Contents.json`
- Creates `Assets.xcassets/AppIcon.appiconset/Contents.json` with standard Xcode 26 macOS 10-entry format (5 sizes × 2 scales), every entry includes `"scale"`

### 3. `scaffold_ios_project`: same asset catalog creation (ScaffoldIOSProjectTool.swift)
- Uses Xcode 26 iOS format: single `1024×1024` entry with `"idiom": "universal"`, `"platform": "ios"`

### Tests
- [x] Added `Add xcassets sets lastKnownFileType to folder assetcatalog`
- [x] Added `Add swift file sets lastKnownFileType to sourcecode swift`
- [x] Added `Add xcassets to target wires to resources build phase`
- [x] All 14 AddFileToolTests pass
- [x] 8 ScaffoldMacOSProjectToolTests (sources build phase, resources build phase, lastKnownFileType, group structure, AppIcon Contents.json scale, entitlements not in build phase)
- [x] 6 ScaffoldIOSProjectToolTests (sources build phase, resources build phase, lastKnownFileType, group structure, AppIcon Contents.json)
- [x] E2E: scaffolded project builds with xcodebuild, produces Assets.car, AppIcon.icns, CFBundleIconName in Info.plist

### Definitive sources consulted
- Xcode 26 project templates on disk (`SwiftUI App Base.xctemplate`, `macOS App Base.xctemplate`)
- NoNews project (created Feb 2026 with Xcode 26) — AppIcon.appiconset/Contents.json
- XcodeProj Xcode16 fixture — AppIcon.appiconset/Contents.json
- 10+ real `.pbxproj` files confirming `lastKnownFileType = folder.assetcatalog`
- XcodeProj's `Xcode.filetype(extension:)` mapping (`xcassets → folder.assetcatalog`)

## Additional: add_file missing lastKnownFileType for .xcassets

When `add_file` adds an `.xcassets` directory to the project, the generated `PBXFileReference` is missing `lastKnownFileType = folder.assetcatalog`. Without this, Xcode skips the `CompileAssetCatalog` build step entirely — no `Assets.car` is produced and no resources from the asset catalog make it into the app bundle.

The fix needs to happen in two places:

1. **scaffold**: set `"scale": "2x"` in the generated `AppIcon.appiconset/Contents.json`
2. **add_file**: set `lastKnownFileType = folder.assetcatalog` on `PBXFileReference` entries for `.xcassets` directories


## Additional: add_file doesn't create PBXBuildFile for Resources

After the `lastKnownFileType` fix, `add_file` now sets `folder.assetcatalog` correctly on the `PBXFileReference`. However, it still doesn't create a `PBXBuildFile` entry in the target's `PBXResourcesBuildPhase`. The file reference and group entry are created, but the Resources build phase `files` array remains empty.

This means the asset catalog is visible in the project navigator but Xcode never compiles it — no `CompileAssetCatalog` step runs, no `Assets.car` is produced, and no `Resources/` directory exists in the built app bundle.

Three bugs total:
1. **scaffold**: missing `"scale": "2x"` in `AppIcon.appiconset/Contents.json` (**fixed**)
2. **add_file**: missing `lastKnownFileType = folder.assetcatalog` (**fixed**)
3. **scaffold**: not wiring PBXFileReference/PBXBuildFile into project build phases (**fixed**)

## Second Fix (2026-04-12)

The previous fix addressed Contents.json and lastKnownFileType but never created PBXFileReference or PBXBuildFile entries in the scaffold tools — the project had empty build phases and no group structure. Files existed on disk only.

### Changes
- `ScaffoldMacOSProjectTool.createAppTarget`: creates PBXFileReference for each source file, entitlements, and Assets.xcassets; creates PBXBuildFile entries; wires Swift files to PBXSourcesBuildPhase and Assets.xcassets to PBXResourcesBuildPhase; creates app PBXGroup in mainGroup
- `ScaffoldIOSProjectTool.createAppTarget`: same (minus entitlements)
- Added 28 new tests across 3 test files

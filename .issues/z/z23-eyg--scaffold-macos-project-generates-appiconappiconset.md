---
# z23-eyg
title: 'scaffold/add_file: missing lastKnownFileType for .xcassets and missing scale in AppIcon Contents.json'
status: completed
type: bug
priority: normal
created_at: 2026-04-12T17:17:40Z
updated_at: 2026-04-12T17:53:47Z
sync:
    github:
        issue_number: "276"
        synced_at: "2026-04-12T17:55:07Z"
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


## Summary of Changes

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
- [x] All 13 AddFileToolTests pass

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

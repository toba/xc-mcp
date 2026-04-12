---
# tmv-k66
title: 'scaffold: AppIcon.appiconset Contents.json uses invalid platform value'
status: completed
type: bug
priority: high
created_at: 2026-04-12T19:17:55Z
updated_at: 2026-04-12T19:23:15Z
sync:
    github:
        issue_number: "279"
        synced_at: "2026-04-12T20:39:10Z"
---

The scaffolded `AppIcon.appiconset/Contents.json` includes `"platform": "macos"` which `actool` does not recognize:

```
warning: Unknown platform value "macos"
warning: The app icon set "AppIcon" has an unassigned child.
```

This causes the icon to silently fail — `actool` runs but produces an `Assets.car` with no icon, and no `CFBundleIconName` is injected into Info.plist.

## Current (broken)

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

## Correct (working)

Remove `"platform"` entirely. The `idiom: "mac"` field is sufficient for macOS. The platform is already communicated to `actool` via `--platform macosx` at build time.

```json
{
  "images": [
    {
      "filename": "AppIcon.png",
      "idiom": "mac",
      "scale": "2x",
      "size": "512x512"
    }
  ]
}
```

## Related

- z23-eyg: original issue covering missing `scale` field and `lastKnownFileType`
- lo7-k5l: missing `PBXBuildFile` in Resources phase (fixed)

## How this was discovered

After fixing the `lastKnownFileType` and `PBXBuildFile` issues, `CompileAssetCatalog` finally ran but still produced no icon. The `actool` warnings in the build log revealed that `"platform": "macos"` is not a valid value — the valid platform identifiers are `ios`, `watchos`, `tvos`, etc., but macOS uses `idiom: "mac"` without a `platform` field.


## Summary of Changes

Fixed: scaffold no longer emits invalid `"platform": "macos"` in AppIcon.appiconset/Contents.json. macOS icons use `"idiom": "mac"` without a platform field.

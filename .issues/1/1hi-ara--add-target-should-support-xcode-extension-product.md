---
# 1hi-ara
title: add_target should support Xcode extension product type
status: completed
type: bug
priority: high
created_at: 2026-04-11T15:57:51Z
updated_at: 2026-04-11T16:02:30Z
sync:
    github:
        issue_number: "271"
        synced_at: "2026-04-11T16:03:38Z"
---

When creating an Xcode Source Editor Extension target, `add_target` uses `com.apple.product-type.app-extension` (generic app extension). The correct product type for Xcode extensions is `com.apple.product-type.xcode-extension`.

## Problem

With the wrong product type:
- pluginkit registers the extension correctly
- System Settings > Extensions shows it and allows enabling
- But **Xcode itself won't load it** — the extension appears greyed out in the Editor menu
- No crash, no error, no log output — Xcode silently ignores it

## Expected Behavior

When creating a target intended as an Xcode Source Editor Extension (or any Xcode extension), the product type should be `com.apple.product-type.xcode-extension`.

Ideally `add_target` should accept an option for extension type, or infer it from the extension point identifier in the Info.plist.

## Known Xcode Extension Product Types

- `com.apple.product-type.xcode-extension` — Xcode extensions (Source Editor, etc.)
- `com.apple.product-type.app-extension` — generic app extensions (Share, Notification, etc.)

## Found In

Swiftiomatic Xcode Source Editor Extension — extension built, signed, registered, enabled in System Settings, but Xcode refused to load it. Zero diagnostic output. Hours of debugging to find this.

## Fix Options

1. Add an `extension_type` parameter to `add_target` (e.g., `xcode-extension`, `app-extension`)
2. Or add a `set_product_type` tool to change it after creation
3. Or detect the extension point from Info.plist and auto-set the correct product type


## Summary of Changes

- Added `sourceEditor` case to `ExtensionType` enum with correct product type (`.xcodeExtension` → `com.apple.product-type.xcode-extension`) and extension point identifier (`com.apple.dt.Xcode.extension.source-editor`)
- Accepts multiple naming variants: `source_editor`, `sourceeditor`, `xcode_extension`, `xcodeextension`, `xcode_source_editor`, `xcodesourceeditor`
- Added `.xcodeExtension` to `RemoveAppExtensionTool`'s valid extension product types so Xcode extensions can be removed
- Updated tool descriptions to mention Xcode Source Editor extensions
- Added test case for `source_editor` → `.xcodeExtension` product type mapping

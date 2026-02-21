---
# s8v-15f
title: add_framework creates duplicate group-relative file references instead of reusing BUILT_PRODUCTS_DIR
status: completed
type: bug
priority: normal
created_at: 2026-02-18T04:36:04Z
updated_at: 2026-02-20T17:51:42Z
sync:
    github:
        issue_number: "73"
        synced_at: "2026-02-20T17:52:06Z"
---

When `add_framework` adds a framework to a target, it creates new `PBXFileReference` entries with `sourceTree = "<group>"` instead of reusing the existing `PBXFileReference` entries that have `sourceTree = BUILT_PRODUCTS_DIR` and `explicitFileType = wrapper.framework`. This causes framework linking issues because the group-relative path doesn't resolve to the built product.

## Reproduction

```
add_framework(project_path: "Thesis.xcodeproj", target_name: "DiagnosticApp", framework_name: "Core.framework", embed: true)
```

Creates:
```
63B491127FFEB37257E9FBCA /* Core.framework */ = {isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = Core.framework; path = Core.framework; sourceTree = "<group>"; };
```

Should reuse:
```
96B8F333292FF677000C6737 /* Core.framework */ = {isa = PBXFileReference; explicitFileType = wrapper.framework; includeInIndex = 0; path = Core.framework; sourceTree = BUILT_PRODUCTS_DIR; };
```

## Expected

`add_framework` should check for existing `PBXFileReference` entries in the Products group (with `sourceTree = BUILT_PRODUCTS_DIR`) before creating new file references. If a matching product exists, reuse it.

## Affected frameworks (all 11 duplicated)

Core, DOM, CSL, DocX, Zotero, BibTeX, RIS, EndNote, Ghost, Obsidian, GRDBQuery

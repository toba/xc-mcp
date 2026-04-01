---
# 81k-cr3
title: add_framework creates bogus .framework file reference for static libraries (.a)
status: completed
type: bug
priority: normal
created_at: 2026-04-01T03:42:31Z
updated_at: 2026-04-01T03:47:15Z
sync:
    github:
        issue_number: "250"
        synced_at: "2026-04-01T03:48:15Z"
---

## Problem

`add_framework` with `framework_name: "libTestSupport.a"` creates a **new** `PBXFileReference` named `libTestSupport.a.framework` instead of reusing the existing build product reference for the static library.

This produces an invalid link that the linker cannot resolve (undefined symbols for all types in the library).

## Expected

When the target is a static library (`.a`), `add_framework` should find the existing `PBXFileReference` with `explicitFileType = archive.ar` in `BUILT_PRODUCTS_DIR` and create a `PBXBuildFile` referencing it, then insert that into the target's `PBXFrameworksBuildPhase`.

## What Xcode does

When you manually add `libTestSupport.a` via "Link Binary With Libraries" in Xcode, it creates:

```
PBXBuildFile {
    fileRef = <existing product ref> /* libTestSupport.a */
}
```

and inserts it into the `PBXFrameworksBuildPhase.files` array. No new `PBXFileReference` is created.

## What add_framework does

It creates a **new** `PBXFileReference`:

```
PBXFileReference {
    path = "libTestSupport.a.framework"  // WRONG - appends .framework
}
```

and a `PBXBuildFile` referencing this bogus file ref. The linker then fails because the `.framework` file does not exist.

## Reproduction

```json
{
    "project_path": "Thesis.xcodeproj",
    "target_name": "MathViewTests",
    "framework_name": "libTestSupport.a"
}
```

## Fix

In `add_framework`, before creating a new `PBXFileReference`:
1. Search existing `PBXFileReference` entries for one matching the given name (exact match on `path` or `name`)
2. If found (especially with `explicitFileType = archive.ar`), reuse it
3. Do NOT append `.framework` to names ending in `.a`

## Summary of Changes

- Modified `AddFrameworkTool.swift` to detect static libraries (`.a` files) before the system framework check
- Static libraries now reuse existing `PBXFileReference` entries (matching on path/name with `buildProductsDir` source tree or `archive.ar` explicit file type)
- When no existing reference exists, creates a proper `BUILT_PRODUCTS_DIR` reference with `explicitFileType: archive.ar` instead of a bogus `.framework` wrapper
- Added two new tests: one verifying reuse of existing product references, one verifying correct creation when no reference exists

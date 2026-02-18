---
# cj4-hf3
title: add_framework creates duplicate group-relative file references instead of reusing BUILT_PRODUCTS_DIR
status: completed
type: bug
priority: normal
created_at: 2026-02-18T04:37:07Z
updated_at: 2026-02-18T04:39:47Z
---

When add_framework adds a framework to a target, it creates new PBXFileReference entries with sourceTree = '<group>' instead of reusing existing entries with sourceTree = BUILT_PRODUCTS_DIR. Should check Products group for existing references first.

## Tasks
- [x] Find the AddFrameworkTool source
- [x] Fix to reuse existing BUILT_PRODUCTS_DIR file references
- [x] Add/update tests
- [x] Verify fix


## Summary of Changes

Fixed `AddFrameworkTool` to search existing `PBXFileReference` entries with `sourceTree = BUILT_PRODUCTS_DIR` before creating new group-relative references. When a matching built product exists (e.g., from a local framework target), the tool now reuses it instead of creating a duplicate. Also skips adding reused product references to the Frameworks group since they already live in the Products group.

Files changed:
- `Sources/Tools/Project/AddFrameworkTool.swift` — reuse logic
- `Tests/AddFrameworkToolTests.swift` — new test verifying BUILT_PRODUCTS_DIR reuse

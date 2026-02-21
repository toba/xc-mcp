---
# 8x3-nse
title: Add rename_target MCP tool
status: completed
type: feature
priority: normal
created_at: 2026-02-21T21:53:43Z
updated_at: 2026-02-21T21:56:21Z
---

Add a rename_target tool that modifies target name in-place, updating all references (build settings, dependencies, product references, groups).

## Summary of Changes

- Created `Sources/Tools/Project/RenameTargetTool.swift` — new MCP tool that renames a target in-place, updating target name, product name, build settings (PRODUCT_NAME, INFOPLIST_FILE, PRODUCT_MODULE_NAME), dependency references, copy-files phase references, product file references, and target groups.
- Created `Tests/RenameTargetToolTests.swift` — 7 tests covering tool creation, missing params, rename existing target, non-existent target, duplicate name, dependencies, and product references.
- Modified `Sources/Server/XcodeMCPServer.swift` — added `renameTarget` enum case, tool instantiation, allTools registration, and switch handler.

---
# gf9-6uw
title: Add scheme StoreKit configuration tool (set/clear .storekit reference)
status: completed
type: feature
priority: normal
tags:
    - enhancement
created_at: 2026-06-27T16:35:15Z
updated_at: 2026-06-27T16:47:26Z
sync:
    github:
        issue_number: "398"
        synced_at: "2026-06-27T16:53:28Z"
---

## Gap

There is no MCP tool to set a scheme's StoreKit configuration file. A scheme's `LaunchAction` (and `TestAction`) can carry a `<StoreKitConfigurationFileReference identifier = "…">` child element that points at a `.storekit` config; today wiring that requires hand-editing the shared `.xcscheme` XML, which the Thesis project's bash guard otherwise blocks for project files. Hit while wiring `Thesis.storekit` into the `Standard` + `CI` schemes (Thesis epic thesis-dk0r / child szr-7kt) — had to edit both scheme files directly.

## Proposed tool

`set_scheme_storekit_config` (mirrors `AddTestPlanToSchemeTool`):
- Inputs: `project_path`, `scheme_name`, `storekit_path` (path to the `.storekit`, stored as the scheme-relative `identifier`), `action` add|remove, and which actions to target (`launch`, `test`, or both — default both).
- Writes/removes the `<StoreKitConfigurationFileReference>` child under `LaunchAction` and/or `TestAction`.
- Computes the `identifier` as the path relative to the scheme file location (e.g. a repo-root `Thesis.storekit` becomes `../../../Thesis.storekit`), matching how Xcode serializes it.
- Idempotent: replaces an existing reference rather than duplicating.

## Reference

- Template: `Sources/Tools/Project/AddTestPlanToSchemeTool.swift`
- Register in the project MCP server (`Sources/Servers/Project/ProjectMCPServer.swift`) + `ServerToolDirectory.swift`.

## Acceptance

- [x] Tool adds a `StoreKitConfigurationFileReference` to a scheme's launch + test actions
- [x] Tool removes it cleanly
- [x] Relative `identifier` computed correctly for a config outside the project bundle
- [x] Idempotent on repeat calls


## Summary of Changes

Added `set_scheme_storekit_config` (Sources/Tools/Project/SetSchemeStoreKitConfigTool.swift), registered in the project + monolithic servers and `ServerToolDirectory`.

- Inputs: `project_path`, `scheme_name`, `storekit_path` (required for add), `action` (add|remove, default add), `target_actions` (launch|test|both, default both).
- Writes/removes the `<StoreKitConfigurationFileReference>` child under `LaunchAction` and/or `TestAction`; idempotent (replaces an existing ref rather than duplicating).
- `identifier` is the `.storekit` path relative to the scheme file location, via new `SchemePathResolver.schemeRelativeIdentifier(for:schemePath:)` (e.g. repo-root `Thesis.storekit` -> `../../../Thesis.storekit`, matching Xcode's serialization).
- Edits the scheme XML directly rather than round-tripping through `XCScheme`: the XcodeProj model only represents the StoreKit ref on `LaunchAction`, so a model round-trip would silently drop an existing `TestAction` ref. Direct editing preserves every other element exactly. Attribute value is XML-escaped.
- 8 tests in Tests/SetSchemeStoreKitConfigToolTests.swift (add to both, idempotency, launch-only preserves an existing test ref, remove, remove-when-absent, missing `storekit_path` throws, missing scheme) — all pass. Lint clean. CLAUDE.md tool counts bumped (xc-mcp 148, xc-project 42).

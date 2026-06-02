---
# 60f-9e1
title: Add archive tool to xc-build (mac+iOS .xcarchive)
status: completed
type: feature
priority: normal
created_at: 2026-06-02T22:02:32Z
updated_at: 2026-06-02T22:07:15Z
sync:
    github:
        issue_number: "377"
        synced_at: "2026-06-02T22:07:55Z"
---

Working on Thesis issue thesis-xsh0 (Xcode Cloud deployments). Reproducing XCC archive failures locally requires the archive command (`xcb archive -scheme X -configuration Release -destination 'generic/platform={iOS,macOS}' -archivePath <p>`), which is fundamentally distinct from build/build_sim/build_macos:

- Archive forces ARCHS_STANDARD (iOS = arm64; macOS = arm64+x86_64) regardless of host
- Archive triggers the Install action which is when MERGEABLE_LIBRARY merge happens, the codesign + dSYM extraction, and the embedded-frameworks copy
- Archive resolves the explicit-module-build dependency graph differently from build (different INTERMEDIATE_BUILD_PATH root: ArchiveIntermediates/<scheme>/... vs Build/Intermediates.noindex/...)

The actual XCC failures we are hitting (relinkable-library duplicate symbols from mergeable libraries, Core-built-for-macOS-during-iOS-archive) only reproduce under archive, not build_macos or build_sim. The Thesis jig hook blocks raw xcb calls (jig nope: BLOCK: Use xc-mcp to build and test), so without an xc-mcp archive tool the local repro loop is gated.

Proposed shape:
- mcp__xc-build__archive_macos(scheme, configuration=Release, archive_path, build_settings?, timeout?) wraps the archive command with -destination 'generic/platform=macOS'
- mcp__xc-simulator__archive_ios(scheme, configuration=Release, archive_path, build_settings?, timeout?) (or xc-build keyed off destination) - destination 'generic/platform=iOS'
- Both accept code_signing_allowed (default false for CI repro), skip_macro_validation, skip_package_plugin_validation to mirror XCC pre-archive flags
- Same error parsing path as build_macos so output stays uniform

Workaround until then: build_macos/build_sim reproduce the compile-side errors but not the link-time merge step nor the explicit-module ArchiveIntermediates layout, so structural archive bugs (mergeable libraries, cross-platform leakage) require manual archive + sandbox bypass.



## Summary of Changes

Added `archive` tool to xc-build (also exposed in monolithic xc-mcp). Single tool dispatches both macOS and iOS archives via a `platform: "macOS"|"iOS"` argument that selects `generic/platform=<X>`.

- `Sources/Tools/MacOS/ArchiveTool.swift` — new tool. Wraps `xcodebuild archive` via the existing `XcodebuildRunner.build(action: "archive", ...)` path so error parsing, partial-diagnostics formatting, process-group lifecycle, and timeout/stuck handling are shared with `build_macos`.
- Required: `archive_path`. Optional: `scheme`, `configuration` (default `Release` to match XCC), `platform` (default `macOS`), `code_signing_allowed` (default `false` — injects `CODE_SIGNING_ALLOWED=NO`, `CODE_SIGNING_REQUIRED=NO`, empty `CODE_SIGN_IDENTITY`/`ENTITLEMENTS` so CI repros run without provisioning), `skip_macro_validation`, `skip_package_plugin_validation`, plus the common `build_settings` / `continue_building_after_errors` / `enable_sanitizers` / `errors_only` / `show_warnings` / `timeout` (default 600s — archives are slower than builds because of Install action, dSYM, and mergeable-library merge).
- Validates macOS scheme support via `BuildSettingExtractor.validateMacOSSupport` when `platform == "macOS"`.
- Wired into `Sources/Servers/Build/BuildMCPServer.swift` (`BuildToolName.archive`) and `Sources/Server/XcodeMCPServer.swift` (`ToolName.archive`, including the macOS workflow categorization and the dispatch switch).

Unblocks the local repro loop for thesis-xsh0 — Thesis can now invoke `mcp__xc-build__archive` to reproduce XCC archive-only failures (relinkable-library duplicate symbols from mergeable libraries, Core-built-for-macOS-during-iOS-archive) that `build_macos`/`build_sim` cannot.

---
# itb-f6i
title: Add targeted clean for macro plugin consumers
status: draft
type: feature
priority: low
created_at: 2026-05-10T03:10:13Z
updated_at: 2026-05-10T03:10:13Z
blocked_by:
    - ibk-gjo
sync:
    github:
        issue_number: "319"
        synced_at: "2026-05-10T03:11:03Z"
---

## Motivation

Spun off from `ibk-gjo`. Now that `clean(derived_data: true)` correctly wipes xc-mcp's scoped DerivedData, the macro debugging loop works — but it's a sledgehammer. A full DerivedData wipe forces a multi-minute rebuild of every unrelated target. A targeted "macro consumers" clean would preserve incremental state for everything except macro plugins and their dependents.

## Proposed surface

One of:

- New `clean(macro_consumers: true)` flag on the existing clean tool.
- New `clean_macros: true` parameter on `build_macos` / `test_macos` that runs the targeted clean before building.
- Standalone `clean_macro_artifacts` tool.

Likely both: a flag on `clean` for explicit use and an opt-in on build/test for ergonomics during a tight macro-edit loop.

## What it should remove

For each `.macro(name:)` target declared in any reachable `Package.swift`:

- Plugin binary + `.swiftmodule` under `<DerivedData>/Build/Products/<config>/<MacroPlugin>` and the SPM build cache (`<DerivedData>/SourcePackages/...`).
- Cached expansion outputs in `<DerivedData>/Build/Intermediates.noindex/<Consumer>.build/Objects-normal/<arch>/*.swift` (the macro-expanded source files that consumers actually compile against — this is the layer that goes stale).
- Optionally `.o` / `.swiftmodule` for any target whose sources reference `@<MacroName>` from the plugins, forcing re-expansion downstream.

## Implementation sketch

- New `Sources/Core/MacroArtifactCleaner.swift` with the targeted-clean logic.
- Macro target discovery via `swift package describe --type json` (or by parsing `Package.swift`) for each SPM dependency reachable from the project.
- Path resolution via the same `DerivedDataScoper` the build tools use.
- Wire into `CleanTool` and optionally `BuildMacOSTool` / `TestMacOSTool`.

## Open questions

- How to discover reachable SPM packages from an `.xcodeproj` / `.xcworkspace`? `xcodebuild -showBuildSettings` exposes `BUILD_DIR` but not the package graph; may need to parse `Package.resolved` or scan `<DerivedData>/SourcePackages/checkouts/`.
- Xcode's macro-cache internals aren't documented; path heuristics will need to be retested against new Xcode releases. If they silently stop matching, the tool reports success but does nothing — same failure mode as the original bug. Mitigation: log the count of artifacts removed and warn loudly when zero.
- Worth doing across both project and SPM macro targets, or scope to SPM-declared macros only?

## When to revisit

Defer until the macro debugging loop becomes a bottleneck again after the `ibk-gjo` fix lands. If full-DerivedData clean + rebuild stays bearable in practice, this isn't worth the brittle path heuristics.

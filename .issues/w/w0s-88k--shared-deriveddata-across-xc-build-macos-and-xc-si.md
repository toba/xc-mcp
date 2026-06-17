---
# w0s-88k
title: Shared DerivedData across xc-build (macOS) and xc-simulator (iOS) collides on framework slices
status: completed
type: bug
priority: normal
created_at: 2026-06-17T17:55:09Z
updated_at: 2026-06-17T18:08:03Z
sync:
    github:
        issue_number: "391"
        synced_at: "2026-06-17T18:08:58Z"
---

## Problem

`xc-build` (macOS builds/tests) and `xc-simulator` (iOS-simulator builds/tests) appear to share a single DerivedData path keyed only by the project (e.g. `~/Library/Caches/xc-mcp/DerivedData/Thesis-4019ecb6511d`). Because both platforms write into the same `Build/Products` and `Build/Intermediates.noindex`, their per-framework slices clobber / cross-link each other.

The concrete failure (hit on the Thesis project): running `test_sim` for the iOS scheme after a macOS `build_macos` (or vice-versa) produces:

```
ld: building for 'macOS', but linking in dylib (.../Build/Products/Debug-iphonesimulator/GRDB.framework/GRDB) built for 'iOS-simulator'
```

followed by a large cascade of `Unable to resolve module dependency: 'GRDB'/'Core'/...` and `The file "X.swiftmodule" couldn't be opened because there is no such file` errors across every downstream target. GRDBCustom only built a `Debug-iphonesimulator` slice, so a macOS-targeted link grabbed the iOS-simulator GRDB framework from the shared products dir.

## Impact

- A clean iOS run after a macOS run (and vice-versa) fails non-deterministically with confusing platform-mismatch + missing-module errors that look like source/build-graph breakage but are pure cache contamination.
- Wiping DerivedData to recover one platform destroys the other platform's cache, so the two servers fight.
- The noise masked a real iOS build break in our project for several build cycles (framework targets missing SUPPORTED_PLATFORMS) — the genuine error was buried under the GRDB platform-mismatch wall.

## Repro

1. `set_session_defaults` for the project
2. `build_macos` scheme=CI (populates macOS slices + Debug/ products)
3. `test_sim` scheme=iOS, simulator=<iPhone> with a narrow only_testing
4. Observe 'building for macOS, but linking in dylib built for iOS-simulator' + module-resolution cascade

## Suggested fix

Namespace the `-derivedDataPath` by SDK/platform (or by server), e.g. `.../Thesis-<hash>-iphonesimulator` vs `-macosx`, so macOS and simulator builds never share `Build/Products` / `Intermediates.noindex`. Xcode keeps a single shared DerivedData but separates products per platform (`Debug-iphonesimulator` vs `Debug`); the breakage here is that framework search paths from one platform's link step resolve the other platform's framework slice. At minimum, document that interleaving xc-build and xc-simulator on the same project requires a clean between platform switches.

- [x] Namespace -derivedDataPath by platform in DerivedDataScoper
- [x] Thread destination through XcodebuildRunner build/buildTarget/test/showBuildSettings
- [x] Update DerivedDataLocator + macOS reader tools to pass matching destination
- [x] CleanTool removes all platform-suffixed scoped dirs
- [x] Centralize platform=macOS literal as XcodebuildRunner.macOSDestination
- [x] Tests


## Summary of Changes

Namespaced xc-mcp's scoped `-derivedDataPath` by platform so macOS (`xc-build`) and iOS-simulator (`xc-simulator`) builds against the same project no longer share `Build/Products` / `Build/Intermediates.noindex` and cross-link framework slices.

**Core**
- `DerivedDataScoper`: added `platformSlug(forDestination:)` (SDK-style slugs: `macosx`, `iphonesimulator`, `iphoneos`, `appletvsimulator`, `maccatalyst`, …) and an optional `destination:` parameter on `scopedPath`/`effectivePath`. Path becomes `<ProjectName>-<hash>-<platform>`; falls back to the base (suffix-free) path when the destination is absent/unrecognized (backward compatible).
- `XcodebuildRunner`: threads `destination` into the scoper for `build`, `buildTarget`, `test`, and `showBuildSettings`. Added `XcodebuildRunner.macOSDestination` constant to replace the repeated `"platform=macOS"` literal across macOS tools.
- `DerivedDataLocator.findProjectRoot`: new `destination` parameter (defaults to `platform=macOS`, since every caller is a macOS build diagnostic) forwarded to `showBuildSettings`.

**Reader tools** (now pass the matching destination so they resolve the same platform-scoped DerivedData the build wrote):
- `GetMacAppPath`, `BuildRunMacOS`, `ProfileAppLaunch`, `DiffBuildSettings`, and all `findProjectRoot`-based diagnostics (`ShowBuildDependencyGraph`, `ListBuildPhaseStatus`, `ExtractCrashTraces`, `ReadSerializedDiagnostics`, `CheckOutputFileMap`).
- `ShowBuildLog.findDerivedDataPath` rewritten to route through `DerivedDataLocator` (previously bypassed scoping entirely and read Xcode's default DerivedData — a latent bug).

**CleanTool**: `derived_data: true` now sweeps the base directory *and* every `-<platform>` sibling (plus the `XC_MCP_DERIVED_DATA_PATH` override), so one clean can't leave the other platform's contaminated cache behind.

**Tests**: added platform-slug mapping, suffix-append, base-path-equivalence, and macOS-vs-iOS-simulator separation cases (16 `DerivedDataScoperTests` pass; `SessionManagerPersistenceTests` unaffected).

**Note**: existing scoped caches at `<name>-<hash>` are orphaned (one-time cold rebuild per platform); multi-platform projects now keep separate per-platform DerivedData. `XC_MCP_DERIVED_DATA_PATH` / `XC_MCP_DISABLE_DERIVED_DATA_SCOPING` overrides are unchanged.

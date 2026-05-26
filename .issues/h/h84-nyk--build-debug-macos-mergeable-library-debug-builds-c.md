---
# h84-nyk
title: 'build_debug_macos: mergeable-library debug builds crash at launch (dyld Symbol missing) — embedded reexport stub shadows full framework'
status: completed
type: bug
priority: high
tags:
    - administrative
created_at: 2026-05-26T22:12:07Z
updated_at: 2026-05-26T22:25:55Z
sync:
    github:
        issue_number: "344"
        synced_at: "2026-05-26T22:31:00Z"
---

## Problem

A `TestApp` (and any app using **mergeable libraries** in Debug) crashes at launch under `build_debug_macos` with:

```
Termination: DYLD — Symbol missing
  Symbol not found: _$s10Foundation16AttributedStringV4CoreE9plainTextSSvg
    (Foundation.AttributedString.(extension in Core):plainText.getter)
  Referenced from: …/TestApp.app/Contents/MacOS/TestApp.debug.dylib
  Expected in:     …/TestApp.app/Contents/MacOS/TestApp.debug.dylib   (terminated at launch)
```

This is the **mergeable-library** variant of the framework-resolution problem fixed in qc1-f6z / 23m-ie7 — but those fixes do **not** cover it.

## Root cause

With `MERGEABLE_LIBRARY = YES` on frameworks + `MERGED_BINARY_TYPE = manual` on the app (Thesis project), each framework builds **two** products in Debug:

1. The **full** framework in `BUILT_PRODUCTS_DIR` (e.g. `Build/Products/Debug/Core.framework`, ~20 MB) — exports all symbols (`nm` shows `T _$s…plainTextSSvg`).
2. A thin **reexport stub** that Xcode embeds into the app bundle (`TestApp.app/Contents/Frameworks/Core.framework`, ~51 KB) — does **NOT** export the symbols.

`TestApp.debug.dylib` has `LC_REEXPORT_DYLIB @rpath/Core.framework/…`. At launch dyld resolves the undefined `plainText` through `@rpath` → finds the **embedded 51 KB stub** → symbol absent → `Symbol missing` (reported self-referentially because of the reexport).

Inside Xcode this works because Xcode injects `DYLD_FRAMEWORK_PATH=BUILT_PRODUCTS_DIR`, so dyld finds the full framework (#1) *before* the embedded stub. Confirmed locally: launching the binary directly with
`DYLD_FRAMEWORK_PATH=<…/Build/Products/Debug>` runs fine (GUI appears, no crash); launching via `open`/LaunchServices crashes.

## Why qc1-f6z's fix misses it

`AppBundlePreparer` symlinks **non-embedded** frameworks from `BUILT_PRODUCTS_DIR` into `Contents/Frameworks`. Here `Core.framework` is **already embedded** (as the stub), so it is skipped — and the stub remains and shadows the real framework. And per qc1-f6z's own note, `DYLD_FRAMEWORK_PATH` can't be passed through `open` (LaunchServices strips `DYLD_*`); passing it via `build_debug_macos`'s `env` param also fails (still launches via LaunchServices).

## Suggested fix

In `AppBundlePreparer`, when a framework is already embedded but is a **mergeable reexport stub**, replace it with the full framework from `BUILT_PRODUCTS_DIR` instead of skipping it. Detect the stub by either:
- presence of `LC_REEXPORT_DYLIB` pointing at `ReexportedBinaries`/itself with no real `__text`, or
- the embedded binary missing symbols that the `BUILT_PRODUCTS_DIR` copy exports, or
- a large size delta (stub is orders of magnitude smaller).

Then re-sign the bundle (as already done for symlinked frameworks).

Alternatively/additionally: launch the app via lldb `process launch` (posix_spawn) with `DYLD_FRAMEWORK_PATH` set, instead of LaunchServices, so the env survives. (`build_debug_macos` currently strips it via LaunchServices even when its `env` param is provided.)

## Repro

- Repo: `toba/thesis`, scheme `TestApp`, Debug.
- `build_debug_macos` → launch crashes (`~/Library/Logs/DiagnosticReports/TestApp-*.ips`, `Symbol missing`).
- Workaround confirmed: `DYLD_FRAMEWORK_PATH="…/Build/Products/Debug" .../TestApp.app/Contents/MacOS/TestApp --show-node <uuid>` launches with a working window.

## Tasks
- [x] Detect embedded mergeable-library reexport stubs in `AppBundlePreparer`
- [x] Replace embedded stub with full framework from `BUILT_PRODUCTS_DIR` + re-sign
- [x] (Not needed) launch via posix_spawn — embedding the full framework removes the LaunchServices dependency entirely
- [x] Verify a fresh `TestApp` Debug build launches via `build_debug_macos` without dyld crash


## Summary of Changes

Fixed in `Sources/Core/AppBundlePreparer.swift`. Two distinct dyld-at-launch failures were resolved:

1. **Mergeable-library reexport stub (the reported bug).** When a framework already exists in `Contents/Frameworks`, the preparer used to skip it. With `MERGEABLE_LIBRARY=YES` Xcode embeds a thin reexport *stub* (~51 KB, 0 exported symbols) that shadows the full framework (~20 MB, 20k+ symbols), causing `Symbol not found` against the app's `LC_REEXPORT_DYLIB @rpath/...`. New `isMergeableStub(embeddedFramework:fullFramework:)` detects the stub by binary-size delta (embedded < 50% of the `BUILT_PRODUCTS_DIR` copy) and replaces it with a symlink to the full framework. `frameworkBinaryPath(_:)` resolves the Mach-O binary inside versioned or flat framework layouts. Detection is idempotent (a symlinked framework matches its source size).

2. **SPM package-product frameworks (revealed once #1 was fixed).** Package products live in `BUILT_PRODUCTS_DIR/PackageFrameworks/` — a subdirectory the preparer never symlinked — so `@rpath` lookups (e.g. `SQLMacros_..._PackageProduct.framework` referenced from `Zotero.framework`) failed with `Library not loaded`. The symlink step was extracted into `symlinkProducts(from:into:)` and now runs over both `BUILT_PRODUCTS_DIR` and its `PackageFrameworks` subdirectory.

The bundle is re-signed as before (existing `resignBundle`). The `posix_spawn`/`DYLD_FRAMEWORK_PATH` alternative was unnecessary since embedding the real frameworks removes the LaunchServices env-stripping dependency.

### Verification
- 4 new unit tests in `Tests/AppBundlePreparerTests.swift` covering stub detection (positive/negative) and binary-path resolution (versioned/flat) — all pass.
- End-to-end via `test-debug.sh ... TestApp screenshot`: the scheme builds, launches under LLDB, and runs past dyld with no crash report. Both the original `Symbol missing` (Core) and the follow-on `Library not loaded` (SQLMacros) crashes are gone. Embedded frameworks in the launched bundle are now symlinks into `BUILT_PRODUCTS_DIR`.

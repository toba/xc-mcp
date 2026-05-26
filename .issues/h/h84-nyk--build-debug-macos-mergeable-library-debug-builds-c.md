---
# h84-nyk
title: 'build_debug_macos: mergeable-library debug builds crash at launch (dyld Symbol missing) — embedded reexport stub shadows full framework'
status: completed
type: bug
priority: high
tags:
    - administrative
created_at: 2026-05-26T22:12:07Z
updated_at: 2026-05-26T22:59:37Z
sync:
    github:
        issue_number: "344"
        synced_at: "2026-05-26T23:01:49Z"
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
- [ ] Detect embedded mergeable-library reexport stubs in `AppBundlePreparer`
- [ ] Replace embedded stub with full framework from `BUILT_PRODUCTS_DIR` + re-sign
- [ ] (Or) launch debug builds via posix_spawn/lldb preserving `DYLD_FRAMEWORK_PATH` instead of LaunchServices
- [ ] Verify a fresh `TestApp` Debug build launches via `build_debug_macos` without dyld crash

---

## Follow-up (2026-05-26): fix resolved the Core symbol, but launch now fails on a Team-ID / library-validation mismatch

Verified the fix **works for the original problem**: the embedded `Core.framework` is now the full 20 MB framework (`nm` shows `T _$s…plainTextSSvg`), signed `TeamIdentifier=D6GX9PC3SR`. The `Core.AttributedString.plainText` `Symbol missing` crash is gone.

However, TestApp still **crashes at launch** (dyld `prepare`/`halt`, `EXC_CRASH`/`SIGABRT`) — now on a different dependency:

```
Library not loaded: @rpath/SQLMacros_6ABCC7ADE539285E_PackageProduct.framework/…
Reason: code signature … not valid for use in process: mapping process and
        mapped file (non-platform) have different Team IDs
```

Signing audit of the prepared bundle:
- `TestApp.debug.dylib` → `TeamIdentifier=D6GX9PC3SR`, `flags=0x10000(runtime)` (hardened runtime)
- embedded `Core.framework` (re-signed by the fix) → `TeamIdentifier=D6GX9PC3SR`
- `SQLMacros_…_PackageProduct.framework` (embedded **and** in `PackageFrameworks/`) → **`TeamIdentifier=not set`** (ad-hoc)

`SQLMacros_…_PackageProduct` is a Swift-macro package product that `Zotero.framework` reexports at runtime. Because `AppBundlePreparer` re-signs the bundle with the developer team identity **and** hardened runtime, library validation now rejects the ad-hoc-signed macro framework (team mismatch). Before the fix, launch died earlier on the Core stub, masking this.

Reproduces via `build_debug_macos` (let the process run after `debug_continue` → it aborts; under LLDB it sits suspended so it looks alive) and via direct `DYLD_FRAMEWORK_PATH` exec.

### Suggested fix (one of)
- When re-signing, also re-sign embedded **package-product** frameworks (e.g. `*_PackageProduct.framework`) with the same identity used for the app, OR
- Add `com.apple.security.cs.disable-library-validation` to the ad-hoc re-sign entitlements for debug bundles, OR
- Preserve/normalize Team IDs across all embedded frameworks so hardened-runtime library validation passes.

(Project-side alternative for Thesis: give the `TestApp` Debug config `RUNTIME_EXCEPTION_DISABLE_LIBRARY_VALIDATION = YES` + the disable-library-validation entitlement, as `ThesisApp` already has — but the general tooling fix is preferable.)

## Tasks
- [ ] Re-sign embedded package-product frameworks consistently (or add disable-library-validation) during AppBundlePreparer re-sign
- [ ] Verify TestApp launches and renders a window via build_debug_macos with no dyld/codesign abort


---

## Follow-up (2026-05-26): fix resolved the Core symbol, but launch now fails on a Team-ID / library-validation mismatch

Verified the fix **works for the original problem**: the embedded `Core.framework` is now the full 20 MB framework (`nm` shows `T _$s…plainTextSSvg`), signed `TeamIdentifier=D6GX9PC3SR`. The `Core.AttributedString.plainText` `Symbol missing` crash is gone.

However, TestApp still **crashes at launch** (dyld `prepare`/`halt`, `EXC_CRASH`/`SIGABRT`) — now on a different dependency:

```
Library not loaded: @rpath/SQLMacros_6ABCC7ADE539285E_PackageProduct.framework/…
Reason: code signature … not valid for use in process: mapping process and
        mapped file (non-platform) have different Team IDs
```

Signing audit of the prepared bundle:
- `TestApp.debug.dylib` → `TeamIdentifier=D6GX9PC3SR`, `flags=0x10000(runtime)` (hardened runtime)
- embedded `Core.framework` (re-signed by the fix) → `TeamIdentifier=D6GX9PC3SR`
- `SQLMacros_…_PackageProduct.framework` (embedded **and** in `PackageFrameworks/`) → **`TeamIdentifier=not set`** (ad-hoc)

`SQLMacros_…_PackageProduct` is a Swift-macro package product that `Zotero.framework` reexports at runtime. Because `AppBundlePreparer` re-signs the bundle with the developer team identity **and** hardened runtime, library validation now rejects the ad-hoc-signed macro framework (team mismatch). Before the fix, launch died earlier on the Core stub, masking this.

Reproduces via `build_debug_macos` (let the process run after `debug_continue` → it aborts; under LLDB it sits suspended so it looks alive) and via direct `DYLD_FRAMEWORK_PATH` exec.

### Suggested fix (one of)
- When re-signing, also re-sign embedded **package-product** frameworks (e.g. `*_PackageProduct.framework`) with the same identity used for the app, OR
- Add `com.apple.security.cs.disable-library-validation` to the ad-hoc re-sign entitlements for debug bundles, OR
- Preserve/normalize Team IDs across all embedded frameworks so hardened-runtime library validation passes.

(Project-side alternative for Thesis: give the `TestApp` Debug config `RUNTIME_EXCEPTION_DISABLE_LIBRARY_VALIDATION = YES` + the disable-library-validation entitlement, as `ThesisApp` already has — but the general tooling fix is preferable.)

## Tasks
- [ ] Re-sign embedded package-product frameworks consistently (or add disable-library-validation) during AppBundlePreparer re-sign
- [ ] Verify TestApp launches and renders a window via build_debug_macos with no dyld/codesign abort



## Summary of Changes (resolved)

`AppBundlePreparer.resignBundle` now injects `com.apple.security.cs.disable-library-validation` into the entitlements it signs with (new `entitlementsWithLibraryValidationDisabled(from:)` helper parses the extracted plist, sets the key, re-serializes; synthesizes a fresh dict when the bundle had none). The bundle is now always re-signed with explicit entitlements.

**Why this is right:** symlinking the full mergeable-library framework and SPM `*_PackageProduct.framework`s into the bundle means it can legitimately contain code signed ad-hoc / by a different team (Swift-macro package products `Zotero.framework` reexports). Under hardened runtime, library validation rejects those Team-ID mismatches and dyld aborts at launch. Disabling library validation on the *debug* re-sign mirrors `RUNTIME_EXCEPTION_DISABLE_LIBRARY_VALIDATION` (which `ThesisApp` already sets) and generalizes across all embedded frameworks without chasing each signing identity.

**Verification (the step skipped before):** forced a clean re-prepare of Thesis `TestApp`, confirmed the re-signed bundle carries `disable-library-validation`, then launched standalone via `open` (the LaunchServices path that strips `DYLD_*` and previously crashed). TestApp runs, opens a window, no new crash report. Both the Core `Symbol missing` crash and the SQLMacros Team-ID library-validation abort are gone.

Files: `Sources/Core/AppBundlePreparer.swift`, `Tests/AppBundlePreparerTests.swift` (+2 tests).

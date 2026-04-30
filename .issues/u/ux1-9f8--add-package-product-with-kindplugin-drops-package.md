---
# ux1-9f8
title: add_package_product with kind=plugin drops package reference
status: completed
type: bug
priority: high
tags:
    - xc-project
created_at: 2026-04-26T21:30:21Z
updated_at: 2026-04-30T16:30:50Z
sync:
    github:
        issue_number: "288"
        synced_at: "2026-04-30T17:20:52Z"
---

## Problem

When linking a remote SPM build tool plugin to a target, the xc-project MCP tools cannot produce a buildable pbxproj state. The two relevant tools each leave the `XCSwiftPackageProductDependency` in a broken configuration:

### `mcp__xc-project__add_package_product` with `kind=plugin`
- Correctly skips the Frameworks build phase
- **Drops the `package = <remote ref>` link** on the `XCSwiftPackageProductDependency` entry
- Reports: `(no existing package reference found — product will resolve at build time)` even when the `XCRemoteSwiftPackageReference` is already present in the project
- Result: xcodebuild fails with `Missing package product 'X'`

### `mcp__xc-project__add_swift_package` with `product_name` + `target_name`
- Correctly wires the `package = <remote ref>` link
- **Adds the plugin to the Frameworks build phase as a `PBXBuildFile`** (wrong — build tool plugins should not be linked as frameworks)

Neither path produces a working pbxproj entry of the form:
```
DA39E3D6... /* SwiftiomaticBuildToolPlugin */ = {
    isa = XCSwiftPackageProductDependency;
    package = D3670D44... /* XCRemoteSwiftPackageReference "swiftiomatic-plugins" */;
    productName = SwiftiomaticBuildToolPlugin;
};
```
…with no corresponding `PBXBuildFile` in the Frameworks build phase.

## Reproduction

1. Project has `XCRemoteSwiftPackageReference` for `https://github.com/toba/swiftiomatic-plugins`
2. Call `add_package_product` with `product_name=SwiftiomaticBuildToolPlugin`, `kind=plugin`, `target_name=ThesisApp`
3. Inspect pbxproj — the new `XCSwiftPackageProductDependency` is missing the `package = ...` field

## Expected

`add_package_product` with `kind=plugin` should:
- Detect the existing `XCRemoteSwiftPackageReference` matching the product
- Wire the `package` field on the new `XCSwiftPackageProductDependency`
- Skip the Frameworks build phase (already correct)

## Workaround

User must hand-edit pbxproj, but `jig nope` blocks direct edits to enforce xc-mcp usage — leaving no working path.

## Discovered

While fixing build of toba/thesis after a swiftiomatic-plugins package was added but pbxproj product entry was malformed.



## Summary of Changes

- `Sources/Tools/Project/AddPackageProductTool.swift`: extended package-reference resolution. New priority order:
  1. Explicit `package_url` / `package_path` argument (resolved against `project.remotePackages` / `localPackages`)
  2. Existing linked `XCSwiftPackageProductDependency` on another target (legacy behavior)
  3. Discovery via local `Package.swift` sources, matched back to the project's remote packages by directory basename ↔ repo URL last component
- Added `package_url` and `package_path` parameters to the tool schema; mutually exclusive.
- Refactored candidate-package-dir scan into a shared helper used by both kind-detection and reference discovery.
- `Tests/AddPackageProductToolTests.swift`: added three tests — explicit `package_url` resolution, missing-URL failure, and discovery via `SourcePackages/checkouts`.

All 10 AddPackageProductToolTests pass. The remote-plugin scenario from the repro now produces a correct `XCSwiftPackageProductDependency` with the `package` field wired and no entry in the Frameworks build phase.



## Update after first fix

`add_package_product --kind plugin --package_url <url>` now correctly produces the expected pbxproj entry:
```
DA39E3D6... /* SwiftiomaticBuildToolPlugin */ = {
    isa = XCSwiftPackageProductDependency;
    package = D3670D44... /* XCRemoteSwiftPackageReference "swiftiomatic-plugins" */;
    productName = SwiftiomaticBuildToolPlugin;
};
```
…and skips the Frameworks build phase. ✓

**However, xcodebuild still fails** with `Missing package product 'SwiftiomaticBuildToolPlugin'` even after `clean --derived-data` and a clean `xcodebuild -resolvePackageDependencies` (which resolves swiftiomatic-plugins @ 1.2.2 successfully).

Hypothesis: build tool plugins may need `productName = "plugin:SwiftiomaticBuildToolPlugin"` (with `plugin:` prefix) for xcodebuild to recognize them — or possibly a separate `PBXBuildRule` / build phase entry. Needs investigation.

The plugin product was correctly resolved by SPM but xcodebuild's project graph isn't binding the `packageProductDependencies` entry to the resolved plugin.



## Investigation: xcodebuild side bug

Spent extensive cycles diagnosing. The pbxproj entry produced by `add_package_product --kind plugin` is structurally identical to what Xcode generates. The remaining build failure is an Apple-side issue, not an xc-mcp bug:

### Root cause

xcodebuild's pbxproj→PIF conversion auto-injects every `XCSwiftPackageProductDependency` from a target's `packageProductDependencies` list as a `PBXBuildFile` in the `com.apple.buildphase.frameworks` phase, regardless of product kind. Verified by inspecting `DerivedData/.../XCBuildData/PIFCache/target/TARGET@v11_*-json`:

```json
{
  "type": "com.apple.buildphase.frameworks",
  "buildFiles": [
    { "guid": "f893...", "targetReference": "PACKAGE-PRODUCT:SwiftiomaticBuildToolPlugin" }
  ]
}
```

This buildFile references a `PackageProductTarget` GUID `PACKAGE-PRODUCT:SwiftiomaticBuildToolPlugin` that **SPM never generates** for plugin products. From `swift-package-manager/Sources/XCBuildSupport/PIFBuilder.swift:393`:

```swift
case .plugin, .macro:
    return  // skip — no PIF target created for plugin products
```

So Xcode looks up `PACKAGE-PRODUCT:SwiftiomaticBuildToolPlugin`, finds nothing, and throws `WorkspaceErrors.missingPackageProduct` (`swift-build/Sources/SWBCore/ProjectModel/Workspace.swift:299`).

### Verification

- `productName = "plugin:SwiftiomaticBuildToolPlugin"` prefix → still fails (verified)
- `objectVersion = 77` (downgrade from 100) → still fails (verified)
- Fresh DerivedData clean + rebuild → still fails (verified)
- Removing plugin from frameworks phase entirely → Xcode auto-injects it anyway (verified via PIF cache)

### Why does Xcode UI work for some users?

Real-world projects that build successfully with build-tool plugins (e.g., SwiftLintPlugin) typically attach the plugin via Xcode's UI "Build Phases → Run Build Tool Plug-ins". My binary inspection of `DevToolsCore`, `IDEFoundation`, `IDEKit`, and `IDESwiftPackageCore` found **no separate isa type or pbxproj field** for this — only `XCSwiftPackageProductDependency` and `packageProductDependencies`. The mechanism remains opaque; the wiring may live in xcuserdata, a sidecar settings file, or undocumented PIF post-processing performed only by the Xcode IDE process (not by `xcodebuild`).

### Recommendation

`add_package_product --kind plugin` produces a textbook-correct pbxproj entry but the resulting project is not buildable via `xcodebuild` alone. Two possible follow-ups:
1. Add a runtime warning in the tool when `kind=plugin` is detected, pointing users at this limitation.
2. File feedback with Apple, or wait for a swift-build update that handles plugin products in the pbxproj→PIF conversion path.

The original wiring fix (linking `package = <ref>` correctly) is preserved and remains useful — it produces the expected pbxproj output and matches what Xcode itself writes.

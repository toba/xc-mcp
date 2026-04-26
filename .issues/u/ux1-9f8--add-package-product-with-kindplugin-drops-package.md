---
# ux1-9f8
title: add_package_product with kind=plugin drops package reference
status: completed
type: bug
priority: high
tags:
    - xc-project
created_at: 2026-04-26T21:30:21Z
updated_at: 2026-04-26T21:40:24Z
sync:
    github:
        issue_number: "288"
        synced_at: "2026-04-26T21:40:50Z"
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

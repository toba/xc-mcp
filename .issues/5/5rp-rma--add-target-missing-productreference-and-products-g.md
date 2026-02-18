---
# 5rp-rma
title: add_target missing productReference and Products group entry
status: completed
type: bug
priority: high
created_at: 2026-02-18T05:16:20Z
updated_at: 2026-02-18T05:19:39Z
---

## Problem

`add_target` creates a `PBXNativeTarget` but does not:

1. Create a `PBXFileReference` for the build product (e.g. `MyTests.xctest`, `my-tool`)
2. Set the `productReference` field on the `PBXNativeTarget`
3. Add the product file reference to the Products group

This causes Xcode to fail with "No test bundle product for testingSpecifier" when trying to run tests for the new target, and likely causes similar issues for other target types.

## Expected

When creating a target, `add_target` should:
- Create a `PBXFileReference` with the correct `explicitFileType` (e.g. `wrapper.cfbundle` for test bundles, `compiled.mach-o.executable` for CLI tools, `wrapper.application` for apps)
- Set `includeInIndex = 0`, `sourceTree = BUILT_PRODUCTS_DIR`
- Set `productReference` on the `PBXNativeTarget` to point to this file reference
- Add the file reference to the Products group (`PBXGroup` named "Products")

## Reproduction

```
add_target(project_path: "Foo.xcodeproj", target_name: "FooUITests", product_type: "uiTestBundle", bundle_identifier: "com.example.FooUITests")
```

Then inspect the pbxproj — the target will have no `productReference` field and no corresponding `PBXFileReference` in the Products group.

## Discovered

While adding `DiagnosticAppUITests` and `fixture-seeder` targets to the Thesis project. Both targets had to be manually patched in the pbxproj.

## Summary of Changes

- Added `explicitFileType` computed property on `PBXProductType` mapping each product type to its correct Xcode file type string
- `add_target` now creates a `PBXFileReference` with `sourceTree = BUILT_PRODUCTS_DIR`, `includeInIndex = 0`, and the correct `explicitFileType`
- Sets `productReference` on the `PBXNativeTarget`
- Adds the product file reference to the project's Products group
- Added test assertions verifying product reference, file type, and Products group membership across all parameterized product type test cases

---
# 9gs-mlm
title: 'add_package_product: detect plugin products and skip Frameworks linkage'
status: completed
type: bug
priority: high
created_at: 2026-04-26T02:47:48Z
updated_at: 2026-04-26T03:32:25Z
sync:
    github:
        issue_number: "287"
        synced_at: "2026-04-26T21:40:50Z"
---

When linking a Swift Package plugin product (e.g. `SwiftiomaticBuildToolPlugin`) to a native target via `add_package_product`, the tool currently:

1. Adds an `XCSwiftPackageProductDependency` to the target's `packageProductDependencies` (correct)
2. Adds a `PBXBuildFile` referencing the product
3. Adds that `PBXBuildFile` to the target's `PBXFrameworksBuildPhase` (**incorrect** — plugins are not frameworks)

Result: Xcode reports `Missing package product 'SwiftiomaticBuildToolPlugin'` on the target, since it tries to link the plugin as a framework.

**Expected:** for plugin products (build tool or command), only add the `XCSwiftPackageProductDependency` entry. Build tool plugins are then auto-discovered by Xcode and run during the build; they do not appear in any build phase.

**Workaround:** none via xc-project tools — `remove_package_product` removes everything, and there's no `add_plugin_product` variant.

**Repro:**
```
add_swift_package(url=https://github.com/toba/swiftiomatic-plugins, requirement=from: 0.32.2)
add_package_product(target=ThesisApp, product=SwiftiomaticBuildToolPlugin)
# Xcode shows: Missing package product 'SwiftiomaticBuildToolPlugin'
```

Detection options:
- Resolve the package and inspect `Package.swift` products for `.plugin(...)` types
- Or accept a `kind: plugin` parameter on `add_package_product`



## Summary of Changes

- `add_package_product` now accepts an optional `kind` parameter (`auto` | `library` | `plugin`); `auto` is the default.
- `plugin` adds the `XCSwiftPackageProductDependency` only — the product is no longer appended to the target's `PBXFrameworksBuildPhase` (which Xcode rejected with "Missing package product").
- `auto` mode best-effort detects the kind by reading `Package.swift` from local packages declared on the project (`XCLocalSwiftPackageReference`) and from common adjacent checkout dirs (`.build/checkouts`, `.swiftpm/checkouts`, `SourcePackages/checkouts`), matching `.plugin(name: "X")` / `.library(name: "X")` / `.executable(name: "X")`. Falls back to `library`.
- For remote packages without on-disk source, callers should pass `kind: "plugin"` explicitly.
- Tests: added `plugin kind skips frameworks build phase` and `auto-detects plugin from local Package.swift`; updated existing message assertion.



## Summary of Changes

`add_package_product` now accepts a `kind` parameter (`auto`/`library`/`plugin`). With `kind: plugin` the product is added to `packageProductDependencies` only and skipped from the Frameworks build phase. Default `auto` detects from local `Package.swift` sources.

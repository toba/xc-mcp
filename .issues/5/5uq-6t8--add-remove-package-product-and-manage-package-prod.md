---
# 5uq-6t8
title: Add remove_package_product and manage_package_product_dependencies tools
status: completed
type: feature
priority: normal
tags:
    - enhancement
created_at: 2026-03-31T16:33:05Z
updated_at: 2026-03-31T16:39:40Z
sync:
    github:
        issue_number: "247"
        synced_at: "2026-03-31T16:44:37Z"
---

When fixing duplicate SPM package product references in Xcode projects (e.g. duplicate HTTPTypes entries across Core and TestSupport), the only option currently is manual pbxproj editing. The existing `remove_framework` tool handles system/custom frameworks but not SPM package products.

## Requested Tools

### `remove_package_product`
Remove a specific SPM package product dependency from a target.

Parameters:
- `project_path` (required)
- `target_name` (required)
- `product_name` (required) — e.g. "HTTPTypes"

Should remove:
1. The `PBXBuildFile` entry from the target's Frameworks build phase (if present)
2. The `XCSwiftPackageProductDependency` entry from the target's `packageProductDependencies` array
3. The `XCSwiftPackageProductDependency` declaration itself (if no other target references it)

### `list_package_products`
List all SPM package product dependencies for a target (or all targets).

Parameters:
- `project_path` (required)
- `target_name` (optional) — list for all targets if omitted

Should show: product name, package reference, which targets reference each product, and whether it appears in both `packageProductDependencies` and the Frameworks build phase.

## Context

Thesis project had two separate `XCSwiftPackageProductDependency` entries for HTTPTypes:
- `964EA1AA2C55B7CE005967B5` (used by Core)
- `AA00000000000000000E0002` (used by TestSupport)

Both pointed to the same package (`swift-http-types`) but were separate entries, causing duplicate ObjC class warnings at test launch. Manual pbxproj surgery was required to fix. These tools would make this a one-command operation.


## Summary of Changes

Added two new tools:

- **`remove_package_product`** — removes a specific SPM package product dependency from a target (build file + product dependency) without removing the package itself
- **`list_package_products`** — lists all SPM package product dependencies for a target or all targets, showing package source and build phase status

Both tools registered in `xc-project` focused server and `xc-mcp` monolithic server. 11 new tests added.

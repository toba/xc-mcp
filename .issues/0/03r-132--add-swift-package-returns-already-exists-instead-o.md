---
# 03r-132
title: add_swift_package returns 'already exists' instead of linking product to new target
status: completed
type: bug
priority: high
created_at: 2026-03-01T18:16:31Z
updated_at: 2026-03-01T18:19:40Z
sync:
    github:
        issue_number: "154"
        synced_at: "2026-03-01T18:23:52Z"
---

## Bug

When a local Swift package is already added to the Xcode project but you want to link one of its products to a **different target**, `add_swift_package` returns early with "already exists" without linking the product.

### Reproduction

1. Project already has local package \`...\` added (linked to SwiftiomaticExtension target)
2. Call:
   ```
   add_swift_package(package_path: "..", product_name: "SwiftiomaticLib", target_name: "SwiftiomaticApp")
   ```
3. Result: \`"Local Swift Package '..' already exists in project"\` — no linking happens

### Root Cause

In \`AddSwiftPackageTool.swift\` (lines ~196–206 for local, ~145–154 for remote), the existence check returns early **before** attempting to link the product to the specified target:

\`\`\`swift
if project.localPackages.contains(where: { $0.relativePath == packagePath }) {
    return CallTool.Result(content: [.text("Local Swift Package '...' already exists in project")])
}
\`\`\`

The \`addProductToTarget()\` logic that would handle linking is never reached.

### Expected Behavior

When the package already exists AND \`target_name\` is specified:
1. Skip adding to \`localPackages\` (it's already there)
2. Still proceed to link the specified \`product_name\` to the target via \`addProductToTarget()\`
3. Only return "already exists" if the product is **already linked** to that specific target

### Affected Files

- \`Sources/Tools/Project/AddSwiftPackageTool.swift\` — early return logic for both local and remote packages

## Summary of Changes

Fixed `AddSwiftPackageTool` to link package products to targets even when the package already exists in the project:

- **Remote packages**: When package URL already exists and `target_name` is provided, skips re-adding the package reference but proceeds to link the specified product to the target
- **Local packages**: Same behavior for local package paths
- **Duplicate detection**: Added guard in `addProductToTarget()` that throws if the product is already linked to the specified target, preventing duplicate build file entries
- **Tests**: Added 3 new tests covering remote re-link, local re-link, and duplicate rejection; added `createTestProjectWithTwoTargets` helper

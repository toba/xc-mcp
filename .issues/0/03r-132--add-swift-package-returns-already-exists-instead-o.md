---
# 03r-132
title: add_swift_package returns 'already exists' instead of linking product to new target
status: completed
type: bug
priority: high
created_at: 2026-03-01T18:16:31Z
updated_at: 2026-03-01T18:43:00Z
sync:
    github:
        issue_number: "154"
        synced_at: "2026-03-01T18:44:47Z"
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


## Still Broken (2026-03-01)

The fix was marked completed but the bug still reproduces. Calling:

```
add_swift_package(package_path: "..", product_name: "SwiftiomaticLib", target_name: "SwiftiomaticApp")
```

Still returns: `"Local Swift Package '..' already exists in project"` — the product is NOT linked to SwiftiomaticApp.

The app target currently has a bogus `System/Library/Frameworks/SwiftiomaticLib.framework` reference (created via `add_framework` as a workaround) instead of a proper package product dependency.

### What needs to happen

When the package already exists in the project and `target_name` + `product_name` are provided, the tool must:
1. Skip the "add package to project" step (already done)
2. Still call `addProductToTarget()` to link the product to the specified target
3. The early return on "already exists" must NOT fire when a target linkage is requested


## Test Spec

Add the following test to `AddSwiftPackageToolTests.swift`. It reproduces the exact real-world scenario that fails: a local package at `..` with product `SwiftiomaticLib` is already linked to an extension target, and the caller wants to link it to a second app target.

### Test: `existingLocalPackageLinksToDifferentTarget_realWorldScenario`

```swift
@Test("Existing local package at parent dir links product to second target")
func existingLocalPackageLinksToDifferentTarget_realWorldScenario() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString,
    )
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
    try TestProjectHelper.createTestProjectWithTwoTargets(
        name: "TestProject", target1: "SwiftiomaticApp", target2: "SwiftiomaticExtension",
        at: projectPath,
    )

    let tool = AddSwiftPackageTool(pathUtility: PathUtility(basePath: tempDir.path))

    // Step 1: Add local package ".." to extension target (first-time add, should succeed)
    let args1: [String: Value] = [
        "project_path": Value.string(projectPath.string),
        "package_path": Value.string(".."),
        "target_name": Value.string("SwiftiomaticExtension"),
        "product_name": Value.string("SwiftiomaticLib"),
    ]
    let result1 = try tool.execute(arguments: args1)
    guard case let .text(msg1) = result1.content.first else {
        Issue.record("Expected text result for first add")
        return
    }
    #expect(msg1.contains("Successfully added local Swift Package"))

    // Step 2: Link same package to app target (package exists, should still link)
    let args2: [String: Value] = [
        "project_path": Value.string(projectPath.string),
        "package_path": Value.string(".."),
        "target_name": Value.string("SwiftiomaticApp"),
        "product_name": Value.string("SwiftiomaticLib"),
    ]
    let result2 = try tool.execute(arguments: args2)
    guard case let .text(msg2) = result2.content.first else {
        Issue.record("Expected text result for second add")
        return
    }

    // MUST NOT return the bare "already exists" message
    #expect(!msg2.contains("already exists in project"))
    // MUST confirm the product was linked
    #expect(msg2.contains("linked product"))
    #expect(msg2.contains("SwiftiomaticApp"))

    // Verify both targets have the product dependency
    let xcodeproj = try XcodeProj(path: projectPath)
    let appTarget = xcodeproj.pbxproj.nativeTargets.first { $0.name == "SwiftiomaticApp" }
    let extTarget = xcodeproj.pbxproj.nativeTargets.first {
        $0.name == "SwiftiomaticExtension"
    }
    #expect(appTarget?.packageProductDependencies?.count == 1)
    #expect(extTarget?.packageProductDependencies?.count == 1)

    // Verify only one local package reference exists (not duplicated)
    let project = try xcodeproj.pbxproj.rootProject()
    let localRefs = project?.localPackages.filter { $0.relativePath == ".." }
    #expect(localRefs?.count == 1)

    // Verify both targets have a Frameworks build phase with the product
    for targetName in ["SwiftiomaticApp", "SwiftiomaticExtension"] {
        let target = xcodeproj.pbxproj.nativeTargets.first { $0.name == targetName }
        let fwPhase = target?.buildPhases.first { $0 is PBXFrameworksBuildPhase }
            as? PBXFrameworksBuildPhase
        #expect(fwPhase != nil, "\(targetName) should have a Frameworks build phase")
        let hasBuildFile = fwPhase?.files?.contains { $0.product?.productName == "SwiftiomaticLib" }
            ?? false
        #expect(hasBuildFile, "\(targetName) Frameworks phase should reference SwiftiomaticLib")
    }
}
```

### Additional fix needed: `addProductToTarget` ignores `localPackageRef`

The `localPackageRef` parameter at line 294 is named `_` (unused). When linking a product from an already-existing local package, the method creates a `XCSwiftPackageProductDependency` with `package: nil`. This may cause Xcode to not properly resolve the package.

The method should either:
- Use the `localPackageRef` to look up the package reference and associate it with the product dependency
- Or find the existing local package reference from the pbxproj when re-linking

The existing test `existingLocalPackageLinksToNewTarget` passes only because it checks `packageProductDependencies?.count` — it doesn't verify the dependency actually references the package.



## Resolution (2026-03-01)

The core fix from commit 241b8c9 is correct and working. Both remote and local "already exists" paths now proceed to call `addProductToTarget()` when `target_name` is provided.

Added the thorough real-world regression test from the test spec (`existingLocalPackageLinksToDifferentTarget_realWorldScenario`) — verifies:
- Product linked to both targets
- No duplicate local package reference
- Both targets have Frameworks build phases referencing the product

Re: `localPackageRef _` — this is **not a bug**. `XCSwiftPackageProductDependency.package` is typed as `XCRemoteSwiftPackageReference?` and only applies to remote packages. Local package products are resolved by product name alone, so `package: nil` is correct.

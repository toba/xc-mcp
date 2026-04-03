---
# v0r-tum
title: add_framework silently fails to add framework to target
status: completed
type: bug
priority: normal
created_at: 2026-04-03T23:19:29Z
updated_at: 2026-04-03T23:32:10Z
sync:
    github:
        issue_number: "257"
        synced_at: "2026-04-03T23:39:40Z"
---

## Tasks

- [x] Detect existing BUILT_PRODUCTS_DIR product references before classifying bare names as system frameworks
- [x] Handle `hasLocalProduct` path in framework filename/path resolution
- [x] Fix duplicate detection to check `frameworkFileName` for path comparison
- [x] Add tests: bare name with local product, bare name without (system framework), duplicate detection
- [x] All 14 AddFrameworkToolTests pass

## Bug

`mcp__xc-project__add_framework` reports success but does not actually add the framework to the target's Frameworks build phase.

## Steps to reproduce

1. Have a static library target (e.g. TestSupport) that links XCTest.framework and Testing.framework
2. Call `add_framework` with `framework_name: "Core"` and `target_name: "TestSupport"`
3. Tool returns success message
4. Check the target's PBXFrameworksBuildPhase — Core.framework was NOT added

## Expected

A new PBXBuildFile entry for Core.framework should be created and added to the target's Frameworks build phase files array.

## Actual

No change to pbxproj. The target still only has its original frameworks.

## Context

This was discovered while trying to add Core and GRDB framework dependencies to the TestSupport static library target in the Thesis project. The tool reported success for both but neither was actually added.


## Summary of Changes

The root cause was in `AddFrameworkTool.execute()`: when `framework_name` was a bare name like `"Core"` (no `.framework` suffix), the tool classified it as a system framework and created an sdkRoot reference to `System/Library/Frameworks/Core.framework`. For projects with a local framework target named "Core", this was incorrect — it should find and reuse the existing `BUILT_PRODUCTS_DIR` product reference.

Fix: before classifying a bare name as a system framework, check if a matching product reference exists in `BUILT_PRODUCTS_DIR`. If found, treat it as a local product and reuse the existing reference. Also fixed the duplicate detection to compare against `frameworkFileName` (e.g. `Core.framework`) in addition to the raw `frameworkName`.

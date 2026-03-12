---
# zgh-8i1
title: Add build-for-testing and test plan selection tools
status: completed
type: feature
priority: high
tags:
    - enhancement
created_at: 2026-03-12T04:29:28Z
updated_at: 2026-03-12T04:41:09Z
sync:
    github:
        issue_number: "202"
        synced_at: "2026-03-12T04:43:58Z"
---

## Context

During a Thesis session improving pipeline benchmark tests, several xc-mcp tooling gaps caused wasted time:

1. **`build_macos` doesn't compile test targets** — `build_macos` succeeded but `test_macos` immediately failed with compilation errors in DOMTests. The `build` action only compiles app/framework targets, not test bundles. This gave false confidence that the code compiled. `xcodebuild build-for-testing` exists for exactly this purpose but has no MCP equivalent.

2. **`list_test_plan_targets` only shows scheme-attached test plans** — the project had a `Performance.xctestplan` with the relevant tests, but it wasn't attached to the Standard scheme. `list_test_plan_targets` only queries scheme-attached plans, so it was invisible. There's no way to list all `.xctestplan` files in a project or query a specific test plan's contents.

3. **No test plan selection in `test_macos`** — `test_macos` always uses the scheme's default test plan. When tests live in a non-default plan (e.g. Performance), there's no way to target them. `xcodebuild test` supports `-testPlan <name>` but the MCP tool doesn't expose it.

## Proposed Changes

### 1. Add `build_for_testing` tool (or add flag to `build_macos`)

Either a new tool or a `for_testing: true` parameter on `build_macos` that runs `xcodebuild build-for-testing`. This compiles all test targets without executing them — useful for fast compilation checks before committing to a full test run.

### 2. Add `test_plan` parameter to `test_macos`

Add an optional `test_plan` parameter (string) that maps to `xcodebuild test -testPlan <name>`. This allows targeting tests that live in non-default test plans.

### 3. Enhance `list_test_plan_targets` to support all plans

Options:
- Add a `test_plan` parameter to query a specific plan by name
- Add a mode that lists ALL `.xctestplan` files in the project directory (not just scheme-attached ones)
- Both

## Impact

These gaps caused ~30 minutes of debugging a pre-existing DOMTests build failure that would have been caught immediately with `build_for_testing`, and prevented running the actual performance tests since they live in a non-default test plan.


## Summary of Changes

### 1. `build_macos` — `for_testing` parameter
- Added `for_testing` boolean parameter to `build_macos` tool
- When true, runs `xcodebuild build-for-testing` instead of `build`, compiling all test targets without executing them
- Added `action` parameter to `XcodebuildRunner.build()` (defaults to `"build"`) to support this

### 2. `test_macos` / `test_sim` / `test_device` — `test_plan` parameter
- Added `test_plan` string parameter to the shared test schema properties
- Maps to `xcodebuild test -testPlan <name>`, allowing tests in non-default test plans to be targeted
- Added to `TestParameters` struct, `XcodebuildRunner.test()`, and all three test tools

### 3. `list_test_plan_targets` — `test_plan` and `all_plans` parameters
- Added `test_plan` parameter to query a specific test plan by name (finds `.xctestplan` file in the project directory regardless of scheme attachment)
- Added `all_plans` boolean to list every `.xctestplan` file in the project with targets
- Made `scheme` optional when `test_plan` or `all_plans` is specified
- Original scheme-based behavior preserved as the default mode

---
# 8jn-08a
title: Add test plan management tools to xc-project
status: completed
type: feature
priority: normal
created_at: 2026-02-22T02:40:09Z
updated_at: 2026-02-22T02:49:08Z
sync:
    github:
        issue_number: "122"
        synced_at: "2026-02-24T18:57:47Z"
---

## Problem

The xc-project MCP server has no tools for managing Xcode test plans (`.xctestplan` files) or adding them to schemes. This means agents can't:

1. Create a new test plan
2. Enable/disable test targets within an existing test plan
3. Add a test plan to a scheme's test action
4. Remove a test plan from a scheme

## Real-world example

In thesis, `ViewTests` (XCUI test target) is in `UnitTests.xctestplan` with `"enabled": false`. Running `test_macos(only_testing: ["ViewTests"])` fails with:

> Tests in the target "ViewTests" can't be run because "ViewTests" isn't a member of the specified test plan or scheme.

The fix requires creating a separate `View Tests.xctestplan` and adding a `<TestPlanReference>` to the Standard scheme's `<TestPlans>` block. Neither operation is possible via xc-project tools today.

## Proposed tools

### `create_test_plan`
- `name`: test plan name (becomes `{name}.xctestplan`)
- `test_targets`: array of target names to include
- `output_directory`: where to write the file (default: project root)
- `code_coverage_enabled`: bool (default: false)

### `add_target_to_test_plan`
- `test_plan_path`: path to `.xctestplan`
- `target_name`: name of the test target to add
- `enabled`: bool (default: true)

### `remove_target_from_test_plan`
- `test_plan_path`: path to `.xctestplan`
- `target_name`: name of the test target to remove

### `enable_test_plan_target`
- `test_plan_path`: path to `.xctestplan`
- `target_name`: target to enable/disable
- `enabled`: bool

### `add_test_plan_to_scheme`
- `scheme_name`: name of the scheme
- `test_plan_path`: path to `.xctestplan`
- `is_default`: bool (default: false)

### `remove_test_plan_from_scheme`
- `scheme_name`: name of the scheme
- `test_plan_path`: path to `.xctestplan`

### `list_test_plan_targets`
- `test_plan_path`: path to `.xctestplan`
- Returns target names with enabled/disabled status

## Notes

- Test plans are JSON files — straightforward to create/modify
- Scheme test plan references are XML (`<TestPlanReference>` inside `<TestPlans>`)
- Target identifiers in test plans reference pbxproj native target IDs — the tool should resolve target name → ID automatically
- The `containerPath` is always `"container:{project_name}"` relative to the project

## TODO

- [x] Implement test plan CRUD tools
- [x] Implement scheme ↔ test plan wiring tools
- [x] Add to xc-project tool registration


## Summary of Changes

All proposed tools implemented and registered:

- `create_test_plan`, `add_target_to_test_plan`, `remove_target_from_test_plan`
- `set_test_plan_target_enabled`, `add_test_plan_to_scheme`, `remove_test_plan_from_scheme`
- `list_test_plan_targets` (with enabled status), `set_test_target_application`

All tools registered in xc-project, xc-mcp (monolithic), and ServerToolDirectory.

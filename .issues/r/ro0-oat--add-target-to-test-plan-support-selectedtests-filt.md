---
# ro0-oat
title: 'add_target_to_test_plan: support selectedTests filtering'
status: completed
type: feature
priority: normal
created_at: 2026-04-01T22:25:16Z
updated_at: 2026-04-01T22:30:16Z
sync:
    github:
        issue_number: "252"
        synced_at: "2026-04-01T22:31:14Z"
---

When adding a target to a test plan via `add_target_to_test_plan`, allow specifying which XCTest classes or Swift Testing suites to include in the `selectedTests` block. Currently the tool adds the entire target with no filtering, requiring manual JSON editing to restrict to specific test classes.

Needed parameters:
- `xctest_classes: [String]?` — XCTest class names to include (e.g. `["XMLDecoderPerformanceTests"]`)
- `suites: [{ name: String, test_functions: [String]? }]?` — Swift Testing suites with optional function filter

When neither is provided, behavior is unchanged (adds full target). When provided, generates the `selectedTests` JSON block matching the xctestplan schema.

## Summary of Changes

- Added `xctest_classes` and `suites` optional parameters to `add_target_to_test_plan`
- When provided, generates a `selectedTests` block matching the xctestplan schema
- `xctest_classes` entries support optional `xctest_methods` for method-level filtering
- `suites` entries support optional `test_functions` for function-level filtering
- When neither parameter is provided, behavior is unchanged (adds full target)
- Added 5 new tests in `AddTargetToTestPlanToolTests`

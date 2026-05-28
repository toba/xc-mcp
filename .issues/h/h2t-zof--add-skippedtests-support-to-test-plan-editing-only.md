---
# h2t-zof
title: Add skippedTests support to test-plan editing (only skippedTags exists)
status: completed
type: feature
priority: normal
created_at: 2026-05-28T02:08:35Z
updated_at: 2026-05-28T02:12:59Z
sync:
    github:
        issue_number: "354"
        synced_at: "2026-05-28T02:13:39Z"
---

No tool manages a .xctestplan's `skippedTests` (exclusion list). Needed to drop XCTest perf classes (`PerformanceTestCase` subclasses) from a plan, the way Xcode/CI does via per-target `skippedTests` arrays.

## What exists today
- `set_test_plan_skipped_tags` — manages `skippedTags` (Swift Testing tags only; can't catch XCTest classes, which have no tags).
- `add_target_to_test_plan` (`xctest_classes`/`suites`) — populates **`selectedTests`**, an *inclusion* allowlist ("run ONLY these").

## Gap
No **`skippedTests`** *exclusion* support ("run everything EXCEPT these"). selectedTests is the inverse and impractical (would require enumerating hundreds of suites just to drop a few classes).

## Desired
Add `set_test_plan_skipped_tests` mirroring `set_test_plan_skipped_tags`:
- args: test_plan_path, tests (class/suite or 'Class/method()'), optional target_name (default = plan defaultOptions), action add|remove.
- Updates the `skippedTests` array on the matching target dict (or defaultOptions).

Found while stabilizing the Thesis iOS Tests plan (thesis issue sgp-4wi).


## Summary of Changes

Added `set_test_plan_skipped_tests` tool mirroring `set_test_plan_skipped_tags`, managing a .xctestplan's `skippedTests` exclusion list (plain `[String]` array on the target dict or `defaultOptions`).

- New: `Sources/Tools/Project/SetTestPlanSkippedTestsTool.swift` — args `test_plan_path`, `tests` (class/suite or `Class/method()`), optional `target_name` (default = plan defaultOptions), `action` add|remove. Removing all entries clears the key.
- Registered in `xc-project` (`ProjectMCPServer`) and the monolithic `XcodeMCPServer`.
- Added both `set_test_plan_skipped_tags` (pre-existing gap) and `set_test_plan_skipped_tests` to `ServerToolDirectory.projectTools` so cross-server hints work.
- New tests: `Tests/SetTestPlanSkippedTestsToolTests.swift` (8 tests, all passing).

Confirmed no prior `skippedTests` support existed (the only `skippedTests` match in Sources was unrelated, in `ErrorExtraction.swift`).

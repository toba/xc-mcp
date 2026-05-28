---
# 5gw-bj4
title: Expose 'parallelizable' setting for test plan targets
status: completed
type: feature
priority: normal
created_at: 2026-05-28T05:04:11Z
updated_at: 2026-05-28T05:09:19Z
sync:
    github:
        issue_number: "357"
        synced_at: "2026-05-28T05:10:27Z"
---

`set_test_plan_skipped_tags` and `set_test_plan_skipped_tests` cover the tag/test exclusion side of an `.xctestplan`, but there's no tool to manage the per-target `parallelizable` flag. Swift Testing defaults to parallel in-process execution; when an iOS app-hosted plan runs many tests concurrently and any of them transitively trigger a system XPC connection (CloudKit, NSUbiquitousKeyValueStore, CoreSymbolication, etc.) that schedules a completion block to the main queue, libdispatch eventually fires `BUG IN CLIENT OF LIBDISPATCH: Block was expected to execute on queue [com.apple.main-thread]` because the test host doesn't run a main runloop in parallel mode. The standard mitigation is per-target `\"parallelizable\": false` in the plan, but with `jig nope` blocking direct edits of `.xctestplan` files, MCP needs to write it.

## Suggested shape

```
mcp__xc-project__set_test_plan_target_parallelizable(
  test_plan_path: \"iOS Tests.xctestplan\",
  target_name: \"CoreTests\",
  enabled: false,
)
```

(Plan-level: omit `target_name` if Xcode supports a default; otherwise scope to the per-target block.)

Also accept the same on a plan-level `defaultOptions` block if Xcode honors it there.

## Source

toba/thesis sgp-4wi — whole-plan iOS run keeps hitting the libdispatch main-queue assertion mid-run, and the only way to bypass it without rewriting every offending call site is to disable parallel execution at the plan level.



## Summary of Changes

- Added `set_test_plan_target_parallelizable` tool (Sources/Tools/Project/SetTestPlanTargetParallelizableTool.swift) writing the per-target `parallelizable` boolean directly under each `testTargets` entry, or onto `defaultOptions.parallelizable` when `target_name` is omitted.
- Registered the tool in both the focused `xc-project` server and the monolithic `xc-mcp` server.
- Added Tests/SetTestPlanTargetParallelizableToolTests.swift (7 tests, all passing) covering per-target enable/disable, overwriting existing values, plan-level default, missing target, and missing-argument errors.

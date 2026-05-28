---
# hws-yed
title: 'set_test_plan_skipped_tags drops ''mode: or'' when adding to per-target block'
status: completed
type: bug
priority: high
created_at: 2026-05-28T04:42:48Z
updated_at: 2026-05-28T04:45:06Z
sync:
    github:
        issue_number: "356"
        synced_at: "2026-05-28T04:45:57Z"
---

While rebuilding the iOS Tests plan's skip list for toba/thesis sgp-4wi, `mcp__xc-project__set_test_plan_skipped_tags` was used to add tags to a per-target block (`target_name: CoreTests`). The tool wrote the tag list correctly but did NOT preserve the existing `\"mode\": \"or\"` key, leaving:

  \"skippedTags\" : { \"tags\" : [ \".api\", \".testSuiteFile\", \".performance\", \".cloudKit\", \".keychain\", \".manual\" ] }

…instead of the original:

  \"skippedTags\" : { \"mode\" : \"or\", \"tags\" : [ ... ] }

Xcode's per-target options override the plan's `defaultOptions`, so this block applies. Without `mode: or` the block defaults to AND semantics, so a test must have ALL listed tags simultaneously to be skipped — no real test does, so the per-target tag-skipping silently no-ops. This is the SAME bug sgp-4wi originally hit in this plan (we restored `mode: or` manually then; the MCP edit just regressed it).

## Repro

```
# Starting state (per-target block with mode: or):
\"skippedTags\" : { \"mode\" : \"or\", \"tags\" : [ \".api\" ] }

mcp__xc-project__set_test_plan_skipped_tags(
  test_plan_path: \"iOS Tests.xctestplan\",
  target_name: \"CoreTests\",
  tags: [\".cloudKit\"],
  action: \"add\",
)

# Result (mode dropped):
\"skippedTags\" : { \"tags\" : [ \".api\", \".cloudKit\" ] }
```

## Fix

When the existing per-target `skippedTags` JSON has a `mode` key, preserve it after the tag mutation. A reasonable secondary policy: if no `mode` is present and a write is being performed, default to `\"or\"` (matches `defaultOptions` and the rest of the project's plans), with a one-line warning in the tool response so the caller knows.

Adding a regression test that reads back the plan JSON after an `add` op and asserts `mode` survives would be cheap.

## Workaround

Remove the per-target block entirely (so `defaultOptions` applies) — that's what we did to unblock sgp-4wi.

## Source

toba/thesis sgp-4wi — `iOS Tests.xctestplan`, 2026-05-27.



## Summary of Changes

`Sources/Tools/Project/SetTestPlanSkippedTagsTool.swift` — `applyToTarget` no longer strips `mode` from per-target `skippedTags`. It now preserves an existing `mode` and defaults to `"or"` when none is set (matching the plan-level behavior), so per-target tag-skipping uses OR semantics instead of silently no-opping on AND.

`Tests/SetTestPlanSkippedTagsToolTests.swift` — The prior `Add tags to specific target` test asserted `mode == nil`, which encoded the bug. Inverted that assertion and added `Adding to existing per-target block preserves mode` as a regression test for the exact repro in this issue.

Note: this is the second pass on the same bug. The first 'fix' explicitly deleted `mode` based on a misread of Xcode's per-target serialization — Xcode preserves whatever `mode` the user authored; only the absence of the key means AND, which is rarely what callers want.

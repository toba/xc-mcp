---
# oi5-2fz
title: Add MCP tool to set test-plan configuration/default options (diagnosticCollectionPolicy, userAttachmentLifetime, etc.)
status: completed
type: task
priority: normal
created_at: 2026-06-22T16:28:59Z
updated_at: 2026-06-22T16:41:17Z
sync:
    github:
        issue_number: "394"
        synced_at: "2026-06-22T16:42:31Z"
---

## Gap

The `xc-project` test-plan tools cover targets, skipped tags, skipped tests, and the parallelizable flag (`SetTestPlanSkippedTagsTool`, `SetTestPlanSkippedTestsTool`, `SetTestPlanTargetParallelizableTool`, etc.), but there is **no** tool to edit a test plan's per-configuration `options` block or `defaultOptions`. Fields with no MCP coverage include:

- `diagnosticCollectionPolicy` (Always / OnFailure / Never)
- `userAttachmentLifetime` (keepNever / keepAlways / deleteOnSuccess)
- `uiTestingScreenshotsLifetime`
- `codeCoverage` (bool; CreateTestPlanTool sets it at creation but nothing edits it after)
- `mainThreadCheckerEnabled`
- `environmentVariableEntries` / `commandLineArgumentEntries`
- `targetForVariableExpansion`

## Why it matters

Consumers who must edit these (e.g. the Thesis project, where a `jig nope` hook is intended to force all test-plan edits through xc-mcp) currently have to fall back to a raw JSON file edit because no tool exists. Concretely: changing a plan's `diagnosticCollectionPolicy` from Always to OnFailure and `userAttachmentLifetime` to keepNever to cut per-test diagnostic overhead had to be done by hand.

## Proposed shape

A `set_test_plan_options` tool (mirroring the existing SetTestPlan*Tool pattern and reusing Core/TestPlanFile.swift):

- `test_plan_path` (required)
- `configuration_name` (optional) — target a named configurations[] entry's `options`; if omitted, edit `defaultOptions`
- one optional parameter per supported option key; only provided keys are written, others left untouched
- support clearing a key (reset to plan default / remove)

Keep it additive and schema-validated like the sibling tools. Env-var/arg-entry editing could be a follow-up if it complicates the first cut.

## Context
Source: Sources/Tools/Project/SetTestPlan*Tool.swift, Sources/Core/TestPlanFile.swift. Filed from toba/thesis issue tlw-n3s.

## Summary of Changes

Added `set_test_plan_options` MCP tool (`Sources/Tools/Project/SetTestPlanOptionsTool.swift`) to edit a test plan's per-configuration `options` block or plan-level `defaultOptions`.

Supported keys (first cut):
- `diagnostic_collection_policy` → `diagnosticCollectionPolicy` (Always / OnFailure / Never)
- `user_attachment_lifetime` → `userAttachmentLifetime` (keepNever / keepAlways / deleteOnSuccess)
- `ui_testing_screenshots_lifetime` → `uiTestingScreenshotsLifetime` (same lifetime enum)
- `code_coverage` → `codeCoverage` (bool)
- `main_thread_checker_enabled` → `mainThreadCheckerEnabled` (bool)

Behavior:
- `configuration_name` (optional) targets a named `configurations[]` entry's `options`; omitted = `defaultOptions`.
- Only provided keys are written; others left untouched. Enum values are schema- and execute-validated.
- `clear` array removes keys (reset to plan default), validated against known options.
- Mirrors the sibling `SetTestPlan*Tool` pattern and reuses `Core/TestPlanFile.swift`.

Registered in both `XcodeMCPServer` (monolithic) and `ProjectMCPServer` (focused), added to `ServerToolDirectory` (also backfilled the missing `set_test_plan_target_parallelizable` entry). Bumped tool counts in CLAUDE.md.

Deferred to a follow-up (as noted in the issue): `environmentVariableEntries` / `commandLineArgumentEntries` / `targetForVariableExpansion` editing (these need richer object/array inputs and project lookups).

Tests: `Tests/SetTestPlanOptionsToolTests.swift` (9 tests, all passing) covering set/clear, named-config vs defaultOptions, untouched-key preservation, and invalid-input errors.

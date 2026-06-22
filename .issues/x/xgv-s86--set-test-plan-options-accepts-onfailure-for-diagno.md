---
# xgv-s86
title: set_test_plan_options accepts OnFailure for diagnosticCollectionPolicy but Xcode 26.2 rejects it
status: completed
type: bug
priority: normal
created_at: 2026-06-22T18:19:01Z
updated_at: 2026-06-22T18:21:12Z
sync:
    github:
        issue_number: "395"
        synced_at: "2026-06-22T18:23:11Z"
---

## Problem

`mcp__xc-project__set_test_plan_options` exposes `diagnostic_collection_policy` with enum `[Always, OnFailure, Never]`, and the tool description recommends `OnFailure` ("Lowering diagnosticCollectionPolicy to OnFailure ... cuts per-test diagnostic overhead").

But `OnFailure` is NOT a value Xcode 26.2 accepts for `XCTHDiagnosticCollectionPolicy`. Writing it into a test plan makes the plan unreadable: Xcode aborts test runs with

> Tests cannot be run because the test plan could not be read. ... Error details: String representation of XCTHDiagnosticCollectionPolicy was not a supported value

So an agent that follows the tool's own guidance produces a broken, unrunnable test plan.

## Repro
1. set_test_plan_options(diagnostic_collection_policy: OnFailure)
2. Try to run the plan in Xcode 26.2 -> parse failure dialog above.

## Expected
The only Xcode-supported values appear to be `Always` and `Never`. Either drop `OnFailure` from the enum and fix the description, or verify against the current Xcode schema which values are valid and gate accordingly.

## Notes
- Surfaced in the Thesis project: a commit set the UnitTests plan to OnFailure (hallucinated value, reinforced by this tool's enum + description), breaking test runs. Fixed there by switching to `Never`.
- `userAttachmentLifetime: keepNever` is valid and unaffected.

## Summary of Changes

Dropped the unsupported `OnFailure` value from the `diagnostic_collection_policy` enum in `SetTestPlanOptionsTool` — Xcode 26.2 only accepts `Always` and `Never` for `XCTHDiagnosticCollectionPolicy`, and writing `OnFailure` made the plan unreadable.

- `Sources/Tools/Project/SetTestPlanOptionsTool.swift`: enum values now `[Always, Never]`; tool description no longer recommends `OnFailure` (now suggests `Never` for cutting per-test diagnostic overhead).
- `Tests/SetTestPlanOptionsToolTests.swift`: updated the set/read test to use `Never`.
- All 9 SetTestPlanOptionsToolTests pass.

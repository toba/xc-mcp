---
# gb7-io5
title: 'test_macos: don''t fail entire run when one only_testing target is invalid'
status: completed
type: bug
priority: normal
tags:
    - enhancement
created_at: 2026-03-21T19:29:26Z
updated_at: 2026-03-21T19:42:36Z
sync:
    github:
        issue_number: "229"
        synced_at: "2026-03-21T19:43:50Z"
---

## Context

When `only_testing` includes a mix of valid and invalid test targets, the entire test run fails with:

```
Tests in the target "ProjectTests" can't be run because "ProjectTests" isn't a member of the specified test plan or scheme.
```

This kills the valid targets too — in a real session, `["CoreTests", "ProjectTests"]` failed to run any tests at all, even though `CoreTests` is valid and has 1731 tests.

## Expected behavior

- Run the valid targets
- Warn about invalid targets in the output (not as an error that stops everything)

## Possible approaches

1. Pre-validate `only_testing` entries against `list_test_plan_targets` and filter out invalid ones, emitting a warning
2. If xcodebuild itself rejects the combo, retry with only the valid targets
3. Document this behavior so callers know to validate targets first

Option 1 is cleanest — catch the problem before invoking xcodebuild.

## Summary of Changes

- Added `ErrorExtractor.validateOnlyTesting` that pre-validates `only_testing` entries against available test targets (discovered from .xctestplan files and scheme testable references)
- Applied pre-validation to all three test tools: `TestMacOSTool`, `TestSimTool`, and `TestDeviceTool`
- When some entries are invalid: they are filtered out, a warning is prepended to the result, and valid entries still run
- When ALL entries are invalid: throws `invalidParams` with the warning (no point running xcodebuild)
- When no test targets can be discovered: skips validation to avoid false positives
- Added public `init` to `TestParameters` so tools can reconstruct it with filtered entries

---
# nnd-8d8
title: list_test_plan_targets should list testable targets for schemes without explicit test plans
status: completed
type: bug
priority: normal
tags:
    - bug
created_at: 2026-03-07T21:38:25Z
updated_at: 2026-03-07T21:49:36Z
sync:
    github:
        issue_number: "179"
        synced_at: "2026-03-07T21:56:31Z"
---

## Problem

For schemes that use the default "Test Scheme Action" (no .xctestplan file), the tool returns:

```
No test plans found for scheme 'TestApp'.
```

This is misleading — the scheme does have test targets (TestAppUITests), they're just configured inline in the xcscheme XML rather than via a test plan file.

## Expected behavior

Fall back to listing testable references from the scheme's `<TestAction><Testables>` section when no explicit test plans exist:

```
Scheme 'TestApp' (no test plan — using scheme test action):
  - TestAppUITests
```

## Summary of Changes

Added fallback logic to `list_test_plan_targets`: when no .xctestplan files exist, the tool now parses the xcscheme's `<TestAction><Testables>` section to list testable targets. Output clearly indicates the source is the scheme test action rather than a test plan. Supports both text and JSON output formats.

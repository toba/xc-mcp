---
# nnd-8d8
title: list_test_plan_targets should list testable targets for schemes without explicit test plans
status: ready
type: bug
priority: normal
tags:
    - bug
created_at: 2026-03-07T21:38:25Z
updated_at: 2026-03-07T21:38:25Z
sync:
    github:
        issue_number: "179"
        synced_at: "2026-03-07T21:39:58Z"
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

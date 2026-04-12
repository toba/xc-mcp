---
# dw7-050
title: swift_package_test truncates failure messages — rule/example identity lost
status: completed
type: bug
priority: normal
created_at: 2026-04-12T02:36:58Z
updated_at: 2026-04-12T02:46:43Z
sync:
    github:
        issue_number: "273"
        synced_at: "2026-04-12T02:48:30Z"
---

## Problem

When `swift_package_test` reports a test failure, it truncates the `Issue.record()` message, losing the detail that identifies *what* failed.

### Example

The test code records:
```swift
Testing.Issue.record("triggeringExample did not violate: \n```\n\(trigger.code)\n```")
```

But `swift_package_test` returns only:
```
Failures:
  Rule examples validate — Issue recorded: triggeringExample did not violate: (LintTestHelpers.swift:649)
```

The `trigger.code` snippet (which would tell you which rule's example failed) is completely absent. This makes parameterized tests (`@Test(arguments:)`) essentially undebuggable through the MCP tool — you can't tell which argument case failed without re-running with a narrower filter.

### Expected behavior

The full `Issue.record()` message should be preserved in the failure output, or at minimum enough of it to identify the failing case. For parameterized tests, the test argument description (e.g., `foundation_modernization`) should also appear.

### Reproduction

1. Have a Swift Testing parameterized test where one argument case fails
2. Run via `swift_package_test`
3. Observe that the failure message is truncated after the first colon

### Impact

Any project using `@Test(arguments:)` (common pattern) hits this — you have to binary-search with `--filter` to find the failing case, which is slow.


## Summary of Changes

Two fixes in `BuildOutputParser.swift`:

1. **Multi-line continuation**: Changed single-line check (`index + 1`) to a `while` loop that collects all consecutive `↳`/`􀄵` continuation lines, joined with `\n`. Multi-line `Issue.record()` messages (e.g., code snippets) are now fully preserved.

2. **Parameterized argument values**: Extracts `→ value` text from between `recorded an issue with N argument value(s)` and ` at file:line:col:`, appending it to the test name as `(→ value)`. Updated `normalizeTestName` to strip this suffix for deduplication.

Added 2 new tests: multi-line continuation and multi-line with argument values.

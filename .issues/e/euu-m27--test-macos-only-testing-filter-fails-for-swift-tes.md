---
# euu-m27
title: test_macos only_testing filter fails for Swift Testing backtick-escaped single-word method names
status: completed
type: bug
priority: normal
created_at: 2026-04-01T22:15:13Z
updated_at: 2026-04-01T22:22:31Z
sync:
    github:
        issue_number: "251"
        synced_at: "2026-04-01T22:23:53Z"
---

When running `test_macos` with `only_testing` filters like `CoreTests/DiffTests/class` or `CoreTests/DiffTests/\`class\`()`, the filter fails to match Swift Testing `@Test func \`class\`()` methods. The agent was forced to fall back to `xcodebuild test` directly.

The issue is that `class` is a single word (no spaces), so it doesn't match the backtick-escaping heuristic. The tool should support:
- `CoreTests/DiffTests/class` → match `@Test func class()` (keyword collision)
- `CoreTests/DiffTests/\`class\`` → match with explicit backticks

This gap forced the agent to bypass xc-mcp tooling entirely.

## Summary of Changes

- Extended `normalizeTestIdentifier` in `ArgumentExtraction.swift` to detect single-word Swift keywords and auto-wrap them in backticks with `()`
- Fixed backtick-wrapped methods missing trailing `()` (e.g. \`class\` → \`class\`())
- Added `swiftKeywords` set with ~50 reserved words
- Added 5 new test cases in `TestIdentifierNormalizationTests`
- Updated tool schema description to document keyword auto-wrapping

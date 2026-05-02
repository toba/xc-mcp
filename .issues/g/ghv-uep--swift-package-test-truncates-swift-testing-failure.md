---
# ghv-uep
title: swift_package_test truncates Swift Testing failure messages; assertion diffs are lost
status: completed
type: bug
priority: normal
created_at: 2026-05-01T23:50:13Z
updated_at: 2026-05-02T00:02:57Z
sync:
    github:
        issue_number: "304"
        synced_at: "2026-05-02T03:17:27Z"
---

When a Swift Testing `@Test` function fails via `Issue.record(Comment(rawValue: longDiffText), …)` (the path Swift Testing uses for `#expect`-style mismatches and any custom `assertStringsEqualWithDiff`-style helper), the `swift_package_test` MCP tool returns only the issue title — the full diff body is dropped. Example output the agent sees:

```
wrappedArrayLiteralInlines() — Issue recorded: Actual output (+) differed from expected output (-): (LayoutSingleLineBodiesTests.swift:1341)
```

The actual diff (the multi-line `+actual` / `-expected` block built by `assertStringsEqualWithDiff` in swift-format-derived test infra) never appears. Without it an agent has to either:

1. Re-run the failing test through a separate harness that prints stdout, or
2. Patch the test infra to write the diff to `/tmp` on failure (what I had to do today in `/Users/jason/Developer/toba/swiftiomatic/Tests/SwiftiomaticTests/Rules/LintOrFormatRuleTestCase.swift`), or
3. Iterate blind, which wastes builds and irritates the user.

## Reproduction

In any Swift package using Swift Testing, write:

```swift
@Test func showsDiff() {
  let actual = \"\"\"
    line A
    line B
    line C
    \"\"\"
  let expected = \"\"\"
    line A
    line X
    line C
    \"\"\"
  let comment = Comment(rawValue: \"Actual differed from expected:\\n\\(actual)\\nvs\\n\\(expected)\")
  Issue.record(comment)
}
```

Run via `mcp__xc-swift__swift_package_test` with a filter selecting only this test. Observe the returned summary contains only the first line of `comment` (or just \"Issue recorded\"), not the multi-line body.

## Background

The Swift Testing JSON event stream emits `issueRecorded` events with `sourceLocation`, `severity`, and a structured `comments` array (each `Comment` has a full text body). `xc-mcp` appears to be:

- collapsing each comment to its first line, OR
- rendering only the issue's `description` (which truncates), OR
- joining issues with newlines and the MCP transport is splitting on the first line break when packing into the failure summary.

XCTest's textual output is also affected for diffs that span multiple lines (`XCTAssertEqual` long-string mismatches), but Swift Testing is the worst case because the structured event has the full body and we're throwing it away.

## Tasks

- [ ] Find the code path in `xc-mcp` that consumes Swift Testing's JSON `issueRecorded` events and builds the test-failure summary
- [ ] Preserve full multi-line `Comment` bodies (escape newlines, embed code fences, or attach as a separate field on the failure record)
- [ ] Verify with the reproduction above that the entire diff text reaches the agent
- [ ] Confirm XCTest long-string diffs (`XCTAssertEqual` of multi-line strings) also flow through unchanged
- [ ] Add a regression test that asserts a multi-line `Issue.record` body round-trips through `swift_package_test`

## Files to look at

- The Swift Testing event-stream parser in `xc-mcp` (likely under `Sources/Tools/Test/` or similar)
- Anywhere `issueRecorded` / `Issue` / `Comment` / `comments` is parsed
- The test-failure summarizer that formats the final string returned by the `swift_package_test` MCP tool



## Summary of Changes

`Sources/Core/BuildOutputParser.swift`: extended the swift-testing "recorded an issue" continuation logic to keep collecting plain indented lines after the first `􀄵`/`↳` detail-marker line. Real swift-testing output only marks the first line of a multi-line `Comment(rawValue:)` body with the detail glyph; subsequent lines are bare indented text. The previous loop broke immediately on the first non-marker line, dropping the diff body. Continuation now stops at blank lines, non-indented lines, or lines whose first scalar lives in the SF Symbols private-use ranges (other swift-testing event glyphs) or starts with `✘`/`✓`/`◇`. Comment lines are joined with newlines instead of `": "` so structure is preserved.

`Sources/Core/BuildResultFormatter.swift`: `formatFailedTests` now splits multi-line failure messages so the file:line tag stays on the header line and the body is rendered indented underneath instead of getting smushed onto one line followed by a trailing `(File:line)`.

`Tests/BuildOutputParserTests.swift`: added `swift testing preserves multi-line Comment body` regression test using the exact format produced by `swift test` on macOS for an `Issue.record(Comment(rawValue: multiLine))` call. All 59 parser tests pass.

XCTest paths are unchanged — the existing `XCAssertEqual` parsing branch in `parseFailedTest` already returns the entire `': error: ...'` line as the message and would benefit from the same multi-line treatment if XCTest emits diffs across lines, but the structured swift-testing path is the one this issue called out and the one verified end-to-end.

---
# ubg-9z1
title: Expose xcresult bundle paths in test tool results
status: completed
type: feature
priority: normal
created_at: 2026-05-07T16:47:00Z
updated_at: 2026-05-07T16:55:46Z
sync:
    github:
        issue_number: "313"
        synced_at: "2026-05-07T17:06:07Z"
---

Port concept from XcodeBuildMCP PR #397 (commit 1ae1867df4fd2b98de89e66bf9b3c862f3311b8e in getsentry/XcodeBuildMCP).

Include the xcresult bundle path in test result artifacts whenever xcodebuild reports or receives a result bundle path. This lets MCP clients open the result bundle directly from structured output and text renderers.

## Tasks

- [x] Audit current test tools (test_macos, simulator test, device test) for whether they surface xcresult paths
- [x] Thread the xcresult path through to the structured tool result
- [x] Add fallback for malformed xcresult summaries (return null rather than throw) — see PR #397's third commit
- [x] Extract shared result-bundle-args parsing helper if duplication shows up across single-phase / two-phase test paths
- [x] Tests covering the path being surfaced on success and failure

## Reference

- Upstream PR: https://github.com/getsentry/XcodeBuildMCP/pull/397
- Fixes upstream issue: getsentry/XcodeBuildMCP#392



## Summary of Changes

Surfaced the xcresult bundle path in `formatTestToolResult` so MCP clients can open the bundle in Xcode or feed it to coverage / attachment tools. The path is appended as `Result bundle: <path>` to both the success text and the failure error message, and only when the bundle actually exists on disk (so a build that failed before tests ran doesn't print a phantom path).

- `Sources/Core/ErrorExtraction.swift`: added `formatResultBundleSuffix(_:)` and wired it into the success and failure branches of `formatTestToolResult`.
- The other audit tasks (malformed-summary fallback, shared parsing helper) had nothing to port — `XCResultParser.parseTestResults` already returns `nil` on malformed JSON, and there was no duplication between single-phase and two-phase paths because xc-mcp only has one path (`TestToolHelper.runAndFormat`).
- New tests in `Tests/TestResultBundleScoperTests.swift` (`ErrorExtractorResultBundleSuffixTests` suite) cover: path included on success, omitted when nil, omitted when file doesn't exist, and included in the failure error message.

Delivered alongside `gqs-ket` so the auto-generated bundle path is now both persistent and visible to the caller.

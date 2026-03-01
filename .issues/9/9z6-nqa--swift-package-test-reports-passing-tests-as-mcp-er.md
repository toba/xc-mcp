---
# 9z6-nqa
title: swift_package_test reports passing tests as MCP error -32603
status: completed
type: bug
priority: normal
created_at: 2026-03-01T21:48:22Z
updated_at: 2026-03-01T21:51:51Z
sync:
    github:
        issue_number: "160"
        synced_at: "2026-03-01T21:51:59Z"
---

## Problem

`mcp__xc-swift__swift_package_test` returns an MCP error (-32603 Internal error) even when all tests pass. The error message contains the success summary, e.g.:

```
MCP error -32603: Internal error: Tests failed: Tests passed (4535 passed)
MCP error -32603: Internal error: Tests failed: Tests passed (4383 passed)
MCP error -32603: Internal error: Tests failed: Tests passed (4387 passed)
```

This was observed 3 times consistently during a single session working on the swiftiomatic project. Every invocation of `swift_package_test` returned this error despite 0 test failures.

## Impact on Agent Workflows

- The agent (Claude Code) must ignore the MCP error status and parse the output text to determine whether tests actually passed
- Creates confusion about whether tests really passed or failed
- May cause agents to retry tests unnecessarily, wasting time and compute
- Undermines trust in tool results — if success is reported as failure, agents cannot rely on the error/success status code

## Root Cause (likely)

The exit-code or output-parsing logic in the Swift runner appears to classify any `swift test` invocation as failed, regardless of the actual test outcome. The summary line "Tests passed (N passed)" is being wrapped in a "Tests failed:" prefix and returned as an MCP error.

This is similar to the previously fixed issue for `test_macos` (ufi-nmg: "Use parsed build output status instead of exit code alone to determine build success") — the same fix pattern likely needs to be applied to the SPM test runner.

## Expected Behavior

When `swift test` exits with code 0 and the output contains "Tests passed", `swift_package_test` should return a successful MCP response (not an error) with the test summary in the result content.

## Summary of Changes

Fixed `formatTestToolResult` in `ErrorExtraction.swift` to override a non-zero exit code when the parsed build output status indicates success. This mirrors the existing pattern in `checkBuildSuccess` which already uses `buildResult.status == "success"` as an exit-code override.

Two code paths were fixed:
1. **SPM test path** (no xcresult): checks `parsed.status == "success"` from `BuildOutputParser`
2. **xcresult path** (xcodebuild tests): checks `failedCount == 0 && passedCount > 0` from xcresult data

Added 2 regression tests in `ErrorExtractorExitCodeOverrideTests`.

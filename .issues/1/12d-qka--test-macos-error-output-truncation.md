---
# 12d-qka
title: test_macos error output truncation
status: completed
type: bug
priority: normal
created_at: 2026-02-18T06:11:55Z
updated_at: 2026-02-18T06:21:59Z
sync:
    github:
        issue_number: "78"
        synced_at: "2026-02-18T06:23:53Z"
---

When tests fail, the error messages returned by test_macos are sometimes cut off mid-sentence, making it hard to see the full failure reason. The tool should return complete error messages from the xcresult bundle.

## Summary of Changes

Added `XCResultParser` to extract complete test failure messages from `.xcresult` bundles via `xcresulttool get test-results tests`. All test tools (test_macos, test_sim, test_device) now automatically create a temporary `.xcresult` bundle and parse it for full error messages, replacing the previous approach of relying solely on xcodebuild text output which could truncate multi-line errors.

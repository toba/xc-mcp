---
# ci5-pje
title: No way to read test stdout from XCUI tests
status: completed
type: bug
priority: normal
created_at: 2026-02-18T06:11:55Z
updated_at: 2026-02-18T06:21:59Z
---

print() statements in XCUI tests go to the test runner process stdout, which isn't captured in the test results returned by test_macos. Would be useful to surface test output logs (or at least provide a way to retrieve them).

## Summary of Changes

`XCResultParser` now walks the xcresult test node tree looking for Attachment nodes with output content. When XCUI test stdout is captured in the xcresult bundle, it surfaces as a "Test output" section in the formatted results. All three test tools (test_macos, test_sim, test_device) now pass the xcresult bundle path through for parsing.

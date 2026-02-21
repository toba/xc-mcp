---
# 8ex-v8c
title: Improve test_macos ergonomics from Thesis session review
status: completed
type: feature
priority: high
created_at: 2026-02-21T23:29:18Z
updated_at: 2026-02-21T23:40:41Z
---

Issues discovered during a Thesis coding session where `test_macos` caused friction:

## TODO

- [x] **Surface compiler errors in test failures**: When `test_macos` fails due to build errors, return the actual compiler diagnostics (e.g. "missing import of defining module 'AppKit'") instead of just "Tests failed: Test run completed". The raw `xcodebuild` output has these — they should be extracted and surfaced.

- [x] **Add `timeout` parameter to `test_macos`**: Full test suites can run long. Without a timeout, the MCP tool blocks indefinitely and gets aborted by the client. A `timeout` parameter (in seconds) would let the caller set a ceiling and get a meaningful timeout error instead of an opaque abort.

- [x] **Add `list_test_targets` tool or extend `list_schemes` with test plan info**: There's no way to discover which test bundles are part of a scheme's test plan. The agent had to guess bundle names (`AppTests`, `DOMTests`, `StorageTests`) and hit "not a member of the specified test plan" errors. Either a dedicated `list_test_targets(scheme:)` tool or enriching `list_schemes` output with testable targets would eliminate this guesswork.

## Context

Session: fixing iOS selection tracking in Thesis. After writing tests and code changes, `test_macos` with no filter ran for ~10 minutes before being aborted. The agent fell back to raw `xcodebuild` via Bash with `| tail -20` and `--timeout 180000` to work around all three issues. The targeted `only_testing` runs worked well but required knowing the bundle names upfront.


## Summary of Changes

1. **`timeout` parameter** added to `test_macos`, `test_sim`, and `test_device` — defaults to 300s, surfaces in `testSchemaProperties` and `TestParameters`, forwarded through `XcodebuildRunner.test()`
2. **Compiler error surfacing** — `formatTestToolResult()` now falls back to `extractTestResults()` when xcresult shows 0 passed / 0 failed and the run failed, ensuring build errors appear
3. **`list_test_plan_targets` tool** — new discovery tool that runs `xcodebuild -showTestPlans` and parses `.xctestplan` files to list test target names usable with `only_testing`; registered in monolithic and build servers

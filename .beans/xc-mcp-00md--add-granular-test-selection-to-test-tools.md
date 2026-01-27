---
# xc-mcp-00md
title: Add granular test selection to test tools
status: completed
type: feature
priority: normal
created_at: 2026-01-21T07:37:59Z
updated_at: 2026-01-27T03:00:46Z
---

Add parameters to test tools for selecting specific tests to run or skip.

## New Parameters for Test Tools

- only_testing: array of strings - test identifiers to run (e.g., "MyTests/testFoo")
- skip_testing: array of strings - test identifiers to skip

## Implementation

### Files to modify:
- Sources/Utilities/XcodebuildRunner.swift - update `test()` to accept `onlyTesting` and `skipTesting`
- Sources/Tools/Simulator/TestSimTool.swift - add new parameters
- Sources/Tools/Device/TestDeviceTool.swift - add new parameters
- Sources/Tools/MacOS/TestMacOSTool.swift - add new parameters

## Verification
- Build: swift build
- Run tests: swift test
- Manual test by running specific tests with only_testing parameter
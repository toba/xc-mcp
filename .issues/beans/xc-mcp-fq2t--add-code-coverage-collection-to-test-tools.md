---
# xc-mcp-fq2t
title: Add code coverage collection to test tools
status: completed
type: feature
priority: normal
created_at: 2026-01-21T07:37:59Z
updated_at: 2026-01-27T03:00:46Z
sync:
    github:
        issue_number: "44"
        synced_at: "2026-02-15T22:08:23Z"
---

Add code coverage support to existing test tools (TestSimTool, TestDeviceTool, TestMacOSTool).

## New Parameters for Test Tools

- enable_code_coverage: boolean - enables code coverage collection
- result_bundle_path: string - path to store .xcresult bundle

## Implementation

### Files to modify:
- Sources/Utilities/XcodebuildRunner.swift - update `test()` to accept `enableCodeCoverage` and `resultBundlePath`
- Sources/Tools/Simulator/TestSimTool.swift - add new parameters
- Sources/Tools/Device/TestDeviceTool.swift - add new parameters
- Sources/Tools/MacOS/TestMacOSTool.swift - add new parameters

## Verification
- Build: swift build
- Run tests: swift test
- Manual test by running tests with enable_code_coverage: true

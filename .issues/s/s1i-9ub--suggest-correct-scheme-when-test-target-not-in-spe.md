---
# s1i-9ub
title: Suggest correct scheme when test target not in specified scheme
status: completed
type: feature
priority: normal
created_at: 2026-02-26T01:56:52Z
updated_at: 2026-02-26T02:22:02Z
sync:
    github:
        issue_number: "145"
        synced_at: "2026-02-26T02:22:31Z"
---

## Context

When `test_macos` (or `test_sim`) is called with a scheme that doesn't include the requested test target, xcodebuild fails with:

> Tests in the target "TestAppUITests" can't be run because "TestAppUITests" isn't a member of the specified test plan or scheme.

The user then has to call `list_schemes`, guess which scheme contains the target, and retry. This is a common stumbling block for agents.

## Proposed Improvement

When a test fails with "isn't a member of the specified test plan or scheme":

1. Parse the target name from the error
2. Run `xcodebuild -list` or equivalent to find which scheme(s) include that target
3. Append a hint to the error message: "Did you mean scheme 'TestApp'? That scheme includes the 'TestAppUITests' target."

## Implementation Notes

- `list_schemes` already exists in Discovery tools — reuse internally
- Could also cross-reference with test plan `.xctestplan` files if present
- The enhancement is in error post-processing (likely `ErrorExtraction.swift` or `BuildResultFormatter.swift`)


## Summary of Changes

Enhanced ErrorExtractor.enhanceTestPlanError() to suggest the correct scheme when a test target is not found in the specified scheme.

### What changed

- Added projectPath and workspacePath parameters to formatTestToolResult() and enhanceTestPlanError()
- Added suggestSchemesForTargets() - scans .xcscheme files to find which schemes contain the missing test target
- Added discoverProjectPaths() - resolves .xcodeproj paths from project or workspace
- Added buildSchemeTestTargetMap() - builds a scheme-name to test-targets mapping
- Added extractTestTargets(fromSchemeAt:) - parses BlueprintName from TestableReference elements
- Updated TestMacOSTool, TestSimTool, and TestDeviceTool to pass project/workspace paths through
- Added 5 tests in SchemeSuggestionTests.swift

### Files modified

- Sources/Core/ErrorExtraction.swift - core logic
- Sources/Tools/MacOS/TestMacOSTool.swift - pass paths
- Sources/Tools/Simulator/TestSimTool.swift - pass paths
- Sources/Tools/Device/TestDeviceTool.swift - pass paths
- Tests/SchemeSuggestionTests.swift - new tests

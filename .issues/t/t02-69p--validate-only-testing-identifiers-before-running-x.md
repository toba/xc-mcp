---
# t02-69p
title: Validate only_testing identifiers before running xcodebuild
status: completed
type: feature
priority: normal
tags:
    - test
created_at: 2026-02-22T22:22:13Z
updated_at: 2026-02-22T22:29:06Z
---

## Problem

When `test_macos` (or `test_sim`) receives an unqualified `only_testing` identifier like `["ZoteroDeletedTests"]` instead of `["ZoteroTests/ZoteroDeletedTests"]`, xcodebuild fails with:

> Tests in the target "ZoteroDeletedTests" can't be run because "ZoteroDeletedTests" isn't a member of the specified test plan or scheme.

This error is passed through verbatim — no hint about the required `Target/TestClass` format, no suggestion of valid targets. In the Thesis session this cost an extra round-trip to grep the test plan file, find the target name, and retry.

The `list_test_plan_targets` tool already exists and can discover valid target names, but it isn't integrated into the test flow.

## Proposed behavior

When `only_testing` identifiers fail validation (xcodebuild returns the "not a member" error):

1. Detect the specific error pattern in the output
2. Run `list_test_plan_targets` logic internally to get valid target names
3. Return an actionable error like: `"ZoteroDeletedTests" is not a valid test identifier. Available test targets: ZoteroTests, CoreTests, DOMTests. Use the format "TargetName/TestClassName" (e.g., "ZoteroTests/ZoteroDeletedTests").`

Alternatively (simpler): pre-validate identifiers before calling xcodebuild by checking them against the test plan targets.

## Files

- `Sources/Core/ErrorExtraction.swift` — add pattern detection for "not a member of the specified test plan"
- `Sources/Tools/MacOS/TestMacOSTool.swift` — integrate validation or enhanced error
- `Sources/Tools/Discovery/ListTestPlanTargetsTool.swift` — reuse discovery logic

## Context

Discovered during a Thesis coding session (de8-sl3). The `list_test_plan_targets` tool was added in 8ex-v8c but isn't surfaced when the error occurs.

## Summary of Changes

Enhanced `ErrorExtractor.formatTestToolResult()` to detect xcodebuild's cryptic "isn't a member of the specified test plan or scheme" error and append actionable guidance including available test targets and the correct identifier format.

### Files changed:
- **Sources/Core/ErrorExtraction.swift** — Added `enhanceTestPlanError(output:projectRoot:)` private method and `projectRoot` parameter to `formatTestToolResult()`
- **Sources/Tools/MacOS/TestMacOSTool.swift** — Passes `projectRoot` derived from project/workspace path
- **Sources/Tools/Simulator/TestSimTool.swift** — Same
- **Sources/Tools/Device/TestDeviceTool.swift** — Same
- **Sources/Tools/SwiftPackage/SwiftPackageTestTool.swift** — Passes package path as `projectRoot`

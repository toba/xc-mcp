---
# 0jo-79v
title: Improve UI test and test plan ergonomics
status: completed
type: feature
priority: normal
created_at: 2026-02-22T02:28:37Z
updated_at: 2026-02-22T02:43:05Z
---

## Context

During a Thesis session fixing a SwiftUI bug (w2c-bd7), the agent needed to run a XCUI test via `test_macos`. Multiple gaps in xc-mcp tooling required manual `.xctestplan` JSON editing and produced an unhelpful error when the UI test target lacked a host application.

## Gaps Identified

### 1. No way to enable/disable test targets in a test plan
The `.xctestplan` JSON has an \`"enabled": false\` flag per test target entry. The existing \`AddTargetToTestPlanTool\` and \`RemoveTargetFromTestPlanTool\` can add/remove targets, but there's no way to toggle the \`enabled\` flag without manually editing the JSON.

**Desired:** A tool (or parameter on existing tools) to enable/disable a test target within a test plan, e.g.:
- \`enable_target_in_test_plan\` / \`disable_target_in_test_plan\`
- Or add an \`enabled\` boolean parameter to \`AddTargetToTestPlanTool\`

### 2. No way to set target application for UI test bundles in scheme
When running \`test_macos\` with a UI test target (\`ViewTests\`), it failed because the scheme's Test action had no target application configured for the UI test bundle. There's no tool to configure this — \`AddTestPlanToSchemeTool\` links plans to schemes but doesn't configure the Test action's target application.

**Desired:** A tool to set the target application (host app) for a UI test target in a scheme's Test action, or at minimum a \`target_application\` parameter on \`test_macos\`/\`test_sim\`.

### 3. Poor error extraction for UI test misconfiguration
When \`test_macos\` fails because a UI test target has no host app, the error output is a ~100-line \`XCTestConfiguration\` internal dump (\`NSInternalInconsistencyException\`). This should be caught and surfaced as a clear message like: "UI test target 'ViewTests' has no target application configured. Set target application in scheme Test action or use the set_test_target_application tool."

### 4. \`list_test_plan_targets\` doesn't show enabled/disabled status
The tool lists target names but doesn't indicate which are enabled vs disabled in the test plan. This information is in the JSON and would save agents from reading the raw file.

## TODO

- [ ] Add enable/disable toggle for test targets in test plans
- [ ] Surface enabled/disabled status in \`list_test_plan_targets\` output
- [ ] Add target application configuration for UI test bundles
- [ ] Improve error extraction for UI test misconfigurations (\`NSInternalInconsistencyException\` → clear message)

## Summary of Changes

- Created `SetTestPlanTargetEnabledTool` to enable/disable test targets in .xctestplan files without removing them
- Created `SetTestTargetApplicationTool` to set the target application (macro expansion) for UI test targets in scheme Test actions
- Updated `ListTestPlanTargetsTool.findTestPlanTargets()` to return enabled/disabled status and show `(disabled)` suffix in output
- Added UI test misconfiguration detection in `ErrorExtraction.formatTestToolResult()` — surfaces actionable guidance when NSInternalInconsistencyException + XCTestConfiguration appears
- Registered both new tools in ServerToolDirectory, ProjectMCPServer, and XcodeMCPServer
- Updated tests with new assertion patterns and added `findTargetsShowsDisabledStatus` test
- All 533 tests pass

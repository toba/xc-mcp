---
# xc-mcp-5kiz
title: Add granular test selection to test tools
status: todo
type: feature
created_at: 2026-01-21T07:36:52Z
updated_at: 2026-01-21T07:36:52Z
---

Add ability to run or skip specific tests in existing test tools (test_sim, test_device, test_macos).

## xcodebuild flags
- `-only-testing:<identifier>` - Run only specified tests
- `-skip-testing:<identifier>` - Skip specified tests

## Test identifier formats
- `MyAppTests` - All tests in target
- `MyAppTests/LoginTests` - All tests in class
- `MyAppTests/LoginTests/testValidLogin` - Specific test method

## Implementation

### XcodebuildRunner changes
Update `test()` method to accept:
- `onlyTesting: [String] = []`
- `skipTesting: [String] = []`

### Test tool changes
Update all three test tools:
- `Sources/Tools/Simulator/TestSimTool.swift`
- `Sources/Tools/Device/TestDeviceTool.swift`
- `Sources/Tools/MacOS/TestMacOSTool.swift`

Add parameters:
- `only_testing`: array of strings (optional)
- `skip_testing`: array of strings (optional)

## Checklist
- [ ] Update XcodebuildRunner.test() for test selection flags
- [ ] Update TestSimTool with new parameters
- [ ] Update TestDeviceTool with new parameters
- [ ] Update TestMacOSTool with new parameters
- [ ] Add tests
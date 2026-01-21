---
# xc-mcp-d33b
title: Add code coverage collection to test tools
status: todo
type: feature
created_at: 2026-01-21T07:36:52Z
updated_at: 2026-01-21T07:36:52Z
---

Add code coverage collection capability to existing test tools (test_sim, test_device, test_macos).

## xcodebuild flags
- `-enableCodeCoverage YES` - Enable coverage collection
- `-resultBundlePath <path>` - Save .xcresult bundle with coverage data

## Implementation

### XcodebuildRunner changes
Update `test()` method signature to accept:
- `enableCodeCoverage: Bool = false`
- `resultBundlePath: String? = nil`

### Test tool changes
Update all three test tools:
- `Sources/Tools/Simulator/TestSimTool.swift`
- `Sources/Tools/Device/TestDeviceTool.swift`
- `Sources/Tools/MacOS/TestMacOSTool.swift`

Add parameters:
- `enable_code_coverage`: boolean (optional, default false)
- `result_bundle_path`: string (optional)

## Checklist
- [ ] Update XcodebuildRunner.test() signature
- [ ] Update TestSimTool with new parameters
- [ ] Update TestDeviceTool with new parameters
- [ ] Update TestMacOSTool with new parameters
- [ ] Add tests
---
# kxu-pmf
title: Add screenshot_mac_window tool
status: in-progress
type: feature
priority: normal
created_at: 2026-02-16T01:20:56Z
updated_at: 2026-02-16T01:26:10Z
---

Add a ScreenCaptureKit-based tool to screenshot macOS app windows, returning inline base64 PNG via MCP.

## Implementation Checklist

- [x] Create `Sources/Tools/MacOS/ScreenshotMacWindowTool.swift` using ScreenCaptureKit
- [x] Register in `Sources/Server/XcodeMCPServer.swift` (enum, instantiation, list, call handler)
- [x] Add `Tests/ScreenshotMacWindowToolTests.swift` (3 tests: schema, params, no-args error)
- [x] Fix API: use `withCheckedThrowingContinuation` for `SCScreenshotManager.captureImage` (completion handler, not auto-bridged async)
- [x] `swift build` passes
- [x] `swift test` passes (318/318)
- [x] `swift format` + `swiftlint` clean
- [ ] Manual verification: run against thesis app with Screen Recording permission

## Notes

- `tccutil reset ScreenCapture` was run during testing, which cleared all Screen Recording permissions
- Permission has been re-granted but terminal session needs reload before it takes effect
- To resume manual testing after reload, run:
  ```bash
  /tmp/test_screenshot.sh
  ```
  This script starts xc-mcp, initializes MCP, and calls `screenshot_mac_window` with `{"app_name":"ThesisApp","save_path":"/tmp/thesis_screenshot.png"}`.
- If the test script is gone, the equivalent manual test is:
  ```bash
  # 1. Make sure thesis app is running:
  open "/Users/jason/Library/Developer/Xcode/DerivedData/Thesis-ddfqsiuxmcpnzhcbomdlbbstfbci/Build/Products/Debug/ThesisApp (debug).app"
  # 2. Run the MCP test harness from test-debug.sh pattern, calling:
  #    tool: screenshot_mac_window
  #    args: {"app_name":"ThesisApp","save_path":"/tmp/thesis_screenshot.png"}
  ```
- Expected result: base64 PNG image inline + text metadata, and file saved to `/tmp/thesis_screenshot.png`

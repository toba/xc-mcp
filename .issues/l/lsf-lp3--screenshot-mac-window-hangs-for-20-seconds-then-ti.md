---
# lsf-lp3
title: screenshot_mac_window hangs for 20+ seconds then times out
status: completed
type: bug
priority: high
created_at: 2026-04-12T16:27:22Z
updated_at: 2026-04-12T16:35:06Z
sync:
    github:
        issue_number: "275"
        synced_at: "2026-04-12T16:44:48Z"
---

## Description

The `screenshot_mac_window` MCP tool hangs for 20+ seconds, requiring user cancellation. This was reproduced 3 times in a row targeting the Swiftiomatic app.

## Diagnostics

The target window exists and is visible:

```
Window: owner=Swiftiomatic id=463 name="Options" layer=0
  bounds=["Y": 404, "Width": 954, "X": 1095, "Height": 1101]
CGWindowList query took 0.032s
```

Native `screencapture` completes in 0.15s for the same window:

```
time screencapture -l 463 /tmp/sm-screenshot-test.png
  0.05s user 0.01s system 45% cpu 0.148 total
```

AppleScript can enumerate windows instantly:

```
osascript -e 'tell application "System Events" to get name of every window of ...'
  0.03s user 0.03s system 13% cpu 0.479 total
```

## Parameters used

- `bundle_id: "app.toba.swiftiomatic"`
- `app_name: "Swiftiomatic"`
- Both variants hung identically

## Environment

- macOS 26.0 (Tahoe)
- Screen Recording permission is granted (native screencapture works fine)


## Summary of Changes

Replaced ScreenCaptureKit with Core Graphics + `screencapture` CLI for window capture:

- **Window enumeration**: `CGWindowListCopyWindowInfo` (~0.03s) replaces `SCShareableContent.excludingDesktopWindows` (20+ seconds)
- **Image capture**: `screencapture -l <windowID>` (~0.15s) replaces `SCScreenshotManager.captureImage`
- Bundle ID matching uses `NSWorkspace.shared.runningApplications` PID→bundle ID lookup
- Removed `ScreenCaptureKit` dependency from the tool entirely

**Files changed:**
- `Sources/Tools/MacOS/ScreenshotMacWindowTool.swift` — rewrote to use CGWindowList + screencapture
- `Tests/ScreenshotMacWindowToolTests.swift` — updated description assertion (no longer mentions ScreenCaptureKit)

**Note:** `PreviewCaptureTool.swift` has the same `SCShareableContent` bottleneck in its `captureMacOSWindow()` method — that should be a separate follow-up issue.

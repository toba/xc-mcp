---
# fo9-1dj
title: PreviewCaptureTool captureMacOSWindow has same SCShareableContent hang
status: completed
type: bug
priority: high
created_at: 2026-04-12T16:35:50Z
updated_at: 2026-04-12T16:41:45Z
sync:
    github:
        issue_number: "274"
        synced_at: "2026-04-12T16:44:48Z"
---

## Description

`PreviewCaptureTool.swift` has the same `SCShareableContent.excludingDesktopWindows()` bottleneck identified in lsf-lp3. Its `captureMacOSWindow()` method hangs for 20+ seconds on macOS 26.

## Fix

Apply the same approach used for `screenshot_mac_window`: replace ScreenCaptureKit with `CGWindowListCopyWindowInfo` + `screencapture -l <windowID>`.

## Tasks

- [x] Replace `SCShareableContent` enumeration with `CGWindowListCopyWindowInfo` in `captureMacOSWindow()`
- [x] Replace `SCScreenshotManager.captureImage` with `screencapture -l <windowID>`
- [x] Remove ScreenCaptureKit import if no longer needed
- [x] Build and run affected tests


## Summary of Changes

Extracted shared `WindowCapture` helper type in `Sources/Core/WindowCapture.swift` with two static methods:
- `findWindow(appName:bundleId:windowTitle:)` — fast CGWindowList enumeration with PID→bundle ID lookup
- `capture(windowID:savePath:)` — `screencapture -l` wrapper with temp file management

Both `ScreenshotMacWindowTool` and `PreviewCaptureTool.captureMacOSWindow()` now delegate to this shared helper, eliminating all ScreenCaptureKit usage.

**Files changed:**
- `Sources/Core/WindowCapture.swift` — new shared helper
- `Sources/Tools/MacOS/ScreenshotMacWindowTool.swift` — simplified to use WindowCapture
- `Sources/Tools/Simulator/PreviewCaptureTool.swift` — replaced 70-line method with 2-line delegation

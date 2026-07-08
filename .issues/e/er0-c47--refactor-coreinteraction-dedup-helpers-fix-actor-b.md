---
# er0-c47
title: 'Refactor Core/Interaction: dedup helpers, fix actor-blocking sleeps, perf'
status: completed
type: task
priority: normal
created_at: 2026-07-08T15:50:04Z
updated_at: 2026-07-08T16:00:06Z
sync:
    github:
        issue_number: "416"
        synced_at: "2026-07-08T16:02:47Z"
---

Swift review of Sources/Core/Interaction/ surfaced: (1a) duplicated+inconsistent appleScriptEscape, (1b) duplicated resolveBootedDevice, (1c) duplicated CGWindowList enumeration, (1d) duplicated focus-window AppleScript, (3) typed throws on SimulatorKeyboardHelper, (4) blocking usleep inside SimulatorUIInput actor, (6) colorAt per-pixel allocation + per-event CGEventSource, (7) acronym naming.

## Summary of Changes

**New shared helpers**
- `AppleScript.swift` — `escape(_:)` (single source of truth; the two prior copies disagreed on whether to escape `\n\r\t`) and `raiseSimulatorWindow(named:)` script builder.
- `WindowList.swift` — typed `WindowEntry` + `onScreen()` wrapper over `CGWindowListCopyWindowInfo`, decoding the `[String: Any]` boundary once.
- `SimctlRunner.findDevice(matching:)` returning `BootedDeviceResolution` (booted/notBooted/notFound) — centralizes the list-and-match logic; callers map outcomes to their own error types.

**Dedup applied**
- `SimulatorKeyboardHelper` and `SimulatorUIInput` now use the shared escape/focus/findDevice helpers; both local `appleScriptEscape` copies and both `resolveBootedDevice` bodies removed.
- `WindowCapture.findWindow` and `SimulatorUIInput.locateWindow` now iterate `WindowList.onScreen()`.

**Concurrency (4)**
- Replaced all 6 blocking `usleep(...)` calls in the `SimulatorUIInput` actor with `try await Task.sleep(for:)` so they suspend instead of tying up a cooperative-pool thread.

**Performance (6)**
- `ScreenRectDetector` reads `NSBitmapImageRep.bitmapData` directly (integer RGB/RGBA fast path, `colorAt` fallback for exotic formats), eliminating a per-sampled-pixel `NSColor` allocation.
- Cached a single `CGEventSource` on the actor instead of creating one per mouse/key event.

**Naming (7)**
- `bundleId`→`bundleID` (WindowCapture), `simulatorId`→`simulatorID` (FocusPolicy), `elementId`→`elementID` (InteractSessionManager) with all call sites and the FocusPolicy test updated. Clears all 13 `uppercaseAcronymsInIdentifiers` lint warnings.

**Dropped**
- (3) Typed `throws(MCPError)` on `SimulatorKeyboardHelper` — verified unsafe: `ProcessResult.run` can throw `CancellationError`, which the MCP cancellation rules require to propagate unchanged; a typed `throws(MCPError)` would force converting it (protocol violation). Left untyped.

**Verification**: `swift build` clean; `FocusPolicyTests` 11/11 pass. No dedicated tests exist for the other touched types (WindowList/SimulatorUIInput/findDevice); full test module compiles.

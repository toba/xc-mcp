---
# 8uj-hm4
title: 'Simulator UIAutomation tools (tap/swipe/touch/button/typeText/keyPress) are broken: ''simctl io <device> <op>'' has no input operations'
status: completed
type: bug
priority: normal
created_at: 2026-06-25T03:55:06Z
updated_at: 2026-06-25T04:34:37Z
sync:
    github:
        issue_number: "396"
        synced_at: "2026-06-25T04:43:32Z"
---

## Symptom
Calling `mcp__xc-simulator__tap` (and siblings) fails with:
```
Failed to tap: Set up a device IO operation.
Usage: simctl io <device> <operation> <arguments>
... Supported operations: enumerate, poll, recordVideo, screenshot, screenConfig
```
The tool passes the coordinates fine, but the underlying invocation is not a real subcommand.

## Root cause
All UIAutomation tools shell out to `xcrun simctl io <device> <verb> ...`, but `simctl io` only supports enumerate / poll / recordVideo / screenshot / screenConfig. There is **no** `tap`, `touch`, `swipe`, `button`, or `keyboard` operation in `simctl` at all — UI input was never a simctl feature. So every one of these tools is a no-op that errors.

Affected (all pass an invalid `io` verb):
- `Sources/Tools/UIAutomation/TapTool.swift:82` — `["io", simulator, "tap", x, y]`
- `Sources/Tools/UIAutomation/LongPressTool.swift:98` — `io ... touch`
- `Sources/Tools/UIAutomation/SwipeTool.swift:130` and `GestureTool.swift:97` — `io ... swipe`
- `Sources/Tools/UIAutomation/ButtonTool.swift:76` and `KeyPressTool.swift:79/83` — `io ... button`
- `Sources/Tools/UIAutomation/TypeTextTool.swift:62` and `KeyPressTool.swift:95` — `io ... keyboard text|key`

## Impact
Agents cannot drive a running Simulator app (tap buttons, type, swipe). Hit while verifying an iOS Settings sheet in the thesis app (c12-yrh): the app ran and the target button was visible in a screenshot, but there was no working way to tap it. `mcp__xc-debug__interact_*` (host AX) does not see into the Simulator (the device's a11y tree is not bridged to the host process — returns 1 element), and `idb` is not installed.

## Fix options
1. **idb** (`idb ui tap|swipe|text|key|button`, fb-idb) — the conventional backend for simulator UI input. Requires `idb_companion`; detect and surface a clear 'install idb' error if absent.
2. **CoreSimulator SimulatorKit** private API (`SimDevice` IndigoHID / `sendPointerEventWithType`) — no external dep but private SPI, version-fragile.
3. **AppleScript/CGEvent on the Simulator window** — map device points to on-screen window coords and synthesize clicks/keys; needs Accessibility permission and window-geometry math (works but brittle across scale/displays).

Recommend (1) idb as primary with a precise 'not installed' diagnostic, optionally (3) as a host-side fallback.

## Repro
Boot a sim, launch any app, call tap with valid coords -> 'Set up a device IO operation' usage dump.

## Summary of Changes

Replaced the non-existent `simctl io <op>` input verbs with a host-side input backend that synthesizes `CGEvent`s on the on-screen Simulator window (the approach chosen over `idb`/private CoreSimulator SPI to avoid an external dependency).

### New: `Sources/Core/SimulatorUIInput.swift`
An actor that drives all simulator UI input:
- **Window + screen detection** — locates the device's Simulator window via `CGWindowList`, captures it with `screencapture -l`, and finds the device-screen rectangle inside it (the window has a title bar and, by default, a device bezel). Detection uses **projection profiles**: a column/row is "screen" if only a small fraction of its pixels in a sampling band are bezel-black. This is robust to scattered dark content (an early single-scanline approach broke on the home-screen wallpaper). The top/bottom pass samples side bands only, dodging the dynamic island and rounded corners. Result is validated against the device aspect ratio (refreshes the cached pixel size on mismatch, e.g. after rotation).
- **Coordinate mapping** — tap/swipe/long-press coordinates are in **device pixels** (the same space as the `screenshot` tool's image), mapped onto global display points for `CGEvent`.
- **Gestures** — tap (down/up), long press (hold), swipe (interpolated drag), gesture presets (fractional swipe).
- **Typing** — the Simulator's hardware keyboard interprets HID keycodes, not Unicode, so each character maps to a US-layout keycode + optional shift. `type_text`/`key_press` idempotently enable *I/O > Keyboard > Connect Hardware Keyboard* so keystrokes route into the focused iOS field. ASCII only (clear error lists unmapped characters).
- **Hardware buttons** — `home`/`lock`/`siri`/`shake`/`screenshot`/`rotate_left`/`rotate_right` driven via the Simulator *Device* menu (AppleScript). `volumeUp`/`volumeDown` are no longer claimed (not available via host automation).

### Rewired tools (no longer shell out to invalid `io` verbs)
`TapTool`, `LongPressTool`, `SwipeTool`, `GestureTool`, `TypeTextTool`, `KeyPressTool`, `ButtonTool` now take a shared `SimulatorUIInput` instead of `SimctlRunner`; descriptions document the device-pixel coordinate space and the on-screen-window requirement. `GestureTool` dropped its now-pointless `screen_width`/`screen_height` params (presets evaluate against a 1×1 box → fractions). Registered the shared `SimulatorUIInput` in both `XcodeMCPServer` and `SimulatorMCPServer`.

### Requirements / limitations
- The Simulator app must be running with the device window visible; needs **Screen Recording** + **Accessibility** permissions on the host process.
- Detection assumes non-(edge-to-edge-black) content; a clear error is returned otherwise.
- Typing is ASCII-only (hardware-keyboard keycodes).

### Verification (end-to-end through the built server, iPhone 17 / iOS 27)
- `tap` → launched Messages from the dock; mapped coordinate landed dead-on.
- `swipe` → swipe-down on home opened Spotlight.
- `type_text` "weather 72" → field showed "weather 72" (letters, space, digits, after the keycode fix that replaced the broken Unicode path which had typed "aaaaaaa").
- `button` home → returned to home screen.
- `long_press` → registered (Maps responded).
`gesture` and `key_press` share the validated swipe/keycode/button mechanisms. Full build + test target compile clean; `sm` formatted.

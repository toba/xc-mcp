---
# elc-se4
title: Add toggle_software_keyboard / toggle_hardware_keyboard simulator tools
status: completed
type: feature
priority: normal
tags:
    - citation
created_at: 2026-04-29T04:41:40Z
updated_at: 2026-04-29T04:58:18Z
sync:
    github:
        issue_number: "293"
        synced_at: "2026-04-29T05:14:18Z"
---

**Inspiration**: getsentry/XcodeBuildMCP `38396fe`, `588e611`, `2c1963f` (keyboard toggle tools).

## Problem

When automating UI on a simulator, the on-screen software keyboard is sometimes hidden (because Simulator > I/O > Keyboard > Connect Hardware Keyboard is enabled), preventing tap-based input on text fields. There is no MCP tool to toggle this state — users currently have to do it manually in the Simulator menu.

## Proposal

Add two simulator tools (or one with a parameter):
- `toggle_software_keyboard` — sends `Cmd+K` to the Simulator app.
- `toggle_connect_hardware_keyboard` — sends `Cmd+Shift+K`.

Implementation pattern (matches upstream):
1. Look up the simulator name from UDID via `simctl list -j`.
2. Focus the matching Simulator window via AppleScript (`tell application "System Events" / process "Simulator" / set frontmost to true`).
3. Send `keystroke "k" using {command down}` (or `{command down, shift down}`).

## Files to add (suggested)

- `Sources/Tools/Simulator/ToggleSoftwareKeyboardTool.swift`
- `Sources/Tools/Simulator/ToggleHardwareKeyboardTool.swift`
- Helper in `Sources/Core/InteractRunner.swift` or a new `SimulatorKeyboardHelper.swift` for AppleScript.

## Out of scope

- Programmatic detection of current keyboard state (the AppleScript approach is just a toggle).


## Summary of Changes

- New `Sources/Core/SimulatorKeyboardHelper.swift`: resolves the booted simulator name from UDID via `SimctlRunner.listDevices()`, focuses its `Simulator.app` window via AppleScript (`AXRaise`), and sends `Cmd+K` or `Cmd+Shift+K` via `osascript`. Pattern matches getsentry/XcodeBuildMCP's `_keyboard_shortcut.ts`.
- New `Sources/Tools/Simulator/ToggleSoftwareKeyboardTool.swift` (`toggle_software_keyboard`).
- New `Sources/Tools/Simulator/ToggleHardwareKeyboardTool.swift` (`toggle_hardware_keyboard`).
- Registered both in `Sources/Servers/Simulator/SimulatorMCPServer.swift`, `Sources/Server/XcodeMCPServer.swift` (monolithic), and `Sources/Core/ServerToolDirectory.swift` (cross-server hint table).

Build passes. Manual testing on a simulator is the natural next step (the AppleScript path can't be unit-tested without a running Simulator) — left for follow-up.

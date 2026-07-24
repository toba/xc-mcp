---
# zfk-h04
title: Make simulator menu automation locale-independent (drive by key equivalent, not English titles)
status: ready
type: bug
priority: normal
tags:
    - citation
created_at: 2026-07-24T04:00:20Z
updated_at: 2026-07-24T04:00:20Z
sync:
    github:
        issue_number: "433"
        synced_at: "2026-07-24T04:01:37Z"
---

Surfaced while evaluating Device Hub adoption (mhc-7p9). XcodeBuildMCP's PR #479 included a follow-up commit "make Device Hub shortcuts locale independent" — the same class of bug exists in our **existing** Simulator.app automation, independent of Device Hub.

## Problem

Sources/Core/Interaction/SimulatorUIInput.swift drives Simulator.app entirely through AppleScript menu navigation using **hardcoded English menu titles**, which silently fail on any non-English macOS system locale:

- `ensureHardwareKeyboardConnected()` (~L442): `menu item "Connect Hardware Keyboard"` of `menu item "Keyboard"` of `menu bar item "I/O"`.
- `clickDeviceMenuItem(_:)` (~L466): `menu item "<x>"` of `menu "Device"`.
- `buttonAliases` table (~L498): "Home", "Lock", "Siri", "Shake", "Trigger Screenshot", "Rotate Left", "Rotate Right" — all English menu titles.

`AppleScript.raiseSimulatorWindow` also uses `tell process "Simulator"` (English process name), though the CGWindowList `ownerName == "Simulator"` filter (SimulatorUIInput.swift:317) is system-provided and locale-independent.

## Task

Make menu-driven simulator input locale-independent:

- [ ] Drive menu items by their **command-key equivalent** (`AXMenuItemCmdChar` / `AXMenuItemCmdModifiers`) or by menu-index position, rather than by localized title. Simulator's Device-menu items and I/O toggles have stable ⌘-shortcuts (e.g. Home ⇧⌘H, Lock ⌘L, Screenshot ⌘S, Rotate ⌘←/⌘→) that are locale-independent.
- [ ] Where a shortcut isn't available, match on a stable AX identifier or menu position instead of the English string.
- [ ] Verify the AppleScript `tell process "Simulator"` still resolves — the process name is the app's executable name (locale-independent), so this is likely fine, but confirm.
- [ ] Add coverage / a note for non-English locale behavior.

## Reference

- XcodeBuildMCP PR #479 (commit 7cd7d5a) and its "locale independent" follow-up.

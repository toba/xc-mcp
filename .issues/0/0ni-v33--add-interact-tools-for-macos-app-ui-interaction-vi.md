---
# 0ni-v33
title: Add interact_ tools for macOS app UI interaction via Accessibility API
status: completed
type: feature
priority: normal
created_at: 2026-02-17T00:32:17Z
updated_at: 2026-02-17T00:39:51Z
sync:
    github:
        issue_number: "60"
        synced_at: "2026-02-17T01:03:31Z"
---

Implement 8 new interact_ tools using macOS Accessibility API (AXUIElement) to drive macOS app UIs.

## Files to Create
- [x] Sources/Core/InteractRunner.swift — Core AX API wrapper
- [x] Sources/Core/InteractSessionManager.swift — Actor caching AXUIElement refs
- [x] Sources/Tools/Interact/InteractUITreeTool.swift
- [x] Sources/Tools/Interact/InteractClickTool.swift
- [x] Sources/Tools/Interact/InteractSetValueTool.swift
- [x] Sources/Tools/Interact/InteractGetValueTool.swift
- [x] Sources/Tools/Interact/InteractMenuTool.swift
- [x] Sources/Tools/Interact/InteractFocusTool.swift
- [x] Sources/Tools/Interact/InteractKeyTool.swift
- [x] Sources/Tools/Interact/InteractFindTool.swift

## Files to Modify
- [x] Sources/Server/XcodeMCPServer.swift — Register 8 new tools

## Verification
- [x] swift build compiles cleanly
- [x] swift test passes (334 tests)

## Summary of Changes

Added 8 new `interact_` tools for macOS app UI interaction via the Accessibility API:

### Core Infrastructure (Sources/Core/)
- **InteractRunner.swift** — Stateless Sendable struct wrapping AXUIElement operations: app resolution, UI tree traversal, attribute reading, action execution, value setting, menu navigation, keyboard events, element search, and key code mapping
- **InteractSessionManager.swift** — Actor caching AXUIElement refs per-PID between tool calls, with SendableAXUIElement wrapper for concurrency safety

### Tools (Sources/Tools/Interact/)
- **interact_ui_tree** — Get UI element tree with assigned IDs, cached for subsequent calls
- **interact_click** — Click element by ID or role+title query
- **interact_set_value** — Set value on text fields, checkboxes, etc.
- **interact_get_value** — Read all attributes of an element
- **interact_menu** — Navigate menu bar by path array
- **interact_focus** — Bring app to front, optionally focus element
- **interact_key** — Send keyboard events with optional modifiers
- **interact_find** — Search elements by role/title/identifier/value with substring matching

### Server Registration
- Added 8 ToolName enum cases and wiring in XcodeMCPServer.swift

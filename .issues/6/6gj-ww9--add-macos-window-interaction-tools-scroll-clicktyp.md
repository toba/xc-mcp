---
# 6gj-ww9
title: 'Add macOS window interaction tools: scroll + click/type into a running app window'
status: completed
type: feature
priority: normal
created_at: 2026-05-27T17:27:15Z
updated_at: 2026-06-03T00:19:18Z
sync:
    github:
        issue_number: "349"
        synced_at: "2026-06-03T01:54:37Z"
---

When visually verifying a running macOS app via xc-debug, there is no way to scroll a window or click/type into it. `screenshot_mac_window` captures a static frame, but to inspect content below the fold or to exercise interactive behavior (e.g. clicking into an embedded editable view and typing) the agent must work around it (relaunching with a narrower target node). No `cliclick`/pyobjc available on the host either.

Requested tools (CGEvent-based, like the simulator tap/swipe/type tools but for a Mac window):
- scroll_mac_window (dx/dy or to-element)
- click_mac_window (at point, or accessibility element)
- type_mac_window (keystrokes / text into the focused window)

Should target a window by app_name/bundle_id/window_title like screenshot_mac_window, and translate to global screen coords. Useful for verifying editor/text-view interaction (e.g. Thesis table cell editing) without a simulator.

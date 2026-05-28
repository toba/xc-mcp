---
# 5hq-47h
title: 'Agents can''t drive TestApp UI: AppleScript GUI-scripting blocked by accessibility permissions; interact_ tools not exposed to MCP client'
status: completed
type: bug
priority: normal
tags:
    - agent-experience
    - macOS
    - dx
created_at: 2026-05-28T16:32:03Z
updated_at: 2026-05-28T16:43:42Z
sync:
    github:
        issue_number: "359"
        synced_at: "2026-05-28T16:44:28Z"
---

## Context

While verifying a UI change in another project, I needed to drive a launched macOS app (TestApp) — click into a control, type, and screenshot the result to confirm a layout updates in real time. The MCP server provides `mcp__xc-debug__screenshot_mac_window` for capture but no exposed tool for **input**.

I fell back to `osascript` / `tell application "System Events"` to send a click + keystrokes. It failed:

```
86:106: execution error: System Events got an error: AppleEvent timed out. (-1712)
```

The screenshot after the script confirmed nothing was clicked or typed — the AppleScript was blocked at the accessibility-permission gate (the agent's shell context isn't in System Settings → Privacy & Security → Accessibility).

## The puzzle

Issue **0ni-v33** ("Add interact_ tools for macOS app UI interaction via Accessibility API") is marked **completed** and ships eight `interact_*` tools (`interact_click`, `interact_set_value`, `interact_key`, `interact_focus`, etc.). Those would have done exactly what I needed.

**But they don't appear in the deferred-tools list surfaced to my MCP client.** I have access to `mcp__xc-build__*`, `mcp__xc-debug__*`, `mcp__xc-project__*`, `mcp__xc-simulator__*`, `mcp__xc-swift__*` — no `mcp__xc-*__interact_*`.

So either (a) the `interact_*` tools were implemented but not registered for export, (b) they're behind a separate MCP server binary I don't have configured, (c) they require a runtime opt-in flag, or (d) they were rolled back.

## What I'd like

In rough order of preference:

1. **Surface the existing `interact_*` tools** to the standard MCP client config so agents can drive macOS app UIs alongside `screenshot_mac_window`. End-to-end visual verification (Task 6 patterns: "type into the app, screenshot, confirm pixels change") becomes feasible without bouncing to the user.
2. **Document the discovery path** — if the tools live in a separate server or require a flag, README or `doctor` should say so explicitly when an agent reaches for them.
3. **Failing both,** document the accessibility-permission setup for the AppleScript fallback so agents at least get a clear "you need to grant X in System Settings" rather than an opaque `AppleEvent timed out (-1712)`.

## Repro

From an agent context (Claude Code in this case):

```bash
osascript -e 'tell application "System Events" to click at {1756, 792}'
# → AppleEvent timed out (-1712)
```

…where the target window belongs to a freshly-launched macOS app under `mcp__xc-debug__build_debug_macos`. Same script run by the human user (with Terminal granted Accessibility) succeeds.

## Why this matters

Without an input path, the verification loop for any UI-affecting change is: **(agent builds + launches) → (human drives the keyboard) → (agent screenshots and assesses)**. The agent can do steps 1 and 3 but has to hand off mid-flow for step 2 even on trivial changes (e.g. "click into this cell and type 100 chars"). The `interact_*` tools were built to close exactly this loop; they just don't seem to be reaching agents.



## Summary of Changes

Root cause: the eight `interact_*` tools (built in 0ni-v33) were only registered on the monolithic `xc-mcp` server. Users running focused servers (`xc-debug`, `xc-build`, etc.) never saw them.

Fix: surfaced the `interact_*` tools through `xc-debug`, alongside `screenshot_mac_window` and the LLDB view tools, since they share the same UI-verification workflow.

- `Sources/Servers/Debug/DebugMCPServer.swift`: added 8 `DebugToolName` cases (`interact_ui_tree`, `interact_click`, `interact_set_value`, `interact_get_value`, `interact_menu`, `interact_focus`, `interact_key`, `interact_find`), constructed an `InteractRunner` + 8 tool instances, registered them in `tools/list`, and dispatched them in `tools/call`.
- `Sources/Core/ServerToolDirectory.swift`: mapped all 8 `interact_*` tools to `xc-debug` so cross-server hints point users to the right binary.
- `README.md`, `CLAUDE.md`: updated xc-debug tool counts and description.

Verification: `swift build` clean; `swift_package_test` for ServerToolDirectory/Debug tests passes (9/9). Tools are now reachable as `mcp__xc-debug__interact_*` in any client that already has the `xc-debug` server configured — no client config change needed.

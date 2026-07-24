---
# mhc-7p9
title: Evaluate Device Hub for simulator UI automation (vs Simulator.app)
status: deferred
type: feature
priority: normal
tags:
    - citation
created_at: 2026-07-24T03:11:20Z
updated_at: 2026-07-24T04:00:39Z
sync:
    github:
        issue_number: "434"
        synced_at: "2026-07-24T04:01:37Z"
---

Follow-up from /cite review of getsentry/XcodeBuildMCP (commit 7cd7d5a, PR #479, "fix(simulator): prefer Device Hub for simulator UI").

## Context

XcodeBuildMCP now prefers **Device Hub** for visible simulator workflows when it is available, falling back to Simulator.app for compatibility. Their implementation:
- Opens Device Hub for visible simulator workflows when available, with Simulator.app as the compatibility fallback.
- Targets the selected simulator by **UDID**.
- Drives keyboard controls through Device Hub's menus (made locale-independent in a follow-up commit).
- Bumped AXe to 1.8.0 as part of the change.

## Task

Evaluate whether xc-mcp's simulator UI automation (Sources/Tools/UIAutomation/, Sources/Tools/Simulator/, Sources/Core/Interaction/) should adopt a Device-Hub-preferred strategy:

- [ ] Investigate Device Hub availability/capabilities and how it's launched + targeted by UDID.
- [ ] Compare against our current Simulator.app-based focus/keyboard/window-capture flow.
- [ ] Decide whether preferring Device Hub (with Simulator.app fallback) improves reliability of our UI automation tools.
- [ ] If adopting, ensure keyboard/menu shortcuts are locale-independent.

## Reference

- Commit: https://github.com/getsentry/XcodeBuildMCP/commit/7cd7d5af4e8e5d502f9408a96a42b6ada9e06f78

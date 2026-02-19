---
# 280-k3o
title: Migrate manual argument extraction to ArgumentExtraction helpers
status: completed
type: task
priority: high
created_at: 2026-02-19T20:12:55Z
updated_at: 2026-02-19T20:36:15Z
sync:
    github:
        issue_number: "89"
        synced_at: "2026-02-19T20:42:41Z"
---

50+ tools use manual if case let .string(value) = arguments[key] instead of existing helpers from ArgumentExtraction.swift (getString, getBool, getInt). Notable: all 4 Logging tools, LaunchMacAppTool, StopMacAppTool, OpenSimTool.

- [ ] Audit all tools for manual argument extraction patterns
- [ ] Replace with arguments.getString(), .getBool(), .getInt()
- [ ] Verify tests pass

---
# qcw-bzr
title: 'Feature batch: Doctor, Gesture Presets, Xcode State, Next Steps, Workflows'
status: completed
type: feature
priority: normal
created_at: 2026-02-19T19:41:09Z
updated_at: 2026-02-19T19:53:46Z
sync:
    github:
        issue_number: "81"
        synced_at: "2026-02-19T20:04:43Z"
---

Implement 5 features for agent ergonomics and diagnostics:

- [x] 1. Enhanced Doctor Tool — add session state, LLDB, SDKs, DerivedData checks
- [x] 2. Gesture Presets — new tool with named gesture presets  
- [x] 3. Xcode IDE State Reader — sync scheme/simulator from Xcode state
- [x] 4. Next Step Hints — append suggested next tools to ~15 tool responses
- [x] 5. Tool Workflows — enable/disable tool categories dynamically



## Summary of Changes

Implemented all 5 features:
1. **Enhanced Doctor Tool** — Added session state, LLDB version, active debug sessions, SDKs, DerivedData disk usage checks
2. **Gesture Presets** — New `gesture` tool with 8 presets (scroll, swipe from edge, pull to refresh, dismiss)
3. **Xcode IDE State Reader** — New `sync_xcode_defaults` tool reads scheme/simulator from xcuserstate
4. **Next Step Hints** — Added suggested next steps to 15 tools (build, launch, screenshot, tap, gesture, debug, etc.)
5. **Tool Workflows** — New `manage_workflows` tool to enable/disable tool categories, with `listChanged` capability and notification support

New files: GestureTool.swift, XcodeStateReader.swift, SyncXcodeDefaultsTool.swift, NextStepHints.swift, WorkflowManager.swift, ManageWorkflowsTool.swift
Modified: DoctorTool.swift, XcodeMCPServer.swift, BuildMCPServer.swift, and 12 tool files for hints

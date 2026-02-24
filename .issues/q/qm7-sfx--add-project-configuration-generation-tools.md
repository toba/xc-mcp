---
# qm7-sfx
title: Add project configuration generation tools
status: completed
type: feature
priority: normal
tags:
    - agent-experience
created_at: 2026-02-22T01:09:52Z
updated_at: 2026-02-22T01:32:10Z
sync:
    github:
        issue_number: "102"
        synced_at: "2026-02-24T18:57:43Z"
---

During an iOS test setup session for the thesis project, several tasks required manually generating Xcode project configuration files that the MCP server could provide as tools instead.

## Checklist

- [x] **`create_test_plan`** — Generate `.xctestplan` JSON files given target names, skipped tags, skipped tests, and options. Currently agents must hand-write the JSON structure
- [x] **`create_scheme`** — Generate `.xcscheme` XML files given a build target, test plan references, and destination. Currently agents must hand-write the XML, duplicating boilerplate like pre-actions, build configurations, and launcher identifiers
- [x] **`add_test_plan_to_scheme`** — Add a test plan reference to an existing scheme's TestAction (avoids XML manipulation)
- [x] **`list_simulators`** (already covered by `list_sims`) — List available simulators with UDID, device name, OS version, and boot state. Currently agents must shell out to \`xcrun simctl list devices\`
- [x] **`add_target_to_test_plan`** — Add a test target entry to an existing test plan (avoids JSON manipulation)
- [x] **`remove_target_from_test_plan`** — Remove a test target entry from a test plan
- [x] **`list_test_plans`** — List all .xctestplan files in the project directory with their target lists
- [x] **`validate_scheme`** — Verify a scheme's build target references, test plan references, and simulator destinations are valid

## Context

The agent had to:
1. Read an existing `.xctestplan` to understand the JSON structure, then hand-write a new one
2. Read an existing `.xcscheme` to understand the XML structure, then hand-write a new one with the GRDB pre-action script
3. Shell out to `xcrun simctl list devices` to find simulator UDIDs
4. Manually look up Xcode target identifiers from existing test plans

All of these are mechanical operations that the xc-project or xc-build MCP server should handle.


## Summary of Changes

Added 7 new project configuration generation tools and 2 shared utilities:

### Core utilities
- `TestPlanFile` — read/write/find `.xctestplan` JSON files
- `SchemePathResolver` — find scheme files in shared/user directories (refactored from RenameSchemeTool)

### New tools
1. `create_test_plan` — generate `.xctestplan` JSON from project target info
2. `create_scheme` — generate `.xcscheme` with build/test/launch actions, pre-actions, and test plan refs
3. `add_test_plan_to_scheme` — add test plan reference to existing scheme
4. `add_target_to_test_plan` — add test target to existing test plan
5. `remove_target_from_test_plan` — remove test target from test plan
6. `list_test_plans` — find and list all `.xctestplan` files under project directory
7. `validate_scheme` — verify scheme target refs, test plans, and build configs exist

All 7 tools registered in both `XcodeMCPServer` (monolithic) and `ProjectMCPServer` (focused). `RenameSchemeTool` refactored to use `SchemePathResolver`. 528 tests pass.

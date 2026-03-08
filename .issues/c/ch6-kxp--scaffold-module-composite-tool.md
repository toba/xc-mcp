---
# ch6-kxp
title: scaffold_module composite tool
status: completed
type: task
priority: normal
created_at: 2026-03-07T18:56:52Z
updated_at: 2026-03-08T22:13:09Z
parent: xav-ojz
blocked_by:
    - t1b-w5r
    - rpc-de1
    - m87-5oa
    - orp-ndc
    - qdd-n43
sync:
    github:
        issue_number: "177"
        synced_at: "2026-03-08T22:14:16Z"
---

A single tool that creates a framework module with test target, fully wired. Replaces ~30 individual tool calls.

## Parameters
- `name` (required): Module name
- `parent_group` (optional): Group to nest under
- `template_target` (optional): Clone settings from existing target
- `with_tests` (bool, default true): Create test target
- `link_to` (optional): Targets to link framework into
- `embed_in` (optional): Targets to embed into with CodeSignOnCopy
- `test_plan` (optional): Test plan path to add test target to
- `source_path` (optional): Source folder path
- `test_path` (optional): Test folder path

## Creates
- Framework target with all project build configs
- Test target (if with_tests)
- Group under parent
- Synchronized folders for Sources/Tests
- Dependencies, framework links, embed phases
- Test plan entry

## Tasks
- [x] Implement ScaffoldModuleTool
- [x] Register in project server tool list
- [x] Add integration test

Blocked by all five gap fixes.


## Summary of Changes

Implemented `scaffold_module` composite tool that creates a framework module with optional test target in a single call. Replaces ~30 individual MCP tool calls.

### Files created
- `Sources/Tools/Project/ScaffoldModuleTool.swift` — the tool implementation (~400 lines)
- `Tests/ScaffoldModuleToolTests.swift` — 12 tests covering all parameters

### Files modified
- `Sources/Servers/Project/ProjectMCPServer.swift` — registered tool
- `Sources/Server/XcodeMCPServer.swift` — registered in monolithic server
- `Sources/Core/ServerToolDirectory.swift` — added to project tools directory

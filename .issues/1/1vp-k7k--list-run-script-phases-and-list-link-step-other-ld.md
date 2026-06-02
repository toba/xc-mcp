---
# 1vp-k7k
title: list_run_script_phases and list_link_step / Other LDFLAGS aggregator
status: completed
type: feature
priority: normal
created_at: 2026-06-02T22:08:31Z
updated_at: 2026-06-02T22:15:49Z
sync:
    github:
        issue_number: "379"
        synced_at: "2026-06-02T22:16:13Z"
---

For thesis-xsh0 diagnosis I needed to see whether any target had -merge_framework explicitly in OTHER_LDFLAGS — currently no xc-mcp tool surfaces that. Had to grep project.pbxproj manually.

Proposed tools:
- mcp__xc-project__list_other_ldflags(project_path, target_name?, filter?) — return resolved OTHER_LDFLAGS per target/config (xcconfig inheritance flattened)
- mcp__xc-project__find_link_flag(project_path, flag, configuration?) — given a substring (e.g. '-merge_framework'), return list of (target, config, full flag value) where it appears
- mcp__xc-project__list_run_script_phases(project_path, target_name?, filter_script?) — script phases per target (useful for finding GRDB pre-actions, Swiftiomatic, etc.)


## Summary of Changes

Added `find_link_flag` and `list_run_script_phases` to xc-project and xc-mcp.

- `find_link_flag(project_path, flag, configuration?)` — substring search across every target's OTHER_LDFLAGS, reports each (target, config, matching element) hit. Use for `-merge_framework`, `-no_warn_duplicate_libraries`, `-rpath`, etc.
- `list_run_script_phases(project_path, target_name?, filter_script?)` — lists every PBXShellScriptBuildPhase across targets with name, position, shellPath, inputs/outputs, inputFileLists/outputFileLists, runOnlyForDeploymentPostprocessing, alwaysOutOfDate, dependencyFile, and the full shellScript body. Optional filter to a single target or by a substring of the shellScript body.
- The companion `list_other_ldflags` is covered by the generic `find_build_settings` (q4u-ocl) with `settings=["OTHER_LDFLAGS"]`.

Files:
- Sources/Tools/Project/FindLinkFlagTool.swift (new)
- Sources/Tools/Project/ListRunScriptPhasesTool.swift (new)
- Sources/Servers/Project/ProjectMCPServer.swift (register)
- Sources/Server/XcodeMCPServer.swift (register)

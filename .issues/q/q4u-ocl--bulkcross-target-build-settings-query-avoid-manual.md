---
# q4u-ocl
title: Bulk/cross-target build settings query (avoid manual pbxproj parsing)
status: completed
type: feature
priority: normal
created_at: 2026-06-02T22:08:31Z
updated_at: 2026-06-02T22:15:49Z
sync:
    github:
        issue_number: "378"
        synced_at: "2026-06-02T22:16:13Z"
---

Working on Thesis thesis-xsh0 archive failures. Needed to find every target whose MERGEABLE_LIBRARY=YES and every target with MERGED_BINARY_TYPE set, across ~55 targets in one project. Current xc-mcp tools force either:

- per-target loop with get_build_settings or show_build_settings (~55 round-trips, slow + chatty)
- manual Python pbxproj parsing (what I ended up doing)

Both are brittle vs. just having a query tool.

Proposed:
- mcp__xc-project__find_build_settings(project_path, settings: [str], values?: [str], configuration?: str) — returns {target: {setting: value}} for every target+config matching. Settings list is required; values list is optional filter.
- Or: mcp__xc-project__list_targets_with_setting(project_path, setting, value?, configuration?) — convenience form
- Should walk the in-memory PIF/pbxproj graph so it's a single roundtrip, not 55

Use cases this unlocks beyond xsh0:
- audit MERGEABLE_LIBRARY / MERGED_BINARY_TYPE consistency across an app + N frameworks
- find every target whose SDKROOT differs from the scheme's
- list targets with a particular SWIFT upcoming feature flag enabled
- find SUPPORTED_PLATFORMS deviations
- audit DEVELOPMENT_TEAM / PRODUCT_BUNDLE_IDENTIFIER

Workaround until then: ad-hoc Python scripts in the consuming repo. Already wrote one for this debugging session.


## Summary of Changes

Added `find_build_settings` to xc-project and xc-mcp. Walks every native target in a single pbxproj load, returns each (target, configuration, setting) pair matching the requested setting names. Optional `values` substring filter and `configuration` scope. Reads pbxproj target-level values only (does not flatten xcconfig inheritance — `show_build_settings` remains for fully resolved settings).

Files:
- Sources/Tools/Project/FindBuildSettingsTool.swift (new)
- Sources/Servers/Project/ProjectMCPServer.swift (register)
- Sources/Server/XcodeMCPServer.swift (register)

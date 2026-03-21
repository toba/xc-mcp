---
# ra3-56u
title: Add tool to set/remove test plan tag exclusions
status: completed
type: feature
priority: high
created_at: 2026-03-21T00:28:55Z
updated_at: 2026-03-21T00:42:29Z
sync:
    github:
        issue_number: "225"
        synced_at: "2026-03-21T00:52:20Z"
---

## Problem

There is no MCP tool to manage test plan tag exclusions (`skippedTags`). Agents cannot correctly add `.api`, `.testSuiteFile`, or other tag exclusions to test plans. Repeated attempts to manually edit the JSON failed because the correct format was unknown.

## Correct Format

Per-target `skippedTags` (as written by Xcode 26):
```json
{
  "skippedTags" : {
    "tags" : [
      ".api",
      ".testSuiteFile"
    ]
  },
  "target" : { ... }
}
```

Note: no `"mode"` key at the per-target level. Xcode omits it.

Plan-level `skippedTags` (in `defaultOptions`):
```json
"skippedTags" : {
  "mode" : "or",
  "tags" : [
    ".api",
    ".testSuiteFile"
  ]
}
```

## Requested Tools

- `set_test_plan_skipped_tags` — add tag exclusions to a test plan (plan-level or per-target)
- `remove_test_plan_skipped_tags` — remove tag exclusions
- Any tool that modifies a test plan (e.g. `add_target_to_test_plan`) should preserve existing `skippedTags` on all targets


## Summary of Changes

Added `set_test_plan_skipped_tags` tool to both xc-project and xc-mcp servers.

### Tool: `set_test_plan_skipped_tags`
- **Parameters**: `test_plan_path` (required), `tags` (required array), `action` (add/remove, default add), `target_name` (optional)
- **Plan-level**: Modifies `defaultOptions.skippedTags` with `mode: "or"`
- **Per-target**: Modifies target entry's `skippedTags` without `mode` key (matches Xcode 26 format)
- Duplicate adds are idempotent; removing all tags cleans up the `skippedTags` key entirely

### Files changed
- `Sources/Tools/Project/SetTestPlanSkippedTagsTool.swift` (new)
- `Sources/Servers/Project/ProjectMCPServer.swift` (registration)
- `Sources/Server/XcodeMCPServer.swift` (registration)
- `Tests/SetTestPlanSkippedTagsToolTests.swift` (new, 8 tests)

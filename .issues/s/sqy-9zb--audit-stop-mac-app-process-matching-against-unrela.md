---
# sqy-9zb
title: Audit stop_mac_app process matching against unrelated-process termination
status: completed
type: bug
priority: high
tags:
    - citation
created_at: 2026-07-24T03:11:09Z
updated_at: 2026-07-24T03:56:20Z
sync:
    github:
        issue_number: "432"
        synced_at: "2026-07-24T04:01:37Z"
---

Follow-up from /cite review of getsentry/XcodeBuildMCP (commit a7d367f, PR #484, "fix(macos): prevent stop_mac_app from terminating unrelated processes", fixes their #306).

## Context

XcodeBuildMCP hardened their `stop_mac_app` after discovering it could terminate unrelated processes. Their fix:
- Stop apps by **exact executable name** instead of matching the app name against every process argument.
- Switched from full-command regex matching to `killall` (by process name) so later arguments cannot accidentally select unrelated processes.
- Reject empty app names and unsafe/invalid process IDs **before** constructing or invoking `kill`, even when callers bypass the typed-tool schema (validation at the execution boundary, not just the schema layer).

## Task

Audit our `stop_mac_app` tool (Sources/Tools/MacOS/ and any macOS process-termination helper in Sources/Core/Runners/) for the same footgun:

- [ ] Determine how we currently select the process(es) to kill — do we match against the full command line / arguments, or by exact executable/process name?
- [ ] Confirm we cannot select unrelated processes when the app name appears as a substring or as an argument of another process.
- [ ] Validate app name (reject empty) and PID (reject unsafe/invalid) at the execution boundary, not only in the tool schema.
- [ ] Add regression tests covering: substring-in-arguments false match, empty app name, invalid PID, and long app names.

## Reference

- Commit: https://github.com/getsentry/XcodeBuildMCP/commit/a7d367fae1c1fc75f778b5b43753e8c706b28902
- Files changed upstream: src/mcp/tools/macos/stop_mac_app.ts (+ tests)

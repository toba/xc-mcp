---
# x62-nw2
title: Review XcodeBuildMCP v2.3.0 changes for applicability
status: completed
type: task
priority: normal
created_at: 2026-03-17T18:15:50Z
updated_at: 2026-03-17T20:02:53Z
sync:
    github:
        issue_number: "220"
        synced_at: "2026-03-17T20:06:39Z"
---

From citation review of getsentry/XcodeBuildMCP (17 commits, 2026-03-14 → 2026-03-16).

- [ ] **Process exit after SIGTERM** (`c4ece28a`): Confirmed — `SwiftPackageStopTool` uses `pkill` fire-and-forget (no wait for exit). Also affects `LogCapture.stopCapture` and `LLDBRunner.terminate()`. Needs fix.
- [x] **CLI flags for list-schemes** (`f103eb56`): No gap — our `ListSchemesTool` already accepts `project_path` and `workspace_path` as optional parameters with session-default fallback.
- [x] **Simulator metadata config churn** (`3881d051`): Not applicable — our `SimctlRunner` is stateless with fully deferred `simctl` calls (no eager startup fetches, no caching). No churn to fix.
- [ ] **MCP SDK upgrade** (`95cb5217`): v0.11.0 available (we're on 0.10.2). Adds 2025-11-25 spec, conformance tests, icons/metadata, elicitation, HTTP transport. Needs testing.


## Summary of Changes

Investigated all four items from the XcodeBuildMCP v2.3.0 citation review:

- **Process exit after SIGTERM**: Confirmed fire-and-forget in `SwiftPackageStopTool`, `LogCapture.stopCapture`, and `LLDBRunner.terminate()`. Created follow-up issue.
- **CLI flags for list-schemes**: No gap — already supported.
- **Simulator metadata config churn**: Not applicable — our design is already lazy/deferred.
- **MCP SDK upgrade**: 0.11.0 available with spec updates. Created follow-up issue.

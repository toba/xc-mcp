---
# 9ia-hyq
title: 'Port XcodeBuildMCP next-step runtime responses (PR #420)'
status: completed
type: feature
priority: normal
created_at: 2026-05-21T16:01:14Z
updated_at: 2026-05-21T16:25:25Z
sync:
    github:
        issue_number: "325"
        synced_at: "2026-05-21T16:26:57Z"
---

Upstream PR getsentry/XcodeBuildMCP#420 (commit f68db5f6) adds next-step runtime responses across debug tools (debug_attach_sim, debug_breakpoint_add/remove, debug_continue, debug_detach, debug_lldb_command, debug_stack) and coverage tools (get_coverage_report, get_file_coverage).

Evaluate against our `Sources/Core/NextStepHints.swift` and the corresponding xc-debug / xc-build tools to see which hint patterns are worth porting.

## Tasks
- [ ] Read PR #420 diff in getsentry/XcodeBuildMCP
- [ ] Map upstream tool names → our xc-debug/xc-build tool names
- [ ] Identify hint patterns not already covered by `NextStepHints`
- [ ] Port applicable hints
- [ ] Add tests



## Summary of Changes

Ported the high-leverage portion of getsentry/XcodeBuildMCP PR #420 — added a shared `NextStepHints` helper in `Sources/Core/NextStepHints.swift` that renders a sorted `Next steps:` block of suggested follow-up tool calls in MCP's `tool({ key: "value", ... })` syntax. Uses `JSONEncoder` with `.withoutEscapingSlashes` so file paths render cleanly.

Wired hints into 3 tools (the only 3 with concrete upstream hints):
- `DebugAttachSimTool` → suggests `debug_breakpoint_add`, `debug_continue`, `debug_stack` keyed by the resolved `pid` (our debug tools key off pid, not session id).
- `GetCoverageReportTool` → suggests `get_file_coverage` targeting the weakest-covered file.
- `GetFileCoverageTool` → suggests `get_coverage_report`.

Param names use our snake_case schema (e.g. `result_bundle_path`, `pid`), not upstream's camelCase.

Tests: 6 new `NextStepHintsTests` covering priority sort, JSON-escaped params, slash-preservation, quote escaping, and empty/append behavior.

Skipped: upstream's CLI rendering path and manifest/runtime envelope — we have no CLI surface and our tools assemble responses directly, so a runtime envelope would be over-engineered for the 3 sites that need it.

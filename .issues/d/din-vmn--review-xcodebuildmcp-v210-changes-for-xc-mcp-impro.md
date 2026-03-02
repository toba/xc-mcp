---
# din-vmn
title: Review XcodeBuildMCP v2.1.0 changes for xc-mcp improvements
status: completed
type: task
priority: normal
created_at: 2026-03-02T18:52:50Z
updated_at: 2026-03-02T19:06:01Z
sync:
    github:
        issue_number: "164"
        synced_at: "2026-03-02T19:11:15Z"
---

XcodeBuildMCP released v2.1.0 with 30 commits. Several changes are worth reviewing for ideas/parity.

- [x] Check if our SwiftRunner has the same stdout-fallback gap they fixed (5c091c6) — include stdout diagnostics when stderr is empty on SPM failure
  - `ProcessResult.output` already combines stdout+stderr correctly
  - Minor gap: `SwiftPackageTestTool` does not pass `stderr` to `formatTestToolResult()`, so infrastructure warnings are never reported for SPM tests — but this is a minor edge case, not worth a code change
- [x] Compare session defaults hardening approach (fc5a184) — schema validation and clear semantics
  - Already evaluated in issue 95q-yzq — no code changes needed
  - Our Swift actor-based SessionManager handles concurrency issues natively
  - Configuration enum validation, env deep-merge, mutual exclusivity all present
  - Missing validations (path existence, UDID format) are low-value — downstream tools fail clearly
- [x] Review destructive hint narrowing (8037e14, f7b07ab) — relevant if we adopt MCP tool annotations for destructive vs read-only classification
  - We currently use zero MCP annotations on any tool
  - SDK supports readOnlyHint, destructiveHint, idempotentHint
  - Adding these would be nice but purely additive — track as separate feature if desired
- [x] Review their AGENTS.md / agent workflow guidance (46906c3, a815832) — see if there are ideas worth adopting for our skill or CLAUDE.md
  - Our `.claude/skills/xcode/SKILL.md` already has excellent routing guidance (decision matrix, server table)
  - It is not referenced from CLAUDE.md — could improve discoverability by adding a pointer
  - No need for a separate AGENTS.md since we use CLAUDE.md + skills
- [x] Note: they updated default simulator from iPhone 16 to iPhone 17 (13eeb84) — check if we have hardcoded simulator references
  - Not an issue — we dynamically select available simulators at runtime
  - Only "iPhone 15 Pro" refs are in docstrings and GestureTool default screen dimensions (393x852)


## Summary of Changes

No code changes needed. All five items reviewed:
1. SwiftRunner stdout gap is minor (SPM tools already use combined output)
2. Session defaults hardening already evaluated in 95q-yzq — architecture differences make TypeScript fixes irrelevant
3. MCP annotations not used — potential future feature, not a gap
4. Agent guidance already strong via xcode skill — could add CLAUDE.md pointer
5. No hardcoded simulator defaults to update

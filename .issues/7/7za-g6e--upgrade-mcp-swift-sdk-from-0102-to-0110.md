---
# 7za-g6e
title: Upgrade MCP Swift SDK from 0.10.2 to 0.11.0
status: completed
type: task
priority: normal
created_at: 2026-03-17T18:26:30Z
updated_at: 2026-03-17T20:02:53Z
blocked_by:
    - x62-nw2
sync:
    github:
        issue_number: "219"
        synced_at: "2026-03-17T20:06:38Z"
---

MCP Swift SDK 0.11.0 (2026-02-19) is available. We're on 0.10.2.

## New in 0.11.0
- 2025-11-25 MCP spec coverage
- Conformance tests (SEP-1730)
- Icons and metadata support (SEP-973)
- Elicitation updates (SEP-1034, SEP-1036, SEP-1330)
- HTTP server transport
- Network transport fixes

## Steps
- [ ] Update Package.swift \`from: "0.11.0"\`
- [ ] \`swift package resolve\` and fix any API breakage
- [ ] Run full test suite
- [ ] Evaluate whether icons/metadata or elicitation features are worth adopting


## Summary of Changes

Updated Package.swift from `from: "0.9.0"` to `from: "0.11.0"`. Resolved to 0.11.0.

**No API breakage** — clean build, 155+ tests pass.

### New transitive dependencies
- swift-nio 2.96.0
- swift-async-algorithms 1.1.3
- swift-collections 1.4.0
- swift-atomics 1.3.0

These come from the HTTP server transport added in 0.11.0. We don't use HTTP transport (stdio only), but the deps are pulled in regardless.

### Features worth evaluating later
- Icons/metadata support (SEP-973) — could add tool icons
- Elicitation (SEP-1034) — interactive prompts from server to client

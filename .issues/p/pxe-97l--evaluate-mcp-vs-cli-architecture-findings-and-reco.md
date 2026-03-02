---
# pxe-97l
title: Evaluate MCP vs CLI architecture — findings and recommendations
status: completed
type: task
priority: normal
created_at: 2026-03-02T18:31:58Z
updated_at: 2026-03-02T18:31:58Z
sync:
    github:
        issue_number: "161"
        synced_at: "2026-03-02T18:46:51Z"
---

## Context

Evaluated whether xc-mcp should be converted from MCP servers to a CLI with subcommands (invoked via Bash tool), with an agent skill.md indexing available tools. Motivation: potential token efficiency gains and greater output flexibility (jq/GraphQL-style querying).

## Token Cost Analysis

### Current MCP approach
- Each tool definition: ~160-220 tokens in system prompt (name + description + JSON schema)
- **xc-build** (21 tools): ~3,500 tokens
- **xc-debug** (22 tools): ~3,700 tokens
- **Monolithic** (145+ tools): ~25,000 tokens
- Per-invocation: ~50-100 tokens (tool name + JSON arguments)

### Hypothetical CLI approach
- A SKILL.md describing all subcommands: ~500-1,500 tokens (compact reference)
- Per-invocation: ~30-80 tokens (bash command string)
- The Bash tool definition itself is ~800 tokens and always present

### Real savings
- Replacing an MCP focused server with CLI + skill.md: **~2,000-3,000 tokens saved** per conversation
- Modest — context windows are 200K, tool definitions are a small fraction of total usage in long sessions

## Output Flexibility

### What MCP gives you
- **Structured content types**: \`.text()\`, \`.image(data:mimeType:)\`, \`.blob()\` — screenshot tool returns inline base64 PNG images Claude sees directly
- **Typed error handling**: \`isError: true\`, \`MCPError\` types clients understand
- **Session state**: Actor-based \`SessionManager\` persists defaults (project, scheme, simulator) across calls without agent tracking

### What a CLI would give you
- **Flexible output formats**: \`--json\`, \`--text\`, \`--quiet\` flags per command
- **Pipe-friendly**: agent could filter output with jq
- **File-based returns**: screenshots saved to disk, agent reads via Read tool (extra round-trip)

### Where CLI loses

1. **Images**: MCP returns inline base64 images Claude sees immediately. CLI must save to file + agent uses Read tool — extra round-trip per screenshot. Real regression for debug/screenshot workflow.
2. **Session state**: SessionManager actor holds defaults across calls. CLI needs session file (complexity, cleanup), per-invocation context passing (verbose, error-prone), or a long-running daemon (back to being a server).
3. **Error semantics**: MCP has typed errors (invalidParams, methodNotFound, internalError). CLI errors are non-zero exit codes + stderr text the agent must parse.
4. **Discovery**: MCP ListTools lets clients dynamically discover capabilities. CLI relies on agent having read skill.md.

### Where CLI could win

1. **Queryable output**: \`--json\` on build-settings, list-targets, view-hierarchy lets agents filter. But MCP tools can also return JSON — nothing prevents \`CallTool.Result(content: [.text(jsonString)])\`.
2. **Composability**: \`xc build settings --json --filter PRODUCT_NAME\` is natural. But MCP tool calls are model-generated, not human-typed — marginal difference.
3. **No server process**: stateless, no lifecycle. But MCP stdio is already simple — Claude Code manages it.

## The jq/GraphQL Angle

- **Within MCP**: Add \`query\` or \`fields\` parameters to tools returning structured data. \`show_build_settings\` already has a \`filter\` param — extend to JSONPath or field selection.
- **As a CLI**: GraphQL over CLI reinvents MCP — a long-running process accepting structured queries returning structured results.
- **Hybrid**: Keep MCP for protocol, add \`--fields\`/\`--format json\` to underlying implementations.

## Decision: Keep MCP

The conversion is **not worth doing**:

1. Token savings are modest (~2-3K per focused server) and don't justify losing inline images, session state, and typed errors
2. The real token problem is already solved — focused servers reduce 25K monolithic to 3-4K per domain
3. Images are a dealbreaker — screenshot/preview capture tools return inline images; CLI adds extra round-trip for every visual operation
4. Session state would regress — SessionManager actor is elegant; CLI equivalent adds filesystem state management
5. Output flexibility gap can be closed within MCP — tools can return JSON, add filter/fields params

## Actionable Follow-ups

Consider these improvements within the existing MCP architecture:

- [ ] Add \`format: "json"\` output mode to tools returning structured data (build settings, list schemes, list targets, view hierarchy)
- [ ] Add \`fields\` parameter to verbose tools (e.g., show_build_settings with specific field selection instead of 200+ settings)
- [ ] Audit tool descriptions for verbosity — shorter descriptions = fewer tokens per definition
- [ ] Evaluate tool usage patterns — if tools are rarely called, consider removing from focused servers or making opt-in

## Summary of Changes

Architecture evaluation completed. Decision: keep MCP, pursue incremental improvements to output flexibility within the existing framework.

---
# xc-mcp-2t9b
title: Add --no-sandbox flag to xc-project, xc-build, and xc-strings servers
status: completed
type: feature
priority: normal
created_at: 2026-01-22T05:24:30Z
updated_at: 2026-01-22T05:27:23Z
---

Add a --no-sandbox flag to disable path validation, allowing these MCP servers to access paths outside their base directory. This fixes issues when Claude Code spawns the server without specifying a working directory.
---
# xc-mcp-mp0a
title: Improve MCP tool timeout handling with streaming progress
status: completed
type: feature
priority: normal
created_at: 2026-01-22T06:12:39Z
updated_at: 2026-01-22T06:19:14Z
sync:
    github:
        issue_number: "16"
        synced_at: "2026-02-15T22:08:23Z"
---

MCP tools (especially xc-build) timeout after long waits with AbortError. Implement:

1. **Streaming progress** - Send incremental output so clients know it's working
2. **Heartbeat messages** - Periodic 'still building...' status updates
3. **Configurable timeout** - Accept timeout parameter in tool arguments
4. **Early abort detection** - If xcodebuild stops producing output for N seconds, assume stuck

This helps distinguish between:
- A long but progressing build
- A truly stuck/hung build  
- A build that will eventually succeed

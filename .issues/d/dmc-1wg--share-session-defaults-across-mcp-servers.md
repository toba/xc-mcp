---
# dmc-1wg
title: Share session defaults across MCP servers
status: completed
type: feature
priority: normal
created_at: 2026-02-15T20:44:43Z
updated_at: 2026-02-15T21:22:37Z
---

## Problem

`set_session_defaults` on xc-build sets project_path, scheme, etc. but xc-debug doesn't pick them up since they're separate MCP servers with separate state. This forces users to pass project_path/scheme explicitly to every debug tool call.

## Observed Behavior

```
# Set defaults via xc-build
mcp__xc-build__set_session_defaults(project_path: "Thesis.xcodeproj", scheme: "Standard")

# Call xc-debug — fails because it doesn't see the defaults
mcp__xc-debug__build_debug_macos()
# Error: Either project_path or workspace_path is required
```

## Expected Behavior

Session defaults set via xc-build should be readable by xc-debug (and other xc-mcp servers), OR xc-debug should have its own `set_session_defaults`.

## Possible Solutions

- [ ] Shared storage (file-based or env) for session defaults across all xc-mcp servers
- [x] Add `set_session_defaults` to xc-debug independently
- [ ] Merge xc-build and xc-debug into a single server


## Summary of Changes

Added the 3 session management tools (`set_session_defaults`, `show_session_defaults`, `clear_session_defaults`) to the **xc-debug** and **xc-swift** MCP servers, which already had `SessionManager` instances but weren't exposing the session tools.

### Files modified
- `Sources/Servers/Debug/DebugMCPServer.swift` — Added 3 session tool enum cases, tool instantiation, registration, and dispatch
- `Sources/Servers/Swift/SwiftMCPServer.swift` — Same

### Servers with session tools (now all that have SessionManager)
- xc-build ✅ (already had)
- xc-simulator ✅ (already had)
- xc-device ✅ (already had)
- xc-debug ✅ (added)
- xc-swift ✅ (added)

### Note on cross-server sharing
Each server runs as a separate process with its own SessionManager. The LLM client needs to call `set_session_defaults` on each server it uses. True cross-server shared storage (file-based or env) remains a possible future enhancement but would add complexity for marginal benefit — the LLM can simply set defaults on whichever server it's about to use.

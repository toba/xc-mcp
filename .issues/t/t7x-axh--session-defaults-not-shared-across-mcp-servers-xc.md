---
# t7x-axh
title: Session defaults not shared across MCP servers (xc-device, xc-build, etc.)
status: ready
type: feature
priority: normal
created_at: 2026-03-14T00:32:28Z
updated_at: 2026-03-14T00:35:39Z
sync:
    github:
        issue_number: "208"
        synced_at: "2026-03-14T00:58:32Z"
---

## Problem

Each xc-mcp server (xc-device, xc-build, xc-simulator, etc.) maintains its own independent session defaults. Setting project/scheme/device on one server doesn't carry over to another, causing friction when tools from multiple servers are used together.

Example workflow that fails:

1. `xc-device.set_session_defaults(project: "Foo.xcodeproj", scheme: "Foo", device_udid: "...")`
2. `xc-build.get_app_bundle_id()` → error: "scheme is required"

The caller must redundantly set defaults on each server, or pass project/scheme explicitly to every cross-server call.

## Proposal

Consider a shared session defaults mechanism across servers, or at minimum document this behavior so callers know to set defaults per-server. Options:

- Shared defaults file on disk that all servers read
- A convention where the agent sets defaults on all servers at once
- Cross-server default inheritance

## Context

Observed while building and deploying Gerg app to iPad Mini — had to pass explicit project/scheme to `xc-build.get_app_bundle_id` after already setting defaults on `xc-device`.


## Evaluation

This is **already implemented**. The `SessionManager` uses PPID-scoped shared files (`/tmp/xc-mcp-session-{PPID}.json`) with automatic reload on access (`reloadIfNeeded()`). All focused servers (xc-device, xc-build, xc-simulator, etc.) spawned by the same parent process (e.g., Claude Code) share the same session file. Setting defaults on one server automatically propagates to others.

The mechanism:
1. `resolveFilePath()` uses `getppid()` to scope the session file by parent PID
2. `saveToDisk()` persists defaults atomically after any `setDefaults()` call
3. `reloadIfNeeded()` checks file modification date before every `resolve*()` call and reloads if another server wrote changes
4. The `XC_MCP_SESSION` env var overrides the PPID logic for custom setups

### When it could fail
- If servers are spawned by different parent processes (different PPIDs)
- If `XC_MCP_SESSION` is set differently per server
- If the MCP client spawns each server through a different wrapper/shell that changes the process tree

### Recommendation
Close as already-working. If the user hit this, it was likely a PPID mismatch — the fix would be to set `XC_MCP_SESSION` to a shared path in the MCP client config. No code changes needed.

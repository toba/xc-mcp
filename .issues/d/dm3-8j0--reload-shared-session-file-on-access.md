---
# dm3-8j0
title: Reload shared session file on access
status: completed
type: bug
priority: normal
created_at: 2026-02-25T02:59:03Z
updated_at: 2026-02-25T03:03:11Z
sync:
    github:
        issue_number: "138"
        synced_at: "2026-02-25T03:09:14Z"
---

## Problem

When multiple focused servers are running (e.g. xc-build and xc-debug), setting session defaults on one server doesn't propagate to the other. The shared file at `/tmp/xc-mcp-session.json` is written correctly, but long-running servers only read it once at startup in `SessionManager.init()`.

## Root Cause

`SessionManager` loads from disk in `init()` and never checks for external changes. The resolve methods (`resolveScheme`, `resolveBuildPaths`, etc.) only read in-memory actor state.

## Fix

- Track the file's modification date after each load/save
- Before resolving defaults, check if the file has been modified externally
- If so, reload from disk and update in-memory state
- Use a lightweight `reloadIfNeeded()` call (stat check only, no read unless changed)

## Tasks

- [x] Add `lastKnownModDate` tracking to SessionManager
- [x] Add `reloadIfNeeded()` method that stats the file and reloads if mtime changed
- [x] Call `reloadIfNeeded()` from `getDefaults()` and all resolve methods
- [x] Update `saveToDisk()` to record the new mtime after writing
- [x] Add tests for cross-process reload behavior


## Summary of Changes

Added `reloadIfNeeded()` to `SessionManager` that checks the shared file modification time before resolving defaults. If another server process has written to `/tmp/xc-mcp-session.json`, the in-memory state is refreshed automatically. This means `set_session_defaults` on xc-build now propagates to xc-debug (and all other focused servers) without needing to call it again on each server.

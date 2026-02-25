---
# 215-b3v
title: stop_mac_app hangs when process is crashed or under LLDB
status: completed
type: bug
priority: normal
created_at: 2026-02-25T02:01:08Z
updated_at: 2026-02-25T02:08:58Z
sync:
    github:
        issue_number: "130"
        synced_at: "2026-02-25T02:17:18Z"
---

\`stop_mac_app\` uses \`osascript -e 'tell application id "..." to quit'\` which hangs indefinitely when:
1. The app is already crashed (stopped under LLDB with SIGABRT)
2. The app is paused at a breakpoint
3. The app is unresponsive

The MCP call eventually times out or must be interrupted by the user.

**Fix options:**
1. Add a timeout to the osascript/pkill subprocess (e.g. 5s)
2. Check if the PID is in a debugged session — if so, use \`process kill\` via LLDB instead of osascript
3. If LLDB session exists for the bundle ID, prefer \`kill -TERM <pid>\` or LLDB \`process kill\`
4. Fallback chain: try graceful quit → timeout → SIGTERM → SIGKILL

The tool should also accept \`pid\` as a parameter (not just bundle_id/app_name) since the agent already knows the PID from \`build_debug_macos\`.

Discovered when trying to stop a crashed Thesis app (PID 99602) — the tool hung and had to be interrupted, then the user force-killed via \`kill -9\`.


## Summary of Changes

Rewrote `StopMacAppTool` to fix indefinite hangs when stopping crashed/debugged apps:

1. **Added `pid` parameter** — agents can pass the PID directly (from `build_debug_macos`), avoiding name-based lookup
2. **LLDB session PID resolution** — when `bundle_id` is provided and an LLDB session exists, resolves the PID via `LLDBSessionManager` to use signal-based kill instead of osascript
3. **5-second timeout on osascript** — the graceful `tell application ... to quit` now times out after 5s instead of hanging indefinitely
4. **Fallback chain** — graceful quit → SIGTERM → wait → SIGKILL, so crashed/hung apps are always terminated
5. **Added `timeout` parameter to `ProcessResult.run()`** — plumbs through to `runSubprocess` timeout support

---
# 1w3-m4e
title: build_run_sim reports false error on successful build, skips install and launch
status: completed
type: bug
priority: high
created_at: 2026-03-17T23:00:54Z
updated_at: 2026-03-17T23:10:44Z
sync:
    github:
        issue_number: "223"
        synced_at: "2026-03-17T23:12:18Z"
---

When `build_run_sim` is called, the build succeeds but the tool reports an error:

```
MCP error -32603: Internal error: Build appears stuck (no output for 30 seconds)

Build succeeded
```

The build output clearly shows success, but the "no output for 30 seconds" timeout fires during the linking/signing phase (which is normal — those steps produce no incremental output). Because this is treated as an error, the subsequent install and launch steps are skipped entirely.

**Reproduction:**
1. Call `build_run_sim` with a valid scheme and simulator
2. Build succeeds but tool returns an error
3. App is never installed or launched on the simulator

**Expected behavior:**
- The "no output" timeout should be longer or not apply during linking/signing
- If the build succeeds (exit code 0), install and launch should proceed regardless of output gaps
- The tool should not report an error when the build actually succeeded

**Related:** The simulator was also shutdown and `build_run_sim` did not boot it before attempting install. Consider auto-booting if the target simulator is shutdown.


## Summary of Changes

### Fix: False "build appears stuck" error (`BuildRunSimTool`, `BuildSimTool`)

Increased `outputTimeout` from 30s (default) to 120s (`deviceOutputTimeout`) for simulator builds. The 30s threshold was too aggressive — linking and code signing phases routinely produce no output for >30 seconds, triggering a false `stuckProcess` error even when the build succeeds.

### Fix: Auto-boot simulator before install/launch (`BuildRunSimTool`)

Added a step after the build to check simulator state via `listDevices()` and call `boot()` if the simulator is not already booted. This prevents install/launch failures when the target simulator is shut down.

### Files changed

- `Sources/Tools/Simulator/BuildRunSimTool.swift` — increased output timeout, added auto-boot step
- `Sources/Tools/Simulator/BuildSimTool.swift` — increased output timeout

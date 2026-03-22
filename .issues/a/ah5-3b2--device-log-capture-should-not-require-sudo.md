---
# ah5-3b2
title: Device log capture should not require sudo
status: completed
type: bug
priority: high
created_at: 2026-03-22T01:58:35Z
updated_at: 2026-03-22T02:07:43Z
sync:
    github:
        issue_number: "233"
        synced_at: "2026-03-22T02:08:11Z"
---

## Problem

`stop_device_log_cap` uses `log collect --device-udid` which requires root privileges. This makes the tool unusable from Claude Code or any non-interactive context where sudo prompts can't be answered.

The current workaround is asking the user to run the sudo command manually via `!`, which defeats the purpose of the MCP tool.

## Expected

Device log capture should work without sudo, or the tool should use an alternative approach that doesn't require root.

## Possible Approaches

- [x] Switch `start_device_log_cap` to use `log stream --level info --predicate '...' > file &` — streams in real-time, no sudo needed
- [x] `stop_device_log_cap` kills the stream process and returns the captured file contents
- [x] Drop `log collect` approach entirely — it always requires root for device logs
- [x] `devicectl` has no log subcommand, so it's not an alternative
- [x] The `!` prompt in Claude Code can't handle interactive sudo (no TTY), so sudo-dependent tools are fundamentally broken in this context


## Summary of Changes

Rewrote `StartDeviceLogCapTool` and `StopDeviceLogCapTool` to use `log stream` as a background process instead of `log collect --device-udid` (which required sudo).

- `start_device_log_cap` now launches `log stream --style compact` with predicate/level filtering, writing to a file via `LogCapture.launchStreamProcess` (same pattern as sim/mac log cap tools)
- `stop_device_log_cap` now kills the stream process via `LogCapture.stopCapture` and returns the tail of the log file
- `DeviceLogCapMetadata` simplified to store `pid` instead of `startTime` — no longer needs time-based `log collect`
- Removed all `log collect` / `log show` / logarchive logic from stop tool

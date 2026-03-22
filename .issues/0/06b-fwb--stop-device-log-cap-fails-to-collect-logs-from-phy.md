---
# 06b-fwb
title: stop_device_log_cap fails to collect logs from physical device
status: completed
type: bug
priority: normal
created_at: 2026-03-22T01:21:38Z
updated_at: 2026-03-22T01:27:02Z
sync:
    github:
        issue_number: "232"
        synced_at: "2026-03-22T01:29:06Z"
---

When using start_device_log_cap followed by stop_device_log_cap on a physical iPad mini (6th gen, iOS 18.7.3), log collection fails with:

```
MCP error -32603: Internal error: Failed to collect device logs:
```

The devicectl CLI on macOS doesn't expose a `log collect` subcommand under `device info`, so the current implementation path may be broken. Need to investigate the correct devicectl API for collecting unified logs from a physical device.

Tested with:
- Device: iPad mini 6th gen (A5CC2917-0B66-5306-8C9F-A60BFEB112C1)
- OS: iPadOS 18.7.3
- Subsystem filter: app.toba.gamerg
- Level: debug


## Summary of Changes

Two root causes fixed:

1. **Date format mismatch** (`StartDeviceLogCapTool.swift`): Changed from `ISO8601DateFormatter` to `DateFormatter` with `yyyy-MM-dd HH:mm:ss` format — the format `/usr/bin/log collect --start` actually accepts. The ISO8601 `T` separator and `Z` suffix caused `log collect` to reject the timestamp with exit code 64.

2. **Empty error message** (`StopDeviceLogCapTool.swift`): `log collect` writes its error diagnostic to stdout, not stderr. Updated the error handler to fall back to stdout when stderr is empty, so the actual error message is now visible.

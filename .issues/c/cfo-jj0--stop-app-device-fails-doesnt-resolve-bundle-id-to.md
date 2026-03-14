---
# cfo-jj0
title: stop_app_device fails — doesn't resolve bundle_id to PID
status: completed
type: bug
priority: normal
created_at: 2026-03-14T01:32:59Z
updated_at: 2026-03-14T01:36:37Z
sync:
    github:
        issue_number: "213"
        synced_at: "2026-03-14T01:38:19Z"
---

## Description

`stop_app_device` fails with `Missing expected argument '--pid <pid>'` because it doesn't resolve the bundle identifier to a PID before calling `devicectl device process terminate`.

## Error

```
Error: MCP error -32603: Internal error: Failed to stop app: Error: Missing expected argument '--pid <pid>'
Help:  --pid <pid>  The process identifier to terminate.
Usage: devicectl device process terminate --device <uuid|ecid|serial_number|udid|name|dns_name> --pid <pid> [--kill] ...
```

## Expected Behavior

`stop_app_device(bundle_id: "app.toba.gerg")` should:
1. Look up the running PID via `devicectl device info processes`
2. Pass `--pid <pid>` to `devicectl device process terminate`

## Workaround

```bash
xcrun devicectl device info processes --device <UDID> | grep <app_name>
xcrun devicectl device process terminate --device <UDID> --pid <pid>
```

## Also

`start_device_log_cap` with `subsystem == "app.toba.gerg"` predicate produces empty log files — the predicate filtering may not be working correctly with `devicectl`. Device log capture with `bundle_id` filter also produced empty results. Needs investigation.


## Summary of Changes

Fixed `stop_app_device` by resolving the bundle identifier to a PID before calling `devicectl device process terminate`.

### Changes in `DeviceCtlRunner.swift`

- **`terminate(udid:bundleId:)`** — now calls `findPID(forBundleID:udid:)` first, then passes `--pid` to `devicectl device process terminate` (previously passed invalid `--bundle-id` flag)
- **`listProcesses(udid:)`** — new method that queries `devicectl device info processes --json-output -` and parses the result
- **`findPID(forBundleID:udid:)`** — new method that resolves a bundle ID to a PID by matching against `bundleURL` or executable path
- **`parseProcessList(from:)`** — new private JSON parser for the process list output
- **`DeviceProcess`** — new struct representing a running process (PID, executable, bundleURL)
- **`DeviceCtlError.processNotFound`** — new error case for when no running process matches the bundle ID

---
# m5k-jma
title: start_device_log_cap produces empty log files — predicate filtering broken
status: completed
type: bug
priority: normal
created_at: 2026-03-14T01:35:46Z
updated_at: 2026-03-14T01:41:51Z
sync:
    github:
        issue_number: "214"
        synced_at: "2026-03-14T01:42:16Z"
---

## Description

`start_device_log_cap` consistently produces empty log files regardless of predicate or filter used. Tested multiple approaches:

1. `bundle_id: "app.toba.gerg"` filter — empty
2. `predicate: 'process == "Gerg" OR subsystem == "com.apple.bluetooth"'` — empty  
3. `predicate: 'subsystem == "app.toba.gerg"'` — empty

The app is confirmed running on the device (visible on screen, PID confirmed via `devicectl device info processes`). The app uses `os.Logger(subsystem: "app.toba.gerg", category: "RowingManager")` which should produce unified log output.

## Device

- iPad mini (6th generation), iOS 18.7.3
- UDID: A5CC2917-0B66-5306-8C9F-A60BFEB112C1
- Connection: wired USB

## Investigation Notes

- `stop_device_log_cap` reports success ("Stopped log capture") but the output file is always 0 bytes
- `devicectl` does not appear to have a `syslog` subcommand — need to verify what underlying command `start_device_log_cap` is using
- The macOS `log stream` command does not support `--device` for remote devices via devicectl
- May need to use `idevicesyslog` (libimobiledevice) or `log collect --device` as the underlying mechanism

## Expected Behavior

Log capture should produce log output matching the filter/predicate from the running app on the connected device.


## Summary of Changes

Replaced broken `devicectl device info syslog` (nonexistent subcommand) with `log collect --device-udid` + `log show` approach.

### `StartDeviceLogCapTool.swift`

- Records start timestamp, device UDID, predicate, and level to a temp metadata file (`/tmp/device_log_cap_<UDID>.json`)
- Builds NSPredicate from `bundle_id` (process name match) and/or `subsystem` parameters
- Added `subsystem` and `level` parameters matching the macOS log capture tool
- No longer spawns a background process (was spawning a process for a nonexistent command)

### `StopDeviceLogCapTool.swift`

- Reads metadata from `start_device_log_cap`, runs `log collect --device-udid <UDID> --start <time>` to fetch a `.logarchive`
- Runs `log show <archive> --style compact [--predicate ...]` to filter and write readable output
- Cleans up metadata file after collection
- Removed PID-based and pkill-based process stopping (no longer needed)

### `DeviceLogCapMetadata`

- New `Codable` struct for persisting capture session config between start/stop calls

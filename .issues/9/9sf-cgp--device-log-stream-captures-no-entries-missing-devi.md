---
# 9sf-cgp
title: Device log stream captures no entries — missing --device flag
status: completed
type: bug
priority: high
created_at: 2026-03-22T02:19:03Z
updated_at: 2026-03-22T02:35:46Z
sync:
    github:
        issue_number: "235"
        synced_at: "2026-03-22T02:44:55Z"
---

## Problem

`start_device_log_cap` produces an empty log file (only the filter header lines, no actual entries) when capturing from a physical device. The subsystem filter `app.toba.gamerg` with level `info` matches the app's `os.Logger` configuration, but zero lines are captured.

## Root Cause (likely)

`log stream` without `--device` or `--device-udid <UDID>` only streams logs from the local Mac, not from the connected iOS device. The tool needs to pass the device UDID to `log stream`.

## Reproduction

1. Deploy an app with `os.Logger` statements to a physical device
2. `start_device_log_cap` with `subsystem` filter and `level: info`
3. Exercise the app on device to trigger log statements
4. `stop_device_log_cap` — log file contains only filter header, no entries

## Fix

- [x] Pass `--device` or `--device-udid <UDID>` to the `log stream` command in `start_device_log_cap`
- [x] Verify that `log stream --device-udid` does not require sudo (unlike `log collect`)


## Summary of Changes

Rewrote `StartDeviceLogCapTool` to use `idevicesyslog` from libimobiledevice instead of `/usr/bin/log stream`. `log stream` has no device flags at all — it is local Mac only. `idevicesyslog` streams unified logs from a physical device over USB without sudo. The tool auto-locates the binary via Homebrew paths or PATH, and errors with install instructions if not found. Filter parameters updated to match idevicesyslog's `-m` (match string) and `-p` (process name) flags.

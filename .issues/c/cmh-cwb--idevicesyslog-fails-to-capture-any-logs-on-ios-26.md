---
# cmh-cwb
title: idevicesyslog fails to capture any logs on iOS 26 devices
status: completed
type: bug
priority: normal
created_at: 2026-03-29T18:41:07Z
updated_at: 2026-03-29T18:54:48Z
sync:
    github:
        issue_number: "246"
        synced_at: "2026-03-29T18:54:53Z"
---

Device log capture via start_device_log_cap / stop_device_log_cap produces no application logs on iOS 26 (iPadOS 26.4). idevicesyslog connects then immediately disconnects with no log output — neither os.Logger nor NSLog messages appear. Tested with both -m (match) and -p (process) filters, and also with no filters at all. The tool may need an update to support iOS 26 syslog_relay changes.

Observed on:
- iPad mini (6th generation), iPadOS 26.4
- idevicesyslog from libimobiledevice (Homebrew)

Expected: NSLog and os.Logger output captured and written to log file.
Actual: Log file contains only [connected] / Exiting... / [disconnected] lines.



## Summary of Changes

Investigation found idevicesyslog works on iOS 26 but NSLog content is privacy-redacted as `<private>`. Updated `start_device_log_cap` tool description to document iOS 26 privacy behavior and recommend `os.Logger` over NSLog, and `process` filter over `match` filter.

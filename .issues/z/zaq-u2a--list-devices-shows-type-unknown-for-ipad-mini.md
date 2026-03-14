---
# zaq-u2a
title: 'list_devices shows ''Type: Unknown'' for iPad Mini'
status: completed
type: bug
priority: normal
created_at: 2026-03-14T00:31:26Z
updated_at: 2026-03-14T00:34:56Z
sync:
    github:
        issue_number: "211"
        synced_at: "2026-03-14T00:58:38Z"
---

## Problem

`list_devices` returns `Type: Unknown` for a connected iPad Mini:

```
📱 Jason's iPad
   UDID: A5CC2917-0B66-5306-8C9F-A60BFEB112C1
   Type: Unknown
   OS Version: 18.7.3
   Connection: wired
```

The device type/model should be identified (e.g., "iPad mini (6th generation)") using the device's product type or model identifier.

## Context

iPad Mini running iOS 18.7.3, connected via USB.


## Summary of Changes

- Fixed `DeviceCtlRunner.parseDeviceList` to read `marketingName` and `productType` from `hardwareProperties` (where devicectl actually puts them) instead of `deviceProperties`
- Prefers `marketingName` (e.g., "iPad mini (6th generation)") over raw `productType` (e.g., "iPad14,1")
- Falls back to `productType` then `deviceType` then "Unknown"

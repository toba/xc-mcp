---
# caw-yth
title: 'build_device: false ''build appears stuck'' error on successful builds'
status: completed
type: bug
priority: high
created_at: 2026-03-14T00:31:23Z
updated_at: 2026-03-14T00:33:38Z
sync:
    github:
        issue_number: "210"
        synced_at: "2026-03-14T00:58:34Z"
---

## Problem

When building for a physical device via `build_device`, the tool returns an MCP error even though the build succeeds:

```
MCP error -32603: Internal error: Build appears stuck (no output for 30 seconds)

Build succeeded
```

The 30-second silence heuristic triggers a false positive during device builds, likely because code signing or asset processing produces no stdout for extended periods.

## Reproduction

1. Connect a physical iOS device
2. Call `build_device` for a project
3. Build succeeds but returns an error

## Expected

Successful builds should not return errors. The stuck-build heuristic needs a longer timeout for device builds, or should check the final exit code before reporting stuck status.

## Context

Observed while building Gerg app for iPad Mini (iOS 18.7.3) via xc-device MCP tools.


## Summary of Changes

- Added `outputTimeout` parameter to `XcodebuildRunner.build()` method
- Added `deviceOutputTimeout` constant (120 seconds) to `XcodebuildRunner`
- `BuildDeviceTool` now passes the longer 120-second output timeout instead of the default 30 seconds
- Code signing and asset processing for physical devices can produce long output gaps that triggered false "stuck" errors

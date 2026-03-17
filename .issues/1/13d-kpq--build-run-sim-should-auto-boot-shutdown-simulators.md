---
# 13d-kpq
title: build_run_sim should auto-boot shutdown simulators
status: completed
type: feature
priority: normal
created_at: 2026-03-17T23:01:07Z
updated_at: 2026-03-17T23:11:04Z
sync:
    github:
        issue_number: "222"
        synced_at: "2026-03-17T23:12:18Z"
---

When `build_run_sim` targets a simulator that is in the Shutdown state, it should automatically boot it before attempting to install and launch the app.

Currently you must manually call `boot_sim` first, which defeats the purpose of the combined `build_run_sim` convenience tool.

`boot_sim` exists and works — `build_run_sim` should call it internally when the target simulator isn't booted.


## Summary of Changes

Addressed as part of 1w3-m4e. `BuildRunSimTool` now checks simulator state via `listDevices()` after the build step and calls `boot()` if the simulator is not in the "Booted" state, before attempting install and launch.

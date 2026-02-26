---
# n4b-ig9
title: launch_mac_app / build_run_macos should return PID and detect early exit
status: completed
type: feature
priority: normal
created_at: 2026-02-26T00:11:27Z
updated_at: 2026-02-26T00:40:14Z
sync:
    github:
        issue_number: "139"
        synced_at: "2026-02-26T00:40:29Z"
---

## Problem

`launch_mac_app` and `build_run_macos` report "Successfully launched" even when the app exits immediately (e.g. crash on launch, sandbox denial, missing entitlement). There's no PID returned and no way to verify the app is still running.

## Observed During

Thesis session: `build_run_macos` and `launch_mac_app` both reported success for `com.thesisapp.debug`, but `ps` showed no matching process. The app likely crashed on launch but the tools gave no indication.

## Suggestion

1. Return the PID in the success response
2. After a brief delay (~1s), verify the process is still alive
3. If the app exited, report failure with exit code (and stderr/crash log path if available)

## TODO

- [x] Return PID from launch_mac_app and build_run_macos
- [x] Add post-launch liveness check
- [x] Surface exit code / crash info on early termination

## Summary of Changes

Both `launch_mac_app` and `build_run_macos` now:

1. **Return PID** — after launching via `/usr/bin/open`, resolve the PID via `pgrep` (tries bundle ID first, then app name)
2. **Liveness check** — waits 1 second then checks if the process is still alive via `kill(pid, 0)`
3. **Early exit detection** — if the app exited, the response includes `(exited — app may have crashed on launch)`

**Files changed:**
- `Sources/Tools/MacOS/LaunchMacAppTool.swift`
- `Sources/Tools/MacOS/BuildRunMacOSTool.swift`

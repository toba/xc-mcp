---
# n4b-ig9
title: launch_mac_app / build_run_macos should return PID and detect early exit
status: ready
type: feature
priority: normal
created_at: 2026-02-26T00:11:27Z
updated_at: 2026-02-26T00:11:27Z
sync:
    github:
        issue_number: "139"
        synced_at: "2026-02-26T00:30:34Z"
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

- [ ] Return PID from launch_mac_app and build_run_macos
- [ ] Add post-launch liveness check
- [ ] Surface exit code / crash info on early termination

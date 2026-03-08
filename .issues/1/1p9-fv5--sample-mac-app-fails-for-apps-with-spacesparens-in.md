---
# 1p9-fv5
title: sample_mac_app fails for apps with spaces/parens in name or bundle ID
status: completed
type: bug
priority: normal
created_at: 2026-03-08T06:10:44Z
updated_at: 2026-03-08T06:21:45Z
sync:
    github:
        issue_number: "194"
        synced_at: "2026-03-08T06:22:29Z"
---

## Problem

`sample_mac_app` fails in two ways when targeting an app whose name contains spaces and parentheses (e.g. `ThesisApp (debug)`):

### 1. Bundle ID lookup fails

```
bundle_id: "com.thesisapp.debug"
→ "No running process found for bundle ID 'com.thesisapp.debug'"
```

The app is definitely running — `pgrep -fl ThesisApp` finds PID 51982. The bundle ID resolution likely uses a method that doesn't match the running process name or bundle ID correctly (possibly the debug bundle ID differs from the build settings value, or the lookup command doesn't handle the parenthesized suffix).

### 2. PID-based sampling fails

```
pid: 51982
→ "Failed to sample process 51982: Subprocess.SubprocessError error 1"
```

The `sample` command itself works fine from the terminal (`sample 51982 10 1 -f /tmp/out.txt`), so the subprocess invocation is likely failing due to argument quoting or the output file path handling.

## Reproduction

```
App: "ThesisApp (debug).app"
Process: "ThesisApp (debug)" (PID 51982)
Bundle ID (from build settings): com.thesisapp.debug
```

1. Build and launch via `build_run_macos` — succeeds
2. `sample_mac_app(bundle_id: "com.thesisapp.debug")` — fails with "no running process"
3. `sample_mac_app(pid: 51982)` — fails with SubprocessError

## Expected

Both should work. The `sample` CLI tool has no issue with the PID.


## Summary of Changes

1. `PIDResolver.findPID(forBundleID:)` — new method using `NSRunningApplication.runningApplications(withBundleIdentifier:)` for reliable bundle ID → PID resolution. `findLaunchedPID` now tries this first before falling back to `pgrep -f`.
2. `SampleMacAppTool` — uses new `findPID(forBundleID:)` for bundle ID lookups; uses `-file` flag with `sample` command for reliable output capture instead of relying on stdout.
3. `MCPErrorConvertible` — changed `import Runtime` to `@_weakLinked import Runtime` to prevent `libswiftRuntime.dylib` load failure on pre-macOS 26.

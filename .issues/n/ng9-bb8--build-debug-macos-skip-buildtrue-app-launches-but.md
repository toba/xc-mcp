---
# ng9-bb8
title: 'build_debug_macos skip_build:true: app launches but window never appears'
status: deferred
type: bug
priority: normal
created_at: 2026-05-30T19:55:36Z
updated_at: 2026-05-30T19:55:36Z
sync:
    github:
        issue_number: "370"
        synced_at: "2026-05-30T20:05:31Z"
---

Split from j22-xn8 (bug #1). The bug 2 portion (view-hierarchy fputs flush) was fixed in j22-xn8.

## Symptom

`build_debug_macos skip_build:true` reports `Successfully relaunched … Process N launched and running under debugger`. `debug_process_status` returns `running`, but no window appears, and `screenshot_mac_window` fails with 'No window found matching bundle_id'. The same args via a fresh full-build `build_debug_macos` (no `skip_build`) works.

## Investigation notes (2026-05-30)

Code-path analysis: the skip_build branch in `BuildDebugMacOSTool.execute` only gates the `xcodebuildRunner.build()` call — everything after (kill existing session, `AppBundlePreparer.prepare`, `launchViaOpenAndAttach`) is identical between the two branches. So the LLDB attach/continue sequence in `runOpenAndAttach` (Sources/Core/LLDBRunner.swift:1003) cannot be the differentiator at the Swift level.

The reporter's intuition ("the relaunch path forgets to issue the initial process continue") is not supported by the code — `sendCommandNoWait("continue")` runs unconditionally when `stopAtEntry` is false, regardless of skip_build.

Note: `ps -p N -o state` showing `SX` is *expected* for any LLDB-attached running process (S = sleeping, X = traced). It does NOT mean the process is stopped at entry. The real symptom is "no window appears".

## Hypotheses to test next time this reproduces

1. **Launch Services state**: `xcodebuild build` registers/refreshes the bundle with `lsregister`. With skip_build, if the bundle's LS registration got stale (e.g. prior external resign), `/usr/bin/open` might activate a phantom record rather than launch a fresh instance. Test: `lsregister -dump | grep <bundleId>` before/after.
2. **AppBundlePreparer mismatch**: in skip_build, `prepare()` only re-signs when `CodeSignInspector.checkBundleConsistency` flags a mismatch. A bundle that's *internally consistent but stale relative to current frameworks* would skip re-signing and silently fail dyld at launch. Test: capture `crashOutput` from `checkForEarlyCrash` more aggressively (raise its delay, or always read full attach output) on skip_build relaunches.
3. **pkill race**: `pkill -f appPath` + 500ms sleep before `open`. If the prior instance is slow to die (e.g. crash reporter handling), `open` without `-n` may see the stale record and skip launching. Test: add `open -n`, or replace the sleep with a polled `pgrep` loop.

## Repro

1. `build_debug_macos scheme:TestApp args:[…]` — works, window visible.
2. Kill the app, run again with `skip_build:true` — process spawns but window never appears.

## Deferral Notes

Cannot fix without a live repro: code paths converge after the skip_build gate, so the differentiator must be runtime state (Launch Services, dyld, code-signing). Need to capture diagnostic output (`lsregister -dump`, `log show` from launchd, `checkForEarlyCrash` attach trace) during a fresh repro before choosing a fix among the three hypotheses above. Predecessor: j22-xn8.

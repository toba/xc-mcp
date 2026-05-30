---
# ng9-bb8
title: 'build_debug_macos skip_build:true: app launches but window never appears'
status: deferred
type: bug
priority: normal
created_at: 2026-05-30T19:55:36Z
updated_at: 2026-05-30T20:22:50Z
sync:
    github:
        issue_number: "370"
        synced_at: "2026-05-30T20:25:01Z"
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



## Validation against ../thesis TestApp (2026-05-30)

Ran scripts/validate-j22-xn8.sh against the Thesis TestApp scheme to attempt repro:

1. Full `build_debug_macos` → window visible, PID 29707 (state SX).
2. `debug_detach` from PID, then `pkill -f com.thesisapp.testapp`.
3. `build_debug_macos skip_build:true` → PID 31445 (state SX).
4. `expr (NSUInteger)[[NSApp windows] count]` → `1`.
5. `screenshot_mac_window` → 397KB PNG saved successfully.

**Bug did NOT reproduce.** The skip_build relaunch worked cleanly on TestApp.

`lsregister -dump` returned no record for the bundle ID either before or after the relaunch — but this didn't prevent a clean relaunch. So hypothesis #1 (Launch Services staleness as a *general* failure mode) is partially weakened: a missing LS record didn't break the flow on TestApp.

This rules out a deterministic Swift-level bug in the shared launch path and points toward project- or environment-specific state. Most likely remaining causes:
- The original Thesis repro used the `Standard` scheme, which has a substantially larger framework / SPM dependency set than `TestApp`. Hypothesis #2 (AppBundlePreparer skipping re-sign on a bundle whose frameworks are internally consistent but stale relative to current dyld state) remains the most plausible.
- Prior crash / signal handler state on the killed instance leaving a zombie record only when the framework set is large enough to be slow to tear down.

## Next steps when this reproduces again

Need to gather these *at the time of failure*, not later:
1. Run the same validation harness against the failing scheme (likely `Standard`) immediately after the failed `skip_build:true` call.
2. Capture `codesign -dvv` Team-ID consistency report for the bundle and all frameworks in `Contents/Frameworks`.
3. Capture `log show --predicate 'eventMessage CONTAINS ""' --last 5m` from launchd / Launch Services / dyld.
4. Compare `AppBundlePreparer.checkBundleConsistency` result before vs after the failed relaunch.

Harness saved at `scripts/validate-j22-xn8.sh` — runnable against any project/scheme pair.



## Cross-ref: Thesis-side wis-g7q (#1130 in toba/thesis)

Original repro context lives in Thesis issue `wis-g7q` ("Tables: eliminate load-time shadowed hosting-view transient"). Key trigger conditions documented there that my isolated TestApp repro did NOT match:

1. **Specific launch args**: `build_debug_macos scheme:TestApp args:["--database","<debug.sqlite>","--show-node","820D91B0-7C30-477B-9606-DF1357ED55BE"]`. The agent was launching TestApp pointed at a previously-set-up sqlite file with a specific document loaded.
2. **Warm DerivedData + WIP build errors**: at the time the bug was observed, Thesis had unrelated WIP errors (`BayeuxClient.swift:132:33`, missing `outgoingEligibleFilter` symbol) blocking fresh builds. The agent only reached `skip_build:true` because a prior cold build had populated `~/Library/Caches/xc-mcp/DerivedData/Thesis-4019ecb6511d/` *before* those errors landed. So the on-disk bundle was "older than current source" in a way a clean tree never produces.

Without that stale-bundle condition I cannot reproduce locally — the validation script ran against a freshly-built bundle and worked correctly.

## Refined finding: AppBundlePreparer re-sign DID fire

Both of my Phase 1 (full build) and Phase 3 (skip_build relaunch) attempts logged:

```
AppBundlePreparer: Team-ID mismatch detected on unmodified bundle; forcing disable-library-validation re-sign
```

So hypothesis #2 as originally written ("re-sign silently skipped") is wrong — re-sign IS firing. The refined hypothesis: the failure mode requires the re-sign to *fail* or to leave the bundle in an inconsistent state, OR an entirely different failure path. Worth checking what `codesign --force --sign` returns when the bundle has frameworks whose Team IDs were freshly rewritten by a prior `AppBundlePreparer` cycle but whose contents now mismatch dyld's view of the same identity.

## What we now know about ng9-bb8's trigger surface

- NOT a deterministic Swift-level bug (TestApp w/ no args, fresh build, then kill+skip_build → works).
- NOT "AppBundlePreparer skips re-sign" (it fires on skip_build relaunches when there's a Team-ID mismatch).
- Most likely needs: stale on-disk bundle (built against older source) + skip_build + LaunchServices state from a prior crash or detach.

## Reproducing requires the actual Thesis workload

To attempt repro again, an agent would need to: (a) check out Thesis at a commit *before* the WIP errors mentioned in wis-g7q, (b) cold-build via `build_debug_macos`, (c) introduce or stash-pop the WIP errors so the source no longer builds clean, (d) attempt `skip_build:true` against the warm bundle. The bug surface is environment-specific, not unit-testable in isolation.

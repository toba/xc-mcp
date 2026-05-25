---
# i4t-491
title: Add no-rebuild relaunch for debug macOS apps (launch-only tool or skip_build on build_debug_macos)
status: completed
type: feature
priority: normal
created_at: 2026-05-25T20:24:21Z
updated_at: 2026-05-25T20:29:45Z
blocked_by:
    - vqc-o14
sync:
    github:
        issue_number: "337"
        synced_at: "2026-05-25T20:30:27Z"
---

## Problem

There is no supported way to **relaunch an already-built debug macOS app without going through `build_debug_macos`'s full build step**. This matters for a common workflow: relaunch the *same* binary with different environment variables or args (e.g. toggling a feature/reset flag like `THESIS_RESET_CK_ZONES`). Nothing about the binary changes, yet `build_debug_macos` always runs the build pipeline (BuildDebugMacOSTool.swift:190 "Step 2: Build"), which — compounded by the unstable scoped DerivedData root (see related issue) — meant minutes per relaunch.

Working around it by exec'ing the built Mach-O directly is unreliable:

```
nohup env DYLD_FRAMEWORK_PATH="$BASE" "$APP/Contents/MacOS/ThesisApp (debug)" &
```

The process runs briefly (long enough to execute `.task` work — e.g. the zone reset logged successfully) then **exits on its own with no crash output**, so it can't host an interactive session for the user to type into. This is the documented DYLD/Launch-Services fragility that `build_debug_macos` exists to solve — but that tool can't be used for a no-rebuild relaunch.

## Request

Add a launch-only path. Either:
1. A new `launch_debug_macos` tool that takes a previously-built app (or resolves the scoped product) and launches it under LLDB with the correct `DYLD_FRAMEWORK_PATH`/Launch Services activation — **no build** — accepting `env` and `args`; or
2. A `skip_build: true` (or `rebuild: false`) parameter on `build_debug_macos` that skips the build when the product is already current and just launches + attaches.

This gives a fast, reliable way to relaunch with new env/args (the exact need when iterating on launch-time flags) without paying for a build or fighting bare-exec lifetime/DYLD issues.

## Context

Encountered while iterating on a CloudKit zone-reset flow gated by an env var: each toggle of the env var forced a full (cold) `build_debug_macos`, and the bare-exec fallback wouldn't stay alive to host the editor session.


## Summary of Changes

Implemented option 2: added a `skip_build: true` parameter to `build_debug_macos` (BuildDebugMacOSTool.swift).

- When set, the tool skips the `xcodebuild build` step (Step 2) and goes straight to bundle preparation + LLDB launch/attach, reusing all the existing build-settings resolution, `AppBundlePreparer`, and `launchViaOpenAndAttach` machinery — so relaunches get the correct DYLD_FRAMEWORK_PATH / Launch Services activation and a hostable interactive session, unlike a bare exec.
- `env` and `args` are honored on relaunch, which is the core need (toggling launch-time flags like `THESIS_RESET_CK_ZONES`).
- Guards against a missing product: if `skip_build` is set but no built `.app` exists at the resolved path, it throws a clear `invalidRequest` telling the user to build first.
- Success message reads "relaunched" vs "built and launched"; tool description and schema document the new parameter.

Combined with the vqc-o14 fix (stable scoped DerivedData root), relaunching with new env/args is now fast and reliable.

Tests: added `BuildDebugMacOSToolTests` covering the schema exposure of `skip_build`.

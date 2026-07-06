---
# okr-ood
title: macOS launch tools don't apply the scheme's StoreKit configuration (StoreKitConfigurationFileReference), silently disabling StoreKit-gated features
status: completed
type: bug
priority: normal
created_at: 2026-07-06T21:15:45Z
updated_at: 2026-07-06T22:56:37Z
sync:
    github:
        issue_number: "407"
        synced_at: "2026-07-06T23:03:04Z"
---

## Problem

Apps launched through the macOS build/launch tools (`build_debug_macos`, `build_run_macos`, `launch_mac_app`) run **without the scheme's StoreKit configuration applied**. `Product.products(for:)` returns an empty array (no error), so any feature gated on a StoreKit entitlement — subscriptions, and anything downstream of them — can't be exercised through the tooling.

## Root cause

A `.storekit` configuration file is injected by whatever **launches** the app, not baked into the build. The Xcode IDE's Run/Test uses an internal XPC path (the `storekitd` container) to push the scheme's `StoreKitConfigurationFileReference` to the launched process. The CLI build tool and direct-binary launches do **not** invoke that path — documented Xcode 26 behavior. Every xc-mcp macOS launch runs the binary directly, so StoreKit testing is never active.

## Impact (real case)

The Thesis app gates CloudKit push on subscription `canWrite`. Launched via xc-mcp, `Product.products` returns 0 -> `SubscriptionGroupUnavailable` -> `canWrite=false` -> CloudKit sync silently pauses (records pile up in CKSyncEngine state, empty send/fetch loop). This presented as a "CloudKit sync is broken" mystery and cost hours of misdiagnosis, because the tooling gives no signal that the scheme's StoreKit config was dropped.

## Repro

1. Project with a scheme referencing a `.storekit` via `StoreKitConfigurationFileReference` (Run action).
2. `build_debug_macos` / `launch_mac_app` the app.
3. Call `Product.products(for: [...])` at runtime -> empty array.
4. Launch the same scheme via Xcode IDE (Cmd+R) -> products load.

## Requests (any of)

- Read the scheme's `StoreKitConfigurationFileReference` and apply it when launching — replicate the IDE's injection (e.g. `SKTestSession` / the storekitd container hand-off) so launched apps see the synthetic store.
- Expose a `storekit_config` parameter on the macOS build/launch tools to opt in explicitly.
- At minimum: when a target's run scheme references a StoreKit config, **emit a warning** from the launch tools that it will not be applied, so StoreKit-gated behavior isn't silently disabled.

## References

- Apple Developer Forums — Product.products empty with local StoreKit config (macOS): https://developer.apple.com/forums/thread/748015
- StoreKit config not pushed to destination via the CLI (IDE-only XPC path): https://developer.apple.com/forums/thread/803084

## Summary of Changes

Implemented the "at minimum" request: the macOS launch tools now **warn** when the launched scheme's Run action references a StoreKit configuration that a direct (non-IDE) launch cannot apply.

### Why a warning, not injection
Applying the scheme's `StoreKitConfigurationFileReference` to a directly-launched app is not reliably possible: Xcode delivers it over a private `storekitd` XPC hand-off that CLI/direct-binary launches don't invoke (documented Xcode 26 behavior; confirmed by the two Apple Forums threads in the issue). Rather than add a `storekit_config` parameter that silently does nothing, the tools now make the drop visible and point at the paths that *do* work.

### New helper
`Sources/Tools/MacOS/StoreKitLaunchAdvisory.swift` — pure function that, given a scheme + project/workspace container, finds the scheme file, reads the **Run (LaunchAction)** `StoreKitConfigurationFileReference` (reusing `SetSchemeStoreKitConfigTool.storeKitIdentifiers` from pzg-2cv), and returns a warning. Only the Run reference drives it (the Test reference applies to `xcodebuild test`, not a launch). Also flags when the reference itself doesn't resolve to a file.

The warning explains the drop (`Product.products(for:)` returns empty, StoreKit-gated features silently disabled) and gives the working alternatives: run from the Xcode IDE (Cmd+R), or drive it from tests via `SKTestSession(configurationFileNamed:)` — cross-referencing `add_storekit_config` from pzg-2cv for wiring the config into a test target.

### Wiring
- `build_run_macos` and `build_debug_macos`: warn using their explicit scheme + project/workspace.
- `launch_mac_app`: best-effort using the session's default scheme/project (it has no scheme argument); warns only when a session default is set and its Run action references a config.

### Tests
`StoreKitLaunchAdvisoryTests` (5): Run-action reference warns; no reference → no warning; Test-only reference → no launch warning; wrong-depth reference is flagged as unresolved; nil/unknown scheme → no warning. All pass; build clean; formatted with `sm`.

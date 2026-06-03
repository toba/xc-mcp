---
# ok5-hxo
title: Add headless launch policy (XC_MCP_HEADLESS_LAUNCH) to suppress focus-stealing GUI launches
status: completed
type: feature
priority: normal
created_at: 2026-06-03T14:07:04Z
updated_at: 2026-06-03T14:13:25Z
sync:
    github:
        issue_number: "381"
        synced_at: "2026-06-03T14:16:59Z"
---

## Motivation

When xc-mcp tools are driven by an agent loop, every macOS app/simulator launch steals window focus, which is disruptive for interactive use and unhelpful in CI/snapshot runs.

Port the headless launch policy added in getsentry/XcodeBuildMCP#435 (commit `59d5ca3e`). They introduced `XCODEBUILDMCP_HEADLESS_LAUNCH=1` with a tiny `utils/focus-policy.ts` (~55 LOC) that:

- Rewrites `open <app>` → `open -g <app>` (background launch, no focus steal)
- Returns `null` for `open -a Simulator` calls so the GUI is skipped entirely; `simctl boot` alone is enough for `simctl`-driven automation.

Off by default — production MCP/CLI behavior unchanged.

## Tasks

- [x] Add `Sources/Core/FocusPolicy.swift` with:
  - [x] `isHeadlessLaunchMode()` reading `XC_MCP_HEADLESS_LAUNCH` (accept `1` / `true` case-insensitive)
  - [x] `openAppArgs(appPath:launchArgs:)` → inserts `-g` when headless
  - [x] `openSimulatorAppArgs(simulatorId:)` → returns `nil` when headless
- [x] Wire into call sites:
  - [x] `Sources/Tools/MacOS/LaunchMacAppTool.swift` — env forces `-g` regardless of `hide`
  - [x] `Sources/Tools/MacOS/BuildRunMacOSTool.swift` — routes through `FocusPolicy.openAppArgs`
  - [x] `Sources/Tools/Simulator/OpenSimTool.swift` — returns skip diagnostic when headless
- [x] `open_in_xcode` left untouched (not routed through FocusPolicy)
- [x] Tests for the policy helper (11 tests in `Tests/FocusPolicyTests.swift`)
- [x] README Environment Variables table updated

## Reference

- Upstream commit: https://github.com/getsentry/XcodeBuildMCP/commit/59d5ca3e
- Upstream file: `src/utils/focus-policy.ts` (55 LOC)
- Cited repo: getsentry/XcodeBuildMCP (already in .jig.yaml)

## Out of scope

The AXe tab-role fix from the same release window (#441, commit `8d501942`) is N/A — AXe is iOS-simulator-specific and xc-mcp's `InteractRunner` exposes raw AX role/subrole/roleDescription without a derived-role classification layer, so SwiftUI tab bars can already be matched via the existing role filter.



## Summary of Changes

- New `Sources/Core/FocusPolicy.swift` (~60 LOC) — public `isHeadlessLaunchMode()`, `openAppArgs()`, `openSimulatorAppArgs()`, all accepting an injectable environment for testability.
- `OpenSimTool` now returns `"Simulator.app launch skipped by XC_MCP_HEADLESS_LAUNCH"` instead of running `open`.
- `BuildRunMacOSTool` routes its launch through `FocusPolicy.openAppArgs`.
- `LaunchMacAppTool` emits `-g` when either the existing `hide` param is true or the env var is set.
- 11 unit tests in `Tests/FocusPolicyTests.swift` cover env parsing, arg construction, and the simulator-nil path.
- README gains an Environment Variables section documenting the var.

Full `swift build` clean. `FocusPolicyTests` all pass (11/11).

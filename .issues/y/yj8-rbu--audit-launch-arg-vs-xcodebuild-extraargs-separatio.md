---
# yj8-rbu
title: Audit launch-arg vs xcodebuild extraArgs separation
status: completed
type: task
priority: normal
created_at: 2026-05-09T15:20:55Z
updated_at: 2026-05-09T15:40:27Z
sync:
    github:
        issue_number: "317"
        synced_at: "2026-05-09T15:41:58Z"
---

XcodeBuildMCP PR #403 (commit b1188ec3, BREAKING) standardized their tool surface: `launchArgs` is the canonical parameter for app launch arguments (passed to the launched process), and `extraArgs` is scoped to xcodebuild / build-settings invocations. The motivation: with a single `args` parameter on build-and-run tools, app runtime arguments could leak into xcodebuild commands.

Audit our equivalent tool surface to confirm we don't have the same conflation:
- macOS build/run/launch tools (`build_run_macos`, `launch_mac_app`)
- Simulator build/run/launch tools
- Device build/run/launch tools
- Any `extraArgs`-style passthrough to `xcodebuild`

Source: https://github.com/getsentry/XcodeBuildMCP/pull/403

- [x] Grep for tool params named `args` / `extraArgs` / `launchArgs` across our build/run/launch tools
- [x] Verify launch-time args reach the launched process, not `xcodebuild`
- [x] If conflation exists, decide whether to introduce a separate `launchArgs` param (likely additive, no need for breaking change)



## Summary of Changes

No code change required — audit confirms our tool surface already keeps launch-time arguments and xcodebuild arguments cleanly separated.

Audit results:

| Tool | `args` param routes to | xcodebuild extra args |
|---|---|---|
| `BuildRunMacOSTool` | `open --args` (line 159–160) | from session helpers (`continueBuildingArgs` + `enableSanitizersArgs` + `buildSettingOverrides`) |
| `BuildDebugMacOSTool` | LLDB launch args | session helpers |
| `LaunchMacAppTool` | `open --args` | n/a (no build) |
| `LaunchAppSimTool` | `simctl launch … args:` | n/a |
| `LaunchAppLogsSimTool` | `simctl launch … args:` | n/a |
| `BuildRunSimTool` | (no `args` param exposed; only build) | session helpers |
| `TestDeviceTool` | (no `args` param) | session helpers |

The schema descriptions consistently document `args` as "Optional arguments to pass to the app." — there is no user-facing parameter that can leak into `xcodebuild`. xcodebuild additional arguments are constructed exclusively from narrowly-scoped session helpers (`continue_building`, `enable_sanitizers`, build-setting overrides), each with its own typed parameter.

XcodeBuildMCP's PR #403 was fixing a TypeScript-side conflation where a single `args` parameter on build-and-run tools was used for both launch and build. We never had that shape. No `launchArgs` rename is needed; no breaking change.

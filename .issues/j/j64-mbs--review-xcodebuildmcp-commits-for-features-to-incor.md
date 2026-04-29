---
# j64-mbs
title: Review XcodeBuildMCP commits for features to incorporate
status: completed
type: task
priority: normal
tags:
    - citation
created_at: 2026-04-29T04:37:02Z
updated_at: 2026-04-29T04:42:46Z
sync:
    github:
        issue_number: "290"
        synced_at: "2026-04-29T05:14:18Z"
---

Review commits from `getsentry/XcodeBuildMCP` (since `937b19d`, through `54837d4`) for features and fixes worth incorporating into xc-mcp. Each commit links to https://github.com/getsentry/XcodeBuildMCP/commit/<sha>.

## Themes to investigate first

- [x] **Workspace-scoped DerivedData** → follow-up `3ng-z0t`. We pass no `-derivedDataPath`, so concurrent xc-mcp sessions against the same clone race on incremental artifacts.
- [x] **Keyboard toggle simulator tools** → follow-up `elc-se4`. Useful for UI automation when text fields don't show the on-screen keyboard.
- [x] **Per-test timing in test results** → follow-up `zhd-brm`. `XCResultParser.TestDetail` already carries `duration`; `BuildResultFormatter` drops it.
- [x] **`XCODEBUILDMCP_CWD` env override** — deferred. We use PPID-scoped session files (`Sources/Core/SessionManager.swift:61`) and absolute paths in tool args, so cwd-at-spawn matters less. Revisit if a host reports project-discovery breakage.
- [x] **`session-profile` persisted flag** — N/A. Our session tools return plain text; we don't expose JSON schemas for structured output.
- [x] **Multi-platform `build_device`** — already at parity. `Sources/Tools/Device/BuildDeviceTool.swift:82-83` builds with `generic/platform=\(connectedDevice.platform)` resolved from `devicectl`.
- [x] **Config path `~` expansion** → follow-up `eoa-eyv`. `PathUtility` and `SessionManager` don't expand `~` — passing `~/Developer/foo.xcodeproj` resolves to literal `<cwd>/~/Developer/foo.xcodeproj`.

## Bug fixes — check parity

- [x] `13bb282` — N/A. `Sources/Tools/Device/ListDevicesTool.swift` does not emit nextStep hints; nothing to fix.
- [x] `fb4e30a` — N/A (same as above).
- [x] `fd55726` — N/A. Sentry-specific xcode-ide bridge; we don't have an analogous component.

## Infra / tooling — review for ideas

- [x] `c2936ff` Warden — noted but not adopting. `getsentry/warden` is a paid GHA for PR review; we run reviews via Claude Code skills instead.
- [x] `4bd32e6` AGENTS.md — N/A. Our `CLAUDE.md` already covers build/architecture/conventions.
- [x] `911301e` manifests publish — N/A. No website manifest pipeline.

## Skipped (not actionable)

- `29f3290` deps bump (hono)
- `dedc509` ignore `.worktrees`
- `48dfc6c` remove orphan `swift-testing-event-parser`
- `27a4df7`, `567aeb4` changelog cleanup

## Output

For each theme, decide: incorporate, defer (create follow-up issue), or skip. Note xc-mcp file paths to modify in the relevant follow-up issues.


## Summary of Changes

Reviewed 37 commits from `getsentry/XcodeBuildMCP` (range `937b19d..54837d4`). Created 4 follow-up issues for actionable work:

- `3ng-z0t` (feature) — workspace-scope DerivedData
- `elc-se4` (feature) — keyboard toggle simulator tools
- `zhd-brm` (feature) — per-test durations in output
- `eoa-eyv` (bug) — expand `~` in user-supplied paths

The rest were either already at parity (`build_device` multi-platform), N/A (Sentry-specific bridge, AGENTS.md sync, manifest pipeline, list_devices nextStep hints we don't emit), or deferred (`XCODEBUILDMCP_CWD` override, Warden review action).

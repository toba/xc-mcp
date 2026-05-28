---
# 7w1-p2h
title: 'test_sim/test() streams no progress (onProgress: nil) — long cold builds look hung'
status: completed
type: bug
priority: normal
created_at: 2026-05-28T01:27:51Z
updated_at: 2026-05-28T01:34:38Z
sync:
    github:
        issue_number: "353"
        synced_at: "2026-05-28T01:40:41Z"
---

Follow-up to ycq-rdc (process-group kill landed; wall-clock timeout now fires reliably). Remaining unaddressed ask from that issue: *surface periodic progress so the caller can distinguish 'slow but alive' from 'hung'.*

## Symptom
A cold iOS `test_sim` run gives the agent ZERO output for minutes and is indistinguishable from a hang, so the client cancels it manually. Observed today on Thesis fw5-27h/akn-6oq: first `test_sim` ran ~6m with no feedback and was cancelled. After warming the build with `build_sim` (which DOES stream progress), the identical `test_sim` returned in well under the timeout and passed 535/535.

## Root cause
`XcodebuildRunner.test(...)` (XcodebuildRunner.swift:513-517) calls `run(arguments:…, onProgress: nil)`. The build (`build`) path threads an `onProgress` callback through to `build_sim`/build tools, but the test path hardcodes nil, so `TestSimTool`/`TestToolHelper.runAndFormat` have no per-line hook to emit progress. The stream readers in `runProcess` already receive the chunks (they update `lastOutputTime`) — they just drop the text on the test path.

## Asks
- Thread an `onProgress` (or periodic heartbeat) through `runner.test(...)` so test runs surface build/test progress like `build_sim` does — at minimum a periodic 'still building: <last target/action>' heartbeat.
- Alternatively, have test tools auto-detect a cold build and emit a one-line 'cold build, this may take several minutes' notice up front.

## Workaround (documented in Thesis akn-6oq)
Run `build_sim` first to warm the scheme, THEN `test_sim` — the test invocation then returns promptly.

Reported from Thesis fw5-27h / akn-6oq iOS-test bring-up.


## Summary of Changes

Threaded an `onProgress` callback through the entire test path so cold `xcodebuild test` runs surface per-line progress via `notifications/progress`, matching `swift_package_test` / `build_debug_macos`.

- `XcodebuildRunner.test(...)` now accepts `onProgress` and passes it to `run(...)` (was hardcoded `nil`).
- `TestToolHelper.runAndFormat(...)` accepts `onProgress` and forwards it to `runner.test`.
- `TestSimTool`/`TestMacOSTool`/`TestDeviceTool.execute(...)` accept an optional `onProgress` and thread it to `runAndFormat`.
- All four servers (monolithic `xc-mcp`, `xc-simulator`, `xc-build`, `xc-device`) wrap their `test_sim`/`test_macos`/`test_device` handlers in a `ProgressReporter` when the client supplies a `progressToken`, exactly like the existing `swift_package_test` path.

Net effect: a cold test run now streams the latest build/test line every ~2s, so 'slow but alive' is distinguishable from 'hung'. ProgressReporterTests (12) pass; full build green.

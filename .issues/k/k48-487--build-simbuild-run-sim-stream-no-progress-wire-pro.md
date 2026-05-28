---
# k48-487
title: build_sim/build_run_sim stream no progress — wire ProgressReporter like test_sim
status: completed
type: bug
priority: normal
created_at: 2026-05-28T01:37:06Z
updated_at: 2026-05-28T01:38:55Z
sync:
    github:
        issue_number: "352"
        synced_at: "2026-05-28T01:40:41Z"
---

Follow-up to 7w1-p2h. While fixing the test path we found build_sim (and build_run_sim) don't wire a ProgressReporter either — BuildSimTool.execute / BuildRunSimTool.execute take no onProgress and the server handlers call them bare. A cold build_sim therefore also streams zero progress. Apply the same pattern: thread onProgress through the build tools and wrap the server handlers in a ProgressReporter when a progressToken is present.


## Summary of Changes

Applied the 7w1-p2h pattern to the simulator build path so cold `build_sim` / `build_run_sim` runs stream progress instead of looking hung.

- `BuildSimTool.execute` and `BuildRunSimTool.execute` now accept an optional `onProgress` and forward it to `xcodebuildRunner.build(...)` (which already supported the callback).
- `build_sim` / `build_run_sim` handlers in both `xc-mcp` and `xc-simulator` wrap the call in a `ProgressReporter` when the client supplies a `progressToken`.

Build green; ProgressReporterTests (12) pass.

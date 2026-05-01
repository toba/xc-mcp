---
# 5t9-9ll
title: Surface elapsed wall-clock time in MCP build tool results
status: ready
type: feature
priority: normal
created_at: 2026-04-30T19:37:58Z
updated_at: 2026-04-30T19:37:58Z
sync:
    github:
        issue_number: "302"
        synced_at: "2026-05-01T04:16:25Z"
---

The `mcp__xc-swift__swift_package_build` and `mcp__xc-swift__swift_package_test` tools currently return text like `Build succeeded (debug configuration)` or `Tests passed (15 passed, 0 failed, 0.031s)` (test runtime only — no build time).

For iteration tuning and benchmarking, callers (agents and humans) need to know **total wall-clock time including build**. Today, getting that requires wrapping every call with bash:

```
date +%s.%N > /tmp/t0
# call the build tool
t1=$(date +%s.%N); python3 -c "print(f'{$t1 - $t0:.2f}s')"
```

Which is awkward and adds clutter to transcripts.

## Proposed change

Append `(N.Ns elapsed)` to the success line of:

- `swift_package_build`: `Build succeeded (debug configuration, 12.4s)`
- `swift_package_test`: `Tests passed (15 passed, 0 failed, 12.4s build, 0.031s tests)`
- `swift_package_clean`: `Package cleaned successfully (0.5s)`

The tool already wraps the underlying invocation, so capturing start/end timestamps around that call is trivial.

## Bonus: per-target breakdown

Even more useful for performance work: parse the build log for per-target timing (the underlying tool emits build progress lines with target names) and surface a top-N slowest targets list. Optional but high value when an agent is investigating slow builds.

## Why now

A user iterating on a Swiftiomatic fix ran 5+ benchmark iterations and had to manually wrap each MCP call with bash timing. The data was the whole point of the work, but extracting it was tedious. Surfacing elapsed time directly would make future build-perf analysis (and routine "is this build getting slower?" sanity checks) trivially observable.

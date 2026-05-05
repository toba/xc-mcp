---
# xgh-fc1
title: 'SwiftSymbolsTool: 60s subprocess timeout fires before test''s 2-min limit on CI'
status: completed
type: bug
priority: normal
created_at: 2026-05-05T23:12:38Z
updated_at: 2026-05-05T23:47:06Z
sync:
    github:
        issue_number: "310"
        synced_at: "2026-05-05T23:47:21Z"
---

Three SwiftSymbolsToolTests time out on the GitHub Actions macOS runner (consistent across runs 210 and 211 on main):

- `Extract Testing module and find Trait protocol` (SwiftSymbolsToolTests.swift:44)
- `Query with no matches returns empty result` (SwiftSymbolsToolTests.swift:62)
- `Kind filter restricts to protocols only` (SwiftSymbolsToolTests.swift:80)

All three throw `.timeout(duration: 60.0 seconds)`. The tests declare `.timeLimit(.minutes(2))`, but the timeout actually comes from the tool itself: `Sources/Tools/Discovery/SwiftSymbolsTool.swift:108` hardcodes a 60s timeout on `xcrun swift-symbolgraph-extract`.

The comment at lines 41-42 notes "Testing module is fast (~18s)" locally, but the CI runner with cold SDK caches exceeds 60s.

CI runs:
- https://github.com/toba/xc-mcp/actions/runs/25386556212
- https://github.com/toba/xc-mcp/actions/runs/25328608423

## Fix candidates
- [x] Add an in-process `SymbolGraphCache` actor keyed by `(module, platform, sdk, triple)` so the three tests share one extraction instead of racing three concurrent extractions on a cold CI cache


## Summary of Changes

Root cause was contention, not raw latency: swift-testing runs the three `Testing`-module tests in parallel, and each invocation of `SwiftSymbolsTool` shelled out to `swift-symbolgraph-extract` independently. Three concurrent extractions racing for CPU/disk on the GitHub Actions runner pushed all of them past the tool's 60s subprocess timeout.

Fix: introduced `SymbolGraphCache` (private actor in `Sources/Tools/Discovery/SwiftSymbolsTool.swift`) that memoizes decoded `SymbolGraph` values by `(module, platform, sdkPath, triple)` and de-dupes inflight extractions through an `inflight: [String: Task<SymbolGraph, Error>]` map. Now the first caller pays the extraction cost; concurrent callers for the same key await the same `Task`, and subsequent calls hit the in-memory cache. Also benefits production sessions that query the same module twice.

Left the 60s subprocess timeout unchanged — with cache + inflight dedup, only one extraction can run per (module, platform, sdk, triple) tuple, so it no longer competes with itself.

Local verification: `SwiftSymbolsToolTests` passes 6/6 in 0.4s. CI verification pending push.

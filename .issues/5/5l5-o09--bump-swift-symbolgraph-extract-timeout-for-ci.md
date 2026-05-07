---
# 5l5-o09
title: Bump swift-symbolgraph-extract timeout for CI
status: completed
type: bug
priority: normal
created_at: 2026-05-07T18:51:07Z
updated_at: 2026-05-07T18:52:18Z
sync:
    github:
        issue_number: "314"
        synced_at: "2026-05-07T18:52:23Z"
---

CI run 25510565014 failed: three SwiftSymbolsToolTests integration tests timed out at exactly 63.974s — the SymbolGraphCache dedup is working (single shared inflight task), but `swift-symbolgraph-extract` for the `Testing` module exceeded the 60s subprocess timeout on a cold GitHub Actions runner.

- [x] Bump `Sources/Tools/Discovery/SwiftSymbolsTool.swift` subprocess timeout 60s → 180s
- [x] Raise `Tests/SwiftSymbolsToolTests.swift` `.timeLimit` 2min → 5min on the three integration tests



## Summary of Changes

- `Sources/Tools/Discovery/SwiftSymbolsTool.swift`: `swift-symbolgraph-extract` subprocess timeout 60s → 180s.
- `Tests/SwiftSymbolsToolTests.swift`: three integration tests' `.timeLimit` 2min → 5min.

The `SymbolGraphCache` dedup from #310 was working as designed (all three tests timed out at exactly 63.974s, indicating one shared inflight `Task`), but the underlying extraction itself exceeded the 60s subprocess timeout on a cold GitHub Actions runner.

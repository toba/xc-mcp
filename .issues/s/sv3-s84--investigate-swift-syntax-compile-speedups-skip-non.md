---
# sv3-s84
title: Investigate swift-syntax compile speedups (skip-non-inlinable, prebuilt modules)
status: ready
type: task
priority: low
created_at: 2026-04-30T16:03:15Z
updated_at: 2026-04-30T16:03:15Z
sync:
    github:
        issue_number: "299"
        synced_at: "2026-04-30T16:11:23Z"
---

Try `-Xswiftc -experimental-skip-non-inlinable-function-bodies`, pre-compiled swift-syntax modules, and other SwiftPM tricks to shave time off swift-syntax-heavy dependency graphs. Known to be fragile across Swift toolchain versions; gate any adoption behind an env var and benchmark before/after on swiftiomatic.

Follow-up to tc2-9jv.

---
# m1o-n2c
title: Replace Date() timing with ContinuousClock
status: completed
type: task
priority: normal
created_at: 2026-02-19T20:12:58Z
updated_at: 2026-02-19T20:22:57Z
sync:
    github:
        issue_number: "86"
        synced_at: "2026-02-19T20:42:41Z"
---

XcodebuildRunner.swift uses Date() for timing which can go backwards (NTP).

- [ ] Line 103: let startTime = Date() → ContinuousClock.now
- [ ] Line 107: Date().timeIntervalSince(startTime) → duration comparison
- [ ] Lines 413-420: LastOutputTime class Date() → ContinuousClock.Instant
- [ ] Verify tests pass

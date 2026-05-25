---
# cku-1oz
title: Flaky high-frequency symbol advisor warning due to Set iteration order
status: completed
type: bug
priority: normal
created_at: 2026-05-25T22:55:49Z
updated_at: 2026-05-25T22:56:20Z
sync:
    github:
        issue_number: "341"
        synced_at: "2026-05-25T22:57:34Z"
---

BreakpointConditionAdvisor.matchedHighFrequencySymbol used highFrequencySymbols.first(where: exact-or-substring) over a Set, so for 'sqlite3_prepare_v2' the substring entry 'sqlite3_prepare' could be returned first depending on nondeterministic Set order. CI (run 229) hit this. Fix: prefer exact match, fall back to longest contained match deterministically.

## Summary of Changes

Sources/Core/BreakpointConditionAdvisor.swift: matchedHighFrequencySymbol now checks for an exact match first, then falls back to the longest contained symbol. This removes dependence on Set iteration order (Swift randomizes the hash seed per process), which is why CI run 229 failed while local runs passed. Verified with BreakpointConditionAdvisorTests (8 passed).

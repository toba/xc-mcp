---
# qnp-a6f
title: loosen LLDBCommandTimeoutTests reader-leak test budget for CI
status: completed
type: bug
priority: normal
created_at: 2026-06-02T19:27:17Z
updated_at: 2026-06-02T19:27:17Z
sync:
    github:
        issue_number: "372"
        synced_at: "2026-06-02T19:27:23Z"
---

The `a tolerated short timeout does not leak the reader and the next command succeeds` test (regression for t57-a7q) flaked on CI: the next `sendCommand("version")` ran past its 3s budget on the 5s-commandTimeout session under parallel test load, where cooperative-pool starvation delays the response without any actual reader leak.

The leak signal is binary — a leaked reader silently swallows the response and forces the call to time out at the full commandTimeout — so widening the budget to 15s on a 30s-commandTimeout session still catches the regression while absorbing CI variance. Same pattern applied previously to WaitForProcessExitTests.

## Summary of Changes

- Tests/LLDBCommandTimeoutTests.swift: bumped session `commandTimeout` from 5s → 30s and the "reader didn't leak" budget from 3s → 15s.

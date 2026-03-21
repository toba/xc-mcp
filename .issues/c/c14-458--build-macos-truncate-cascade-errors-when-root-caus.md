---
# c14-458
title: 'build_macos: truncate cascade errors when root cause is a script phase failure'
status: completed
type: feature
priority: normal
tags:
    - enhancement
created_at: 2026-03-21T19:29:13Z
updated_at: 2026-03-21T19:33:46Z
sync:
    github:
        issue_number: "230"
        synced_at: "2026-03-21T19:43:50Z"
---

## Context

When a build fails due to a script phase error (e.g. `PhaseScriptExecution failed`), the output includes dozens of cascade errors like "Unable to find module dependency: 'GRDB'" from every downstream target. These are noise — the root cause is the single script phase failure, and the cascade errors are uninformative.

In a real session, a `buildAmalgamation.sh` failure produced 88 errors, but only 1 was meaningful:
```
Error: Unknown option --srcdir
Command PhaseScriptExecution failed with a nonzero exit code
```

The other 87 errors were all "Unable to find module dependency" and `lstat ... No such file or directory` cascades.

## Proposal

When `errors_only` is true and a `PhaseScriptExecution` failure is detected:
1. Show the script phase error prominently
2. Collapse or truncate the cascade errors (e.g. "... and 87 cascade errors from downstream targets")
3. Still show the full count in the summary

This would make build failures much faster to diagnose, especially for LLM agents that need to identify the root cause without human pattern matching.

## Summary of Changes

- `BuildResultFormatter.formatBuildResult` now detects when a `PhaseScriptExecution` failure is present among errors
- Cascade errors (matching known patterns like "Unable to find module dependency", "No such file or directory", etc.) are partitioned out and collapsed into a single summary line: "(+N cascade errors from downstream targets hidden)"
- Root-cause errors (the script phase failure itself and any non-cascade errors) are shown prominently
- When no script phase failure is present, all errors are shown as before (no behavior change)
- Added 3 tests: cascade truncation with multiple errors, no truncation without script phase failure, singular form

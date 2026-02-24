---
# 95q-yzq
title: Evaluate Sentry XcodeBuildMCP session defaults hardening
status: ready
type: task
priority: normal
created_at: 2026-02-24T18:29:37Z
updated_at: 2026-02-24T18:29:37Z
sync:
    github:
        issue_number: "94"
        synced_at: "2026-02-24T18:57:42Z"
---

getsentry/XcodeBuildMCP made several session defaults improvements in v2.1.0. Evaluate whether any patterns are worth adopting in our SessionManager.

## Commits to review

- `7356c4c` — Support persisting custom env vars in session defaults
- `506b5f5` — Deep merge env
- `b90c0a6` — Harden env deep-merge and prevent mutation leaks
- `fc5a184` — Harden store, schema validation, and clear semantics

## Tasks

- [ ] Read the relevant Sentry source files (session-store.ts, session_set_defaults.ts, session_clear_defaults.ts)
- [ ] Compare with our SessionManager.swift approach
- [ ] Determine if env persistence, deep-merge, or schema validation gaps exist in our implementation
- [ ] Create follow-up issues if any changes are warranted, or close as not applicable

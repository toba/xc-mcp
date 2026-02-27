---
# 3nn-1yf
title: Add custom env vars to session defaults
status: ready
type: feature
priority: normal
created_at: 2026-02-27T17:41:04Z
updated_at: 2026-02-27T17:41:04Z
sync:
    github:
        issue_number: "148"
        synced_at: "2026-02-27T17:47:47Z"
---

Allow users to set custom environment variables in session defaults that get merged into build/run/test commands.

Inspired by getsentry/XcodeBuildMCP's implementation (7356c4c, fc5a184) which supports persistent custom env vars with deep merge semantics.

## Tasks

- [ ] Add `env: [String: String]` field to session defaults
- [ ] Support `set_session_defaults(env: {...})` with deep merge (new keys add, existing keys update)
- [ ] Pass session env vars through to xcodebuild, swift, and launch commands
- [ ] `clear_session_defaults` resets env along with everything else
- [ ] Add tests

## Use cases

- Setting `DYLD_` vars for debugging
- Custom build flags via env (e.g. `ENABLE_FEATURE_X=1`)
- CI-specific env passthrough

## References

- getsentry/XcodeBuildMCP@7356c4c (initial impl)
- getsentry/XcodeBuildMCP@fc5a184 (hardened store + schema validation)

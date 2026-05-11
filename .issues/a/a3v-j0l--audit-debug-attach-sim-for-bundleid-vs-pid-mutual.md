---
# a3v-j0l
title: Audit debug_attach_sim for bundleId vs pid mutual-exclusion bug from session defaults
status: completed
type: bug
priority: normal
created_at: 2026-05-11T22:27:21Z
updated_at: 2026-05-11T22:43:07Z
sync:
    github:
        issue_number: "321"
        synced_at: "2026-05-11T22:43:40Z"
---

Upstream XcodeBuildMCP #411 (sentry/XcodeBuildMCP@edfa19f) fixed a bug where `debug_attach_sim` called with an explicit `pid` would trip mutual-exclusion validation because inherited `bundleId` values from session defaults were still being applied. Fix: drop inherited bundleId when explicit pid is provided. Keep explicit bundleId + explicit pid rejected (still mutually exclusive when both explicit). Cover tool-local exclusive keys in the session-aware merge path.

## Tasks

- [x] Review `Sources/Tools/Debug/DebugAttachSimTool.swift` (or equivalent) for how bundleId/pid args are merged with session defaults
- [x] Reproduce: set session default bundleId, then call debug_attach_sim with explicit pid — does mutual-exclusion validation fire incorrectly?
- [x] If buggy: drop inherited bundleId when explicit pid is supplied (and vice versa)
- [x] Ensure explicit bundleId + explicit pid still rejected
- [x] Add regression tests covering session-default vs explicit-arg precedence for mutually exclusive keys



## Summary of Changes

**Upstream bug does not apply to xc-mcp** — no code change required to `DebugAttachSimTool`.

Findings from the audit:

1. **`SessionManager` does not store `bundle_id` as a session default.** It only stores `simulatorUDID` (plus other project/workspace/scheme/configuration/destination fields). The upstream defect required a `bundleId` session default to be inherited and re-applied; that mechanism doesn't exist here.
2. **`DebugAttachSimTool` has no mutual-exclusion validation between `pid` and `bundle_id`.** The current precedence is:
   - explicit `pid` → use directly, skip bundle_id resolution entirely
   - else `bundle_id` (+ optional simulator) → resolve PID via pgrep / LLDB session
   - else → throw `invalidParams("Either bundle_id or pid is required")`
   Passing both is silently allowed; `pid` wins. There is no validation path that could falsely reject the explicit-pid + inherited-bundleId case.
3. **`bundle_id` does pass through to `LLDBSessionManager.registerBundleId(_:forPID:)` after a successful attach** — which is correct behavior (lets later debug calls map back from bundle_id to PID).

Added `Tests/DebugAttachSimToolTests.swift` (3 tests) locking in the contract:
- schema declares `bundle_id`, `simulator`, `pid` all as optional (none in `required`)
- `execute([:])` throws `invalidParams` mentioning bundle_id or pid
- `SessionManager` exposes no `bundleId`-like field (Mirror-based check; if a future change adds one, this test will fail and force a revisit of the precedence logic)

All 3 new tests pass. Full suite: 1129 passed, 2 pre-existing flakes (`build alamofire mac OS`, `build swift format mac OS` — external-project download timeouts in `BuildRunScreenshotIntegrationTests`, unrelated).

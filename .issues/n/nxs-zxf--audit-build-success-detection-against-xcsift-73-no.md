---
# nxs-zxf
title: 'Audit build success-detection against xcsift #73 (no false greens on truncated/killed streams)'
status: completed
type: task
priority: high
created_at: 2026-06-17T00:33:20Z
updated_at: 2026-06-17T00:48:18Z
sync:
    github:
        issue_number: "389"
        synced_at: "2026-06-17T00:56:07Z"
---

## Context

Upstream citation `ldomaradzki/xcsift` landed commit `0a4b128` — **fix: never report failed or truncated builds as success (#73)** — which tracks our `Sources/Core/BuildOutputParser.swift`, `BuildOutputModels.swift`, `BuildResultFormatter.swift`. Same bug class as our recent `41f3993` (xc-build archive reporting success while writing no .xcarchive).

Their findings:
- **False greens from truncated/killed streams.** Through a pipe, the parser can't see xcodebuild's exit code, so a `Killed: 9` (OOM) run that ends before any terminal marker reported `status: success`. Fix: require *positive evidence* of success (a terminal marker or actually-passed tests), else emit a new `incomplete` status.
- **Status/count disagreement.** `status: success` with `failed_tests: 1` (and the mirror) — they reconciled status against the aggregate failed-test count so the two can never disagree.
- **New terminal markers recognized:** `** TEST SUCCEEDED **`, `** TEST EXECUTE SUCCEEDED **`, `Build succeeded in …`, `Build failed after …`, plus xcbeautify's rewritten `Build Succeeded` / `Test Succeeded`.

Refs: https://github.com/ldomaradzki/xcsift/pull/73

## Tasks

- [x] Audit `BuildOutputParser`/`BuildResultFormatter`/`checkBuildSuccess` — do we infer success from the *absence* of failure markers, or require a positive terminal marker?
- [x] Check the truncated/killed-stream case (process killed before `** BUILD SUCCEEDED **`) — confirm we don't report success
- [x] Verify build status can never disagree with the parsed failed-test count
- [x] Confirm we detect the full set of terminal markers (TEST SUCCEEDED, TEST EXECUTE SUCCEEDED, Build succeeded/failed in/after …, xcbeautify variants)
- [x] Add regression tests for OOM/truncation and status/count reconciliation if gaps found



## Summary of Changes

Audited and fixed `BuildOutputParser` success-detection, porting the fix from xcsift #73. Both audited bugs were present and are now fixed.

**Bug 1 — false greens from truncated/killed streams.** `status` defaulted to `success` whenever no failure markers were seen, so a build/test killed before any terminal marker (e.g. OOM `Killed: 9`) reported success. Because every consumer gates on `result.succeeded || status == "success"`, this false green survived even a non-zero exit code (`checkBuildSuccess` returned as success). Fixed by requiring **positive evidence** of success — a terminal success marker or actually-passed tests — and introducing a new `incomplete` status for the truncated/killed case.

**Bug 2 — status/count disagreement.** `hasActualFailures` ignored the aggregate `totalFailed`, so a failure appearing only in the `Executed N tests, with M failures` line (never as an individual `Test Case … failed`) yielded `status: success` with `summary.failedTests > 0`. Fixed by folding `totalFailed > 0` into the failure check so `status` can never disagree with the reported count.

**Expanded terminal-marker recognition.** Added `** TEST SUCCEEDED **`, `** TEST EXECUTE SUCCEEDED **`, generalized `Build succeeded (…)` / `Build failed (…)` (parenthesized-time form), and xcbeautify's `Build Succeeded` / `Test Succeeded` / `Build Failed` / `Test Failed`. The parser now tracks `sawTerminalSuccessMarker` / `sawTerminalFailureMarker`, and the fast-path filter lets these lines through.

**Consumer-facing.** `BuildResultFormatter` header renders `Build incomplete`; `ErrorExtraction.checkBuildSuccess` throws a distinct message for `incomplete` explaining the build was likely killed/truncated.

### Files
- `Sources/Core/BuildOutputParser.swift` — marker state, new status model, expanded marker parsing, fast-path filter
- `Sources/Core/BuildResultFormatter.swift` — `incomplete` header
- `Sources/Core/ErrorExtraction.swift` — `incomplete` message in `checkBuildSuccess`
- `Tests/BuildOutputParserTests.swift` — 8 new regression tests (truncated build/test → incomplete, aggregate-count reconciliation, TEST SUCCEEDED/TEST EXECUTE SUCCEEDED/xcbeautify markers, real-fixture truncation); `Parse warnings` snippet gained a realistic terminal marker

### Verification
Full suite green: 1346 passed, 0 failed. Refs: https://github.com/ldomaradzki/xcsift/pull/73

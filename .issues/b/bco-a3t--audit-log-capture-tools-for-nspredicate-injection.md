---
# bco-a3t
title: Audit log-capture tools for NSPredicate injection via bundleId/subsystem
status: completed
type: bug
priority: high
created_at: 2026-05-11T22:27:21Z
updated_at: 2026-05-11T22:31:24Z
sync:
    github:
        issue_number: "322"
        synced_at: "2026-05-11T22:43:41Z"
---

Upstream XcodeBuildMCP #407 (sentry/XcodeBuildMCP@6bfff99) hardened their log capture against predicate injection: user-supplied bundleId and custom subsystem filter values are interpolated into NSPredicate strings passed to `log stream --predicate`. A bundleId containing double quotes or other special characters could inject arbitrary predicate syntax (information disclosure from other subsystems, or DoS via malformed predicates). Upstream added strict allowlist validation (alphanumeric, dots, hyphens, underscores) before any string interpolation.

CWE-78 / predicate injection mitigation.

## Tasks

- [x] Audit `Sources/Core/SimctlRunner.swift`, `Sources/Tools/Logging/`, and any tool that builds `log stream --predicate` / `log show --predicate` strings
- [x] Identify all user-supplied values interpolated into predicate strings (bundleId, subsystem, category, process)
- [x] Add strict allowlist validation (alphanumeric, dots, hyphens, underscores) before interpolation
- [x] Reject invalid values early with a descriptive error
- [x] Add tests covering quote/special-char injection attempts



## Summary of Changes

Added `PredicateFilterValidator` (`Sources/Core/PredicateFilterValidator.swift`) — a strict allowlist (alphanumeric, `.`, `-`, `_`) for user-supplied values that get interpolated into NSPredicate strings. Throws typed `PredicateFilterError` that converts to `MCPError.invalidParams`.

Applied at every vulnerable call site:
- `StartSimLogCapTool` — `bundle_id` (was `processImagePath CONTAINS "..."`)
- `StartMacLogCapTool` — `bundle_id`, `process_name`, `subsystem`
- `ShowMacLogTool` — `bundle_id`, `process_name`, `subsystem`
- `LaunchAppLogsSimTool` — `bundle_id` (was `subsystem CONTAINS '...'`)

Validation runs inside the `do/catch` blocks so the typed error flows through `error.asMCPError()`. The explicit `predicate` parameter remains as the escape hatch for callers who legitimately need raw NSPredicate syntax.

The `mdfind` injection at `StartMacLogCapTool.resolveExecutableName` (`kMDItemCFBundleIdentifier == '\(bundleId)'`) is now also covered transitively, since both callers validate bundle_id before invoking it.

Added `Tests/PredicateFilterValidatorTests.swift` — 10 tests covering well-formed values, empty/quote/whitespace/operator rejection, error→MCPError conversion, and end-to-end injection rejection through each tool's `execute()`. All pass.

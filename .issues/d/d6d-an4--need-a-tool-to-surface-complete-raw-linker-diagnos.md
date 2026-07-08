---
# d6d-an4
title: Need a tool to surface complete raw linker diagnostics from an xc-mcp build
status: completed
type: feature
priority: normal
created_at: 2026-07-08T15:36:53Z
updated_at: 2026-07-08T22:06:48Z
sync:
    github:
        issue_number: "414"
        synced_at: "2026-07-08T22:07:45Z"
---

Diagnosing linker failures through xc-mcp is currently blind because the full ld diagnostic is unrecoverable via sanctioned tools.

## Concrete blocker

Debugging a duplicate-symbol Release link failure in the Thesis project, I needed the verbatim ld block:

    duplicate symbol '_relinkableLibraryClasses' in:
        <path A>
        <path B>

That two-file list IS the entire diagnosis (which frameworks collide). But:
1. build_macos / test_macos report only the symbol name (Undefined symbol X) — truncated, AND mislabeled (real error is duplicate, not undefined; see fm2-cax).
2. build_macos leaves an EMPTY (0-byte) .xcactivitylog in DerivedData/Logs/Build, so the raw log cannot be recovered by hand. (test_macos does write a full activitylog, inconsistently.)
3. show_build_log returns a stale/unrelated log (compile warnings from an earlier build), not the failing link.
4. The raw build CLI is policy-blocked in this environment (hooks forbid invoking it directly), so there is no fallback.

Net: an agent cannot see WHICH objects/frameworks a duplicate or undefined symbol comes from — the one fact needed to fix it.

## Ask (any one unblocks)

- A raw_output/verbatim option on build_macos/test_macos returning the complete unparsed clang/ld stderr for failed link steps, OR
- A dedicated get_link_diagnostics / show_last_build_raw tool that dumps the full linker invocation + error for the most recent xc-mcp build, OR
- Ensure build_macos always persists a complete, readable activity log (never 0 bytes) for manual extraction.

Minimum viable: for duplicate-symbol and undefined-symbol errors, capture and return the full multi-line block including every source path ld lists (the '... in:' files and the 'referenced from:' objects) and the failing target.

## Summary of Changes

Added `show_last_build_raw` — a tool returning the complete, unparsed clang/ld output of the most recent build/test run, so an agent can recover the verbatim linker diagnostic (full `Undefined symbols …` / `duplicate symbol … in:` blocks with every source path) when the parsed summary truncates or mislabels it.

### New files
- `Sources/Core/BuildOutput/RawBuildLog.swift` — persists the raw combined stdout/stderr of the most recent `xcodebuild` build/test to a PPID-scoped file (`/tmp/xc-mcp-last-build-{ppid}.log`, overridable via `XC_MCP_LAST_BUILD`) with a JSON metadata sidecar. Best-effort; empty captures never clobber a prior real one.
- `Sources/Core/BuildOutput/LinkerDiagnostics.swift` — extracts verbatim compiler/linker diagnostic regions (anchors on error:/ld:/clang: error/Undefined symbol/duplicate symbol/framework|library-not-found/`, referenced from:`, plus indented continuation and one leading-context line). Non-adjacent regions joined with an ellipsis; capped at 500 lines.
- `Sources/Tools/MacOS/ShowLastBuildRawTool.swift` — the `show_last_build_raw` tool. Defaults to extracted diagnostics; `full: true` dumps everything, `tail: N` the final N lines. Always prints the on-disk path as a last-resort fallback.

### Wiring
- `XcodebuildRunner.build()`/`test()` capture raw output at the single chokepoint — on both the nonzero-exit (BUILD FAILED) path and the timeout/stuck partial-output path. Covers macOS, simulator, and device scheme builds/tests; no build-time flag needed.
- Registered in `XcodeMCPServer` (monolithic) and `xc-build` focused server; added to `ServerToolDirectory` for cross-server hints.

### Tests
- `Tests/LinkerDiagnosticsTests.swift` (6) and `Tests/RawBuildLogTests.swift` (3) — all pass.

Unblocks via two of the three proposed paths: a dedicated tool AND guaranteed persistence of a complete, readable raw log (never 0 bytes).

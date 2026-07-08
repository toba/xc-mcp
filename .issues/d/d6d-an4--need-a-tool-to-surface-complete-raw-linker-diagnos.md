---
# d6d-an4
title: Need a tool to surface complete raw linker diagnostics from an xc-mcp build
status: ready
type: feature
priority: normal
created_at: 2026-07-08T15:36:53Z
updated_at: 2026-07-08T15:36:53Z
sync:
    github:
        issue_number: "414"
        synced_at: "2026-07-08T15:43:48Z"
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

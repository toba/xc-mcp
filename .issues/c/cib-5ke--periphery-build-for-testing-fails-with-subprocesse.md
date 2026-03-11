---
# cib-5ke
title: Periphery build-for-testing fails with SubprocessError; no build output surfaced
status: completed
type: bug
priority: normal
created_at: 2026-03-11T18:21:43Z
updated_at: 2026-03-11T18:25:39Z
sync:
    github:
        issue_number: "201"
        synced_at: "2026-03-11T18:26:28Z"
---

When running `detect_unused_code` with `fresh_scan: true` on the Thesis project, Periphery's internal `build-for-testing` step fails with `MCP error -32603: Internal error: The operation couldn't be completed. (Subprocess.SubprocessError error 1.)`

The underlying Periphery build fails because it uses its own DerivedData directory and some symbols (e.g. `ScaleDocumentFactory`) can't be found in scope. The regular Xcode build succeeds fine.

**Workaround**: Build the project first with `build_macos`, then run `detect_unused_code` with `skip_build: true`. This works but produces a stale index, causing `// periphery:ignore` annotations to not match line numbers (false `superfluousIgnoreCommand` reports).

**Expected**: The SubprocessError should surface the actual build failure output (stderr/stdout from Periphery CLI) so the user can diagnose the root cause.


## Summary of Changes

Fixed `asMCPError()` in `Sources/Core/MCPErrorConvertible.swift` to use `String(describing: self)` instead of `localizedDescription`. This ensures errors that conform to `CustomStringConvertible` (like `Subprocess.SubprocessError`) surface their detailed `description` instead of the generic Foundation format ("The operation couldn't be completed. (Subprocess.SubprocessError error 1.)"). Affects all 80+ tool catch blocks that call `.asMCPError()`.

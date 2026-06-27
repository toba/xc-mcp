---
# dmz-7pj
title: Surface swift-frontend compiler crashes (not just 'Build failed (N warnings)')
status: ready
type: task
priority: normal
created_at: 2026-06-27T04:31:26Z
updated_at: 2026-06-27T04:31:26Z
sync:
    github:
        issue_number: "397"
        synced_at: "2026-06-27T16:53:27Z"
---

When the Swift frontend itself CRASHES during a build (SIGABRT/SIGSEGV, e.g. an IRGen `report_size_overflow` reabstraction-thunk bug), the build tools report only `Build failed (N warnings)` with **zero error lines**, and the xcactivitylog is written 0 bytes — giving an agent no actionable signal. `build_macos`, `diagnostics`, and `show_build_log` all hid the real cause; pinning it required manual forensics outside the MCP.

## What happened (real case)

Compiling a SwiftUI view crashed swift-frontend. Symptoms:
- `build_macos(errors_only:true)` → `Build failed (39 warnings)`, no error.
- `diagnostics` → same: only warnings.
- `show_build_log` → 'No non-empty build logs found' (0-byte .xcactivitylog).
- The per-file `.dia` contained only: `reproducer is available at: <swbuild.tmp.*/Data.noindex>`.
- The true cause was in `~/Library/Logs/DiagnosticReports/swift-frontend-*.ips` and in the frontend's own stderr: `Stack dump … While emitting IR SIL function "@$s…TR"` (a reabstraction-thunk IRGen crash).

## Tooling gaps / proposed improvements

1. **Detect frontend crashes.** When a build fails with no parsed errors AND a `.dia` contains 'reproducer is available' (or a child swift-frontend exited via signal), say so explicitly instead of 'Build failed (N warnings)'.
2. **Surface the crashing function.** Parse the matching `~/Library/Logs/DiagnosticReports/swift-frontend-*.ips` (crashing thread frames; the 'While emitting IR … SIL function "@…"' note) and the reproducer's `reproduce.sh`, and include the demangled symbol + primary-file path in the error.
3. **Empty-activity-log fallback.** When the .xcactivitylog is 0 bytes, fall back to scanning `.dia` files and DiagnosticReports rather than reporting 'no logs'.
4. **read_serialized_diagnostics robustness.** It shelled out to `c-index-test` which isn't in PATH on this machine (`unable to find utility 'c-index-test'`); it should degrade gracefully or use an in-process .dia reader.
5. **Optional:** a 'replay reproducer' helper that runs the frozen `reproduce.sh` and captures the frontend stderr banner.

## Context
Surfaced while fixing thesis issue 1nu-81z (a NodeStatus `Binding<Int>` setter became a `@Sendable @isolated(any) (Int)->()` value under NonisolatedNonsendingByDefault, hitting a Swift 6.3 IRGen overflow). Diagnosis took ~15 tool calls of manual nm/dia/ips forensics that the MCP could have short-circuited.

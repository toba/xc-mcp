---
# sv3-s84
title: Investigate swift-syntax compile speedups (skip-non-inlinable, prebuilt modules)
status: completed
type: task
priority: low
created_at: 2026-04-30T16:03:15Z
updated_at: 2026-04-30T17:03:23Z
sync:
    github:
        issue_number: "299"
        synced_at: "2026-04-30T17:20:52Z"
---

Try `-Xswiftc -experimental-skip-non-inlinable-function-bodies`, pre-compiled swift-syntax modules, and other SwiftPM tricks to shave time off swift-syntax-heavy dependency graphs. Known to be fragile across Swift toolchain versions; gate any adoption behind an env var and benchmark before/after on swiftiomatic.

Follow-up to tc2-9jv.

## Summary of Changes

Investigated `-experimental-skip-non-inlinable-function-bodies` as a swift-syntax compile speedup. Result: **~2% improvement on swiftiomatic, within noise. Not worth adopting by default.**

**Benchmark (cold compile, swiftiomatic with swift-syntax 603.0.1, Swift 6.3.1)**

| Configuration                                                                  | Real time | User CPU |
|--------------------------------------------------------------------------------|-----------|----------|
| `swift build -c debug` (baseline)                                              | 147.40s   | 938.55s  |
| `swift build -c debug -Xswiftc -experimental-skip-non-inlinable-function-bodies` | 144.09s   | 933.15s  |

**Likely reason for the small delta:** Swift 6.3.1's `--enable-experimental-prebuilts` is on by default and already pulls a prebuilt swift-syntax macros library. The remaining swiftiomatic compile time is dominated by the user code that *consumes* swift-syntax (so the bodies that would be skipped are mostly in user modules, not swift-syntax itself, and many of those bodies are required for type checking).

**What landed**

Rather than commit to a flag whose payoff is workload-dependent and may regress across toolchain versions, I added a generic env-var hook so users can opt in or experiment without code changes:

- `XC_MCP_SWIFT_EXTRA_ARGS` is read by `SwiftRunner.extraArgsFromEnvironment()` and appended to every `swift build` and `swift test` invocation. Whitespace-separated tokens (no quoting). Empty/unset → no behavior change.
- Implemented in `Sources/Core/SwiftRunner.swift`. Tested in `Tests/ProgressReporterTests.swift` (env var unset, env var set with two tokens).

Example:
```sh
export XC_MCP_SWIFT_EXTRA_ARGS="-Xswiftc -experimental-skip-non-inlinable-function-bodies"
```

**Other ideas not pursued**

- `--experimental-prebuilts` — already enabled by default in Swift 6.1+; nothing to do.
- Manually symlinking `.build/checkouts` across packages — covered by the separate follow-up `a68-g9s` (shared `.build`).
- `-experimental-skip-non-exportable-decls` — needs specific module structure (sees-no-impls); not generally applicable to app/tool packages.

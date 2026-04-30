---
# a68-g9s
title: Share built artifacts across packages via shared .build
status: scrapped
type: feature
priority: low
created_at: 2026-04-30T16:03:16Z
updated_at: 2026-04-30T17:05:14Z
sync:
    github:
        issue_number: "297"
        synced_at: "2026-04-30T17:20:52Z"
---

SwiftPM's global cache deduplicates *checkouts* but not built artifacts, so two packages depending on swift-syntax each compile it from scratch. Investigate symlinking `.build/artifacts` / `.build/<triple>/debug/ModuleCache` across known packages, or wiring `SWIFTPM_PACKAGE_CACHE_DIR` and a custom built-products cache. Risk: ABI/version mismatches between packages on different Swift versions.

Follow-up to tc2-9jv.

## Reasons for Scrapping

Investigated whether xc-mcp can share built swift-syntax artifacts across SwiftPM packages. Conclusion: **SwiftPM 6.1+ already handles the swift-syntax case for the macro use case via its prebuilts mechanism, and the remaining "share library builds across packages" problem is a much larger initiative (custom artifact cache with strict version/toolchain/triple/flag keying) than fits a follow-up.**

**What SwiftPM already does**

`--enable-experimental-prebuilts` (default ON in Swift 6.1+) downloads prebuilt swift-syntax modules from the `swiftlang/swift-syntax-prebuilts` GitHub artifact bundle and unpacks them into `<package>/.build/prebuilts/swift-syntax/<version>/`. Verified locally:

```
~/Library/Caches/org.swift.swiftpm/prebuilts/swift-syntax/
├── 600.0.1/
├── 601.0.1/
├── 602.0.0/
├── 603.0.0/
└── 603.0.1/swiftlang-6.3.1.1.2-macosx26.4-MacroSupport.zip   (26MB)
```

Total prebuilt cache: 151MB. Each package consuming swift-syntax for **macros** gets these for free, no recompile.

**Where the gap remains**

For packages that consume swift-syntax as a **library** (e.g., swiftiomatic, swift-format, swift-lint), prebuilts only cover the macro-support modules. The library targets (SwiftSyntax, SwiftParser, SwiftSyntaxBuilder, etc.) are still compiled from source — visible as the 44MB `.build/arm64-apple-macosx/debug/SwiftSyntax.build/` directory after a clean build. Two such packages each pay this compile cost independently.

**Why this is hard to share safely**

The brainstormed mechanisms in the original ticket — symlinking `.build/artifacts`, `.build/<triple>/debug/ModuleCache`, or wiring a custom built-products cache — all founder on:

1. **Toolchain skew**: `.swiftmodule` binary format is not stable across compiler builds. Sharing requires keying on the exact `swiftlang-x.y.z` revision.
2. **Compile-flag skew**: `-O`, `-enable-library-evolution`, `-strict-concurrency`, sanitizer flags, etc. all change the emitted module and object files. Two packages built with different SwiftSettings will produce mutually incompatible artifacts under the same source tree.
3. **Triple skew**: arm64 vs x86_64, macosx vs iossimulator, etc. The cache key must include the target triple.
4. **Dependency-graph skew**: Even if the swift-syntax checkout is identical, the *transitive* dep graph isn't. SwiftPM resolves and links modules in a graph-specific order; two packages may bring different versions of co-deps that change codegen.

A correct shared cache must hash on `(git-commit, toolchain-id, triple, configuration, swift-settings-hash, deps-graph-hash)`. That's essentially `sccache`/`bazel-cache` for SwiftPM — a real project, not a follow-up.

**What did land (durable)**

`XC_MCP_SWIFT_EXTRA_ARGS` (added under follow-up sv3-s84) lets a power user pass `--scratch-path /shared/path` if they explicitly want to experiment, without xc-mcp imposing it. That's the right level of intervention for an unsafe operation.

**Recommended next steps if revisited**

- Survey existing build-cache solutions for SwiftPM (sccache, bazel-rules-swift, swift-build's experimental remote cache).
- File a discussion on swift-evolution / forums.swift.org to gauge whether the SwiftPM team would accept upstream support for cross-package built-products caching with the necessary keying.
- Don't roll our own — the failure mode of a stale-cache hit is silent miscompilation.

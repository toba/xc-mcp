---
# hfa-7mx
title: 'Add build-optimization tools: benchmark_build, find_compile_hotspots, audit_build_settings'
status: completed
type: feature
priority: normal
created_at: 2026-07-26T06:29:35Z
updated_at: 2026-07-26T06:48:02Z
sync:
    github:
        issue_number: "435"
        synced_at: "2026-07-26T06:48:44Z"
---

Three deterministic build-performance tools, distilled from avanderlee.com's 'Xcode build optimization using 6 agent skills'. That kit is prompt-shells around the build CLI; we already own the *structural* half (diff_build_settings, list_build_phase_status, show_build_dependency_graph, list_run_script_phases, XCTest perf baselines). These three close the *timing/analysis* half without duplicating anything we have.

## Proposed tools

### 1. benchmark_build (biggest gap)
get_performance_metrics is XCTest measure() only — there is no build-*time* benchmark. Wrap the build with -showBuildTimingSummary, run N clean + N incremental builds (default 3/3), persist JSON to a .build-benchmark/ dir (reuse the SetPerformanceBaseline/ShowPerformanceBaselines storage pattern). Report clean vs incremental separately (they expose different problems: clean = module graph/target structure, incremental = script phases / cache invalidation). Support before/after diff against a stored baseline so 'apply a setting, re-benchmark' is one call.

### 2. find_compile_hotspots
Nothing does this today. Inject -stats-output-dir and/or -Xfrontend -warn-long-function-bodies=N -Xfrontend -warn-long-expression-type-checking=N into a build, then parse the emitted diagnostics/stats into a ranked list of slow-to-type-check functions/expressions and slow files. Read-only; the payoff for large Swift 6 codebases.

### 3. audit_build_settings
Turn the article's 'project-analyzer' skill into one read-only 'recommend' pass over resolved settings, flagging known incremental-build anti-patterns:
- Debug configuration using wholemodule
- DEBUG_INFORMATION_FORMAT=dwarf-with-dsym in Debug (should be dwarf)
- EAGER_LINKING off on multi-framework projects
- explicit modules / compilation caching off
- run-script phases with empty input/output paths — we can already see these via list_run_script_phases, so this check is nearly free and catches a real, common tax.

## Notes / provenance

- Validated against the Thesis project: its build *settings* were already optimal (Debug: incremental + -Onone + dwarf, explicit modules on), so audit_build_settings correctly returns near-empty there and the only Thesis finding was empty-I/O script phases — good real-world regression fixture for check #3.
- Scope each tool as read-only/advisory (no auto-apply); mirror the article's review-before-apply stance.
- Consider splitting into 3 child issues if this grows past a scoping doc.

## Summary of Changes

Added all three tools to both the monolithic `xc-mcp` server and the focused `xc-build` server.

- **`benchmark_build`** (`Sources/Tools/MacOS/BenchmarkBuildTool.swift`) — times N clean + N
  incremental (no-change) builds (default 3/3), reporting each series separately with mean/min/max/
  stddev plus a `-showBuildTimingSummary` phase breakdown. Persists results to a `.build-benchmark/`
  dir next to the project and diffs against a saved baseline when `compare_baseline` is set. All
  invocations are driven through `runner.run()` with an explicit scoped `-derivedDataPath` so the
  clean and incremental phases hit the same DerivedData (a `runner.clean()` would otherwise resolve a
  platform-unscoped path different from the destination-scoped build).
- **`find_compile_hotspots`** (`FindCompileHotspotsTool.swift`) — injects
  `-warn-long-function-bodies` / `-warn-long-expression-type-checking` via an
  `OTHER_SWIFT_FLAGS=$(inherited) …` override (preserving project flags), cleans by default so every
  file recompiles, and parses the timing warnings into a ranked list of slow declarations and
  costliest files. Read-only.
- **`audit_build_settings`** (`AuditBuildSettingsTool.swift`) — read-only pass over resolved settings
  flagging whole-module/optimization/dSYM/all-arch in Debug and explicit-modules/eager-linking when
  explicitly off, gated so Release configs aren't wrongly flagged. Also scans `.xcodeproj`
  run-script phases for empty output paths (always-out-of-date tax). Returns near-empty on a
  well-configured project.

Wiring: enum cases + workflow category + instantiation + registration + dispatch in
`XcodeMCPServer.swift` and `BuildMCPServer.swift`; names added to `ServerToolDirectory.buildTools`.
Tests in `Tests/BuildOptimizationToolTests.swift` (22 tests, all passing) cover the pure parsing/
stats/audit/formatting logic without spawning builds. Full package builds clean.

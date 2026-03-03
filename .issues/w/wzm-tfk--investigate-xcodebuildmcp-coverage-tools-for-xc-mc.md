---
# wzm-tfk
title: Investigate XcodeBuildMCP coverage tools for xc-mcp
status: completed
type: feature
priority: normal
created_at: 2026-03-03T18:22:41Z
updated_at: 2026-03-03T18:41:27Z
sync:
    github:
        issue_number: "168"
        synced_at: "2026-03-03T18:48:55Z"
---

XcodeBuildMCP added `get_coverage_report` and `get_file_coverage` tools that extract per-target and function-level coverage from xcresult bundles (7 commits by irangareddy, Feb 24-25).

## Investigation

- [x] Review their `get_coverage_report` implementation: per-target coverage from xcresult
- [x] Review their `get_file_coverage` implementation: function-level coverage and uncovered line ranges
- [x] Check how they invoke `xccov` and parse output
- [x] Compare with our existing `CoverageParser.swift` in Core
- [x] Determine if we should add similar tools to xc-build / xc-mcp

## Relevant upstream commits

- `41ac091` Add get_coverage_report tool
- `a1eaf64` Add get_file_coverage tool
- `751c88d` Add coverage tools to simulator, device, macos, and swift-package workflows
- `f4006a4` Fix missing Array.isArray guard on targets field
- `5a4d510` Validate xcresultPath exists before invoking xccov
- `97e7241` Inject filesystem into coverage tool handlers

## Source

getsentry/XcodeBuildMCP (cited repo)


## Findings

### XcodeBuildMCP approach

Two tools with drill-down UX:
1. **get_coverage_report** — runs `xcrun xccov view --report [--only-targets] --json <xcresultPath>`, returns per-target coverage sorted lowest-first. Optional `showFiles` param adds per-file breakdown. `nextStepParams` guides LLM to drill into files.
2. **get_file_coverage** — runs `xcrun xccov view --report --functions-for-file <file> --json <xcresultPath>` for function-level detail, plus optional `xcrun xccov view --archive --file <path> <xcresultPath>` for uncovered line ranges (gated behind `showLines=false` default for token economy).

Both handle two xccov JSON formats (flat array vs `{ targets: [...] }`) for Xcode version compat.

### Our existing infrastructure

- **CoverageParser.swift** already parses xcresult bundles via `xccov view --report --json` and SPM `.profraw` files
- Returns `CodeCoverage` struct with `lineCoverage` and per-file `FileCoverage` array
- **NOT exposed as a standalone tool** — only surfaced as a one-line summary (`Coverage: 72.3%`) in test result formatting
- Test tools accept `enable_code_coverage: true` but don’t return detailed data

### Gap analysis

We have the parsing infrastructure but lack:
1. **Dedicated coverage tools** — no way for LLM to query coverage independently of running tests
2. **Function-level coverage** — our parser only goes to file level, not function level
3. **Uncovered line ranges** — we don’t use `xccov view --archive` at all
4. **Target filtering** — no way to focus on a specific target

## Recommendation

Add two tools to the MacOS/Simulator/SwiftPackage categories:
1. `get_coverage_report` — target-level overview from xcresult, extend CoverageParser
2. `get_file_coverage` — function-level + optional line ranges, new xccov invocations

CoverageParser.swift already handles the target-level case. Function-level and archive parsing would be new code in CoverageParser or a new dedicated parser.


## Summary of Changes

Added `get_coverage_report` and `get_file_coverage` tools to xc-build, xc-swift, and monolithic xc-mcp servers.

### New files
- `Sources/Tools/MacOS/GetCoverageReportTool.swift` — per-target coverage from xcresult bundles
- `Sources/Tools/MacOS/GetFileCoverageTool.swift` — function-level coverage with optional uncovered line ranges
- `Tests/GetCoverageReportToolTests.swift` — 5 tests
- `Tests/GetFileCoverageToolTests.swift` — 4 tests

### Modified files
- `Sources/Core/BuildOutputModels.swift` — added TargetCoverage, CoverageReport, FunctionCoverage, FileFunctionCoverage, UncoveredRange structs
- `Sources/Core/CoverageParser.swift` — added parseCoverageReport, parseFunctionCoverage, parseUncoveredLines methods
- `Sources/Servers/Build/BuildMCPServer.swift` — registered both tools
- `Sources/Server/XcodeMCPServer.swift` — registered both tools
- `Sources/Servers/Swift/SwiftMCPServer.swift` — registered both tools
- `Tests/CoverageParserTests.swift` — added 9 tests for new parser methods

### Verification
- swift build: clean
- 26 tests pass (CoverageParser + GetCoverageReport + GetFileCoverage)
- swiftformat + swiftlint: no issues

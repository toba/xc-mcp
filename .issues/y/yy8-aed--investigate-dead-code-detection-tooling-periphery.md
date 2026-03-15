---
# yy8-aed
title: Investigate dead code detection tooling (Periphery or equivalent)
status: completed
type: feature
priority: normal
created_at: 2026-03-07T18:49:04Z
updated_at: 2026-03-15T16:37:18Z
sync:
    github:
        issue_number: "171"
        synced_at: "2026-03-15T16:56:53Z"
---

Investigate integrating [Periphery](https://github.com/peripheryapp/periphery) or building equivalent functionality to detect unused code in Swift projects.

## Scope

Single MCP tool wrapping Periphery CLI (v3.6.0, MIT license). Targets Swift 6.2+ projects only. Returns structured results an agent can consume — consistent with `swift_lint`, `swift_format`, and other xc-swift tools.

## Periphery CLI

Installed at `/opt/homebrew/bin/periphery`. Key flags:

| Flag | Purpose |
|------|---------|
| `--format json` | Structured output (array of result objects) |
| `--project <path>` | Xcode project (`.xcodeproj` / `.xcworkspace`) |
| `--schemes <schemes>` | Schemes to build and scan |
| `--quiet` | Suppress progress output, only emit results |
| `--disable-update-check` | Skip update check |
| `--retain-public` | Retain all public declarations (for library projects) |
| `--retain-objc-annotated` | Retain `@objc`/`@objcMembers` declarations |
| `--retain-codable-properties` | Retain Codable properties |
| `--exclude-targets` | Targets to exclude from indexing |
| `--report-exclude` | File globs to exclude from results |
| `--skip-build` | Skip build step (use existing index) |
| `--index-store-path` | Use pre-built index store (implies `--skip-build`) |
| `--relative-results` | Output paths relative to project root |
| `--strict` | Exit non-zero if any unused code found |
| `--config <path>` | Path to `.periphery.yml` config file |
| `--baseline <path>` | Filter results against a baseline |

### JSON output format

Each result is an object with:
```json
{
  "name": "unusedFunc()",
  "kind": "function.free",
  "hints": ["unused"],
  "accessibility": "internal",
  "location": "/path/to/file.swift:2:6",
  "modules": ["MyModule"],
  "ids": ["s:8MyModule10unusedFuncyyF"],
  "attributes": [],
  "modifiers": []
}
```

`hints` values include: `unused`, `assignOnlyProperty`, `redundantProtocol`, `redundantPublicAccessibility`, `redundantConformance`, `unusedImport`.

`kind` values include: `function.free`, `function.method.instance`, `function.method.static`, `struct`, `class`, `enum`, `protocol`, `var.instance`, `var.static`, `var.global`, `typealias`, `enumelement`, `import`.

## Tool design

**Name:** `detect_unused_code`

**Parameters:**
| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `package_path` | string | no | Swift package directory (uses session default if not specified) |
| `project` | string | no | Path to `.xcodeproj` or `.xcworkspace` (for Xcode projects) |
| `schemes` | string[] | no | Schemes to build and scan (required for Xcode projects) |
| `retain_public` | bool | no | Retain all public declarations (default false) |
| `skip_build` | bool | no | Skip build step, use existing index data (default false) |
| `exclude_targets` | string[] | no | Targets to exclude from indexing |
| `report_exclude` | string[] | no | File globs to exclude from results |

**Output format** (structured text, grouped by file):
```
23 unused declaration(s) found:

Sources/Core/OldHelper.swift
  12:6 function unusedFunc() [unused] (internal)
  45:8 struct LegacyModel [unused] (internal)

Sources/Tools/SomeTool.swift
  8:1 import UnusedModule [unusedImport]
  33:9 var debugFlag [assignOnlyProperty] (internal)
  67:17 public func helperMethod() [redundantPublicAccessibility] (public)
```

## Implementation plan

### 1. Create tool file

**File:** `Sources/Tools/SwiftPackage/DetectUnusedCodeTool.swift`

Pattern: follows `SwiftLintTool.swift` exactly.

- `Sendable` struct with `SessionManager` dependency
- `tool()` returns MCP `Tool` with schema
- `execute()` resolves paths, builds args, calls `ProcessResult.run()`, parses JSON, formats output
- Internal `Result` struct for parsed JSON objects
- Static `parseJSONOutput()` and `formatResults()` methods
- Uses `BinaryLocator.find("periphery")` to locate the executable
- Timeout: 600s (Periphery builds the project, can be slow)

### 2. Register in xc-swift focused server

**File:** `Sources/Servers/Swift/SwiftMCPServer.swift`

- Add `case detectUnusedCode = "detect_unused_code"` to `SwiftToolName` enum
- Instantiate `DetectUnusedCodeTool(sessionManager: sessionManager)`
- Add to `ListTools` handler
- Add switch case in `CallTool` handler

### 3. Register in monolithic server

**File:** `Sources/Server/XcodeMCPServer.swift`

- Add `case detectUnusedCode = "detect_unused_code"` to `ToolName` enum
- Add to `.swiftPackage` category in the category computed property
- Instantiate tool alongside other swift tools (~line 586)
- Add to tool list (~line 771)
- Add switch case in dispatch (~line 1122)

### 4. Add tests

**File:** `Tests/DetectUnusedCodeToolTests.swift`

- Test `parseJSONOutput()` with sample Periphery JSON
- Test `formatResults()` output structure
- Test empty results case
- Test various hint types (unused, unusedImport, redundantPublicAccessibility, assignOnlyProperty)

### 5. End-to-end verification

- Run against this project (`xc-mcp`) as a Swift package
- Run against thesis project as an Xcode project
- Verify output is agent-consumable and consistent with `swift_lint` format

## Files to modify

| File | Change |
|------|--------|
| `Sources/Tools/SwiftPackage/DetectUnusedCodeTool.swift` | **New** — tool implementation |
| `Sources/Servers/Swift/SwiftMCPServer.swift` | Add enum case + registration |
| `Sources/Server/XcodeMCPServer.swift` | Add enum case + registration |
| `Tests/DetectUnusedCodeToolTests.swift` | **New** — unit tests |


## Evaluation: incorporating Periphery's analysis code directly

Rather than wrapping the Periphery CLI or adding it as a Swift package dependency, this section evaluates copying the relevant source code into xc-mcp and owning it as native analysis capability.

### Periphery internals

Periphery (v3.6.0, MIT) is ~12–15K lines across these modules:

| Module | Purpose | Est. size |
|--------|---------|-----------|
| **PeripheryKit** | Core analysis library — graph construction, traversal, unused detection | ~4–6K lines |
| **SourceGraph** | Declaration graph data structures, edges, nodes | ~2–3K lines |
| **Indexer** | Reads Swift compiler's index store via libIndexStore C API | ~2–3K lines |
| **Shared** | Extensions, logging, file utilities | ~1–1.5K lines |
| **Frontend** | CLI, configuration, formatters | ~2–3K lines (not needed) |

### Dependencies Periphery brings

| Dependency | Already in xc-mcp? | Weight | Notes |
|------------|-------------------|--------|-------|
| **swift-syntax** (SwiftSyntax, SwiftParser) | No | Heavy (~50MB build artifacts) | Used for supplemental AST analysis beyond what index store provides |
| **swift-indexstore** | No | Light (thin C wrapper over libIndexStore) | Core dependency — reads compiler index data |
| **swift-system** (SystemPackage) | No | Light | File path operations |
| **swift-filename-matcher** | No | Light | Glob matching for exclude patterns |
| **AEXML** | No | Light | XIB/storyboard parsing (not needed for Swift-only analysis) |
| **ArgumentParser** | Yes | — | Already used by xc-mcp |

### How the analysis pipeline works

```
Build (xcodebuild/swift build)
  └─ generates index store at DerivedData/.../IndexStore/
       │
       ▼
SwiftIndexStore reads libIndexStore C API
  └─ extracts declarations, references, relationships
       │
       ▼
Graph construction
  └─ builds in-memory declaration graph (nodes = declarations, edges = references)
  └─ SwiftSyntax supplements with details not in index store
       │
       ▼
Graph mutation
  └─ marks entry points (@main, test cases, public API if --retain-public)
  └─ applies special rules (Codable, @objc, protocol conformances)
       │
       ▼
Traversal & analysis
  └─ walks graph from roots, marks reachable nodes
  └─ unreachable nodes = unused code
  └─ also detects: redundant public, unused imports, assign-only properties
```

### What would need to be copied (minimum viable)

For Swift package analysis with a pre-built index store:

1. **SwiftIndexStore wrapper** — thin C interop layer over libIndexStore (~500 lines)
2. **Graph data structures** — Declaration, Reference, SourceGraph types (~1–2K lines)
3. **Index store reader** — populates graph from index data (~1–2K lines)
4. **Analysis engine** — graph traversal, unused detection logic (~2–3K lines)
5. **Retained declaration rules** — Codable, @objc, protocol, test case retention (~500 lines)

**Total: ~5–8K lines of Swift** to copy and adapt.

**Not needed:**
- Frontend/CLI module
- Output formatters (we'd write our own MCP output)
- AEXML / XIB parsing (Swift-only scope)
- Bazel support
- Configuration file parsing (.periphery.yml)
- SwiftSyntax supplemental parsing (optional — index store alone covers ~90% of cases)

### Advantages of incorporating

| Advantage | Detail |
|-----------|--------|
| **No external binary dependency** | Users don't need `brew install periphery`; analysis ships with xc-mcp |
| **Tighter integration** | Can reuse xc-mcp's existing build artifacts and index store paths from `show_build_settings` |
| **Customizable analysis** | Can add xc-mcp–specific rules (e.g., detect unused MCP tools, unused Runner methods) |
| **Faster execution** | No process spawn overhead; analysis runs in-process |
| **Version control** | No risk of Periphery CLI version mismatches or breaking changes |
| **Smaller surface** | Only copy what's needed — skip Bazel, XIB, CLI, formatters |

### libIndexStore context

libIndexStore is an **LLVM component** that ships inside the Xcode toolchain (`libIndexStore.dylib` in the toolchain's `usr/lib/`). The Swift and Clang compilers both write index data during builds (the `IndexStore/` directory in DerivedData), and libIndexStore is the public C API to read that data back.

Why it's idiomatic for xc-mcp:

- xc-mcp already depends on the Xcode toolchain being present (xcodebuild, simctl, swift CLI)
- The index store is generated automatically by every `swift build` and `xcodebuild` invocation — no extra flags needed
- It's the same data that powers Xcode's "Jump to Definition", "Find All References", and code completion
- SourceKit-LSP (Apple's official Swift LSP) uses the same index store data
- It's public LLVM infrastructure, not a private/undocumented Xcode API

Reading index store data via libIndexStore is well within the same toolchain surface area that xc-mcp already uses — no more exotic than calling `xcodebuild` or `swift build`.

### Risks and costs

| Risk | Severity | Mitigation |
|------|----------|------------|
| **swift-syntax dependency** | High | SwiftSyntax adds ~50MB to build and significant compile time. Could skip it initially — index store alone handles ~90% of unused detection. Add later if precision matters. |
| **Maintenance burden** | Medium | Upstream Periphery evolves; incorporated code becomes our responsibility. MIT license allows this but we lose upstream fixes. |
| **libIndexStore stability** | Low | C API is stable across Xcode releases; SwiftIndexStore wrapper insulates from changes |
| **Index store availability** | Low | xc-mcp already builds projects via xcodebuild/swift build, which generate index stores by default |
| **Code volume** | Medium | 5–8K lines is substantial but well-contained in a single analysis module |

### Recommendation

**Phase 1: wrap the CLI** (current plan). Ship the `detect_unused_code` tool quickly by wrapping `periphery scan --format json`. This validates the tool's UX and output format with real users.

**Phase 2: evaluate incorporation**. If the tool proves valuable and the CLI dependency is friction (install requirement, version issues, process overhead), then incorporate the core analysis code:

1. Copy SwiftIndexStore + graph + analysis engine (~5–8K lines)
2. Skip SwiftSyntax initially (index-store-only analysis)
3. Add as a new `Sources/Core/UnusedCodeAnalyzer/` module
4. Replace CLI wrapper in `DetectUnusedCodeTool.swift` with direct analysis calls
5. Consider adding swift-syntax later for higher precision if needed

This phased approach ships value immediately while keeping the door open for deeper integration.


## Summary of Changes

Committed in v1.25.0:

1. **`detect_unused_code` tool** — wraps `periphery scan --format json`, registered in xc-swift and monolithic servers. Parses Periphery JSON output into structured text grouped by file, consistent with `swift_lint` output format. 10 unit tests.

2. **Subprocess teardown fix** — configured `PlatformOptions.teardownSequence` with graceful shutdown (SIGTERM → 5s → SIGKILL) in `ProcessResult.runSubprocess`. Prevents orphan child processes on MCP abort/timeout that were blocking subsequent builds/tests by holding the SPM build lock.

3. **`ServerToolDirectory` backfill** — added missing `swift_format`, `swift_lint`, `get_coverage_report`, `get_file_coverage` entries.

4. **swift-review skill** — added Subprocess teardown learning to §4 Structured Concurrency.

### Remaining

E2E testing against real projects (SPM package and Xcode project with schemes).

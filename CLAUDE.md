# xc-mcp

MCP server for Xcode development on macOS.

## Overview

This project provides an MCP server for Xcode project manipulation with build, test, and run capabilities. It uses:
- [tuist/xcodeproj](https://github.com/tuist/xcodeproj) for project file manipulation
- [modelcontextprotocol/swift-sdk](https://github.com/modelcontextprotocol/swift-sdk) for MCP functionality
- Native `xcodebuild`, `simctl`, and `devicectl` for build and device operations

## Architecture

- **Language**: Swift 6.2 (strict concurrency enabled)
- **Platform**: macOS 15+
- **Dependencies**: MCP Swift SDK (≥0.9.0), XcodeProj (≥9.7.2), ArgumentParser (≥1.7.0)

## Package Structure

```
xc-mcp/
├── Package.swift
├── Sources/
│   ├── CLI.swift                    # Entry point (monolithic server)
│   ├── Server/
│   │   └── XcodeMCPServer.swift     # Monolithic server with all tools
│   ├── Servers/                     # Focused servers (smaller tool surface)
│   │   ├── Build/                   # xc-build (21 tools)
│   │   ├── Debug/                   # xc-debug (31 tools)
│   │   ├── Device/                  # xc-device (12 tools)
│   │   ├── Project/                 # xc-project (40 tools)
│   │   ├── Simulator/               # xc-simulator (29 tools)
│   │   ├── Strings/                 # xc-strings (24 tools)
│   │   └── Swift/                   # xc-swift (12 tools)
│   ├── Core/                        # Shared utilities (69 files), grouped by concern
│   │   ├── Runners/                 # Subprocess wrappers (xcodebuild, simctl, devicectl, lldb, swift, interact, xctrace) + ProcessResult
│   │   ├── BuildOutput/             # Build/test/coverage/crash output parsing & formatting
│   │   ├── ProjectFile/             # pbxproj/scheme/test-plan editing (PBXProj*, SafeProjectWrite, Scheme*)
│   │   ├── Interaction/             # UI automation helpers (focus, sim input, window capture, interact session)
│   │   ├── Locators/                # Path/binary/PID/DerivedData/PIF-cache resolution
│   │   ├── MCP/                     # MCP protocol plumbing (errors, progress, annotations, tool directory, arg extraction, next-step hints)
│   │   ├── Testing/                 # Test discovery/diagnostics helpers
│   │   ├── Session/                 # Session/workflow state + build guard + Xcode state reader
│   │   ├── AppBundle/               # App-bundle staging & inspection (preparer, codesign, icon manifest)
│   │   ├── XCStrings/               # String-catalog parsing/encoding (+ Models/)
│   │   └── *.swift                  # Cross-cutting singletons (XCMCPCore, ElapsedFormatting, MachineMetadata, BreakpointConditionAdvisor, PackageResolvedParser)
│   ├── Tools/                       # 168 tools across 14 categories
│   │   ├── Project/                 # 44 project manipulation tools
│   │   ├── XCStrings/               # 24 localization/string catalog tools
│   │   ├── Simulator/               # 18 simulator tools
│   │   ├── Debug/                   # 19 LLDB debug tools
│   │   ├── MacOS/                   # 10 macOS build tools
│   │   ├── Interact/                # 8 macOS UI automation (accessibility)
│   │   ├── UIAutomation/            # 8 simulator UI automation tools
│   │   ├── Device/                  # 7 device tools
│   │   ├── SwiftPackage/            # 9 Swift Package Manager tools
│   │   ├── Discovery/               # 5 project discovery tools
│   │   ├── Session/                 # 5 session management tools
│   │   ├── Logging/                 # 4 log capture tools
│   │   ├── Utility/                 # 4 utility tools
│   │   └── Instruments/             # 3 Xcode Instruments tools
│   └── Documentation.docc/          # DocC documentation
├── Tests/                           # 506 tests (swift-testing)
├── fixtures/                        # Test fixtures (open source repos)
├── scripts/                         # Build/utility scripts
└── CLAUDE.md
```

## Executables

The project builds 8 executables — one monolithic server and 7 focused servers:

| Executable | Tools | Use case |
|------------|-------|----------|
| `xc-mcp` | 148 | Full server (~50K tokens) |
| `xc-project` | 42 | Project file manipulation |
| `xc-simulator` | 29 | Simulator + UI automation |
| `xc-debug` | 31 | LLDB debugging + macOS UI automation |
| `xc-build` | 21 | Build, test, run |
| `xc-device` | 12 | Physical device management |
| `xc-swift` | 12 | SPM + Swift operations |
| `xc-strings` | 24 | Localization/string catalogs |

Focused servers reduce token overhead for clients that only need specific capabilities.

## Building and Running

```bash
# Build
swift build

# Run the monolithic MCP server
swift run xc-mcp

# Run a focused server
swift run xc-debug

# Run tests
swift test
```

## Issue Tracking

- **Create an issue before starting work**: `jig todo create "title" -t <type> -s in-progress`
- **Mark completed when done**: `jig todo update <id> -s completed`
- The `/commit` skill generates changelog entries from completed issues — if no issue exists, the work won't appear in the changelog.
- **Never commit automatically** — wait for the user to say `/commit` or explicitly ask to commit.

## Testing Rules

- **Use `swift_package_test`** (MCP tool) for running tests — never `swift test` via bash.
- **Filter to affected tests** when verifying a specific fix: `swift_package_test(filter: "TestClassName")`.
- If an MCP tool call is aborted, **do not retry it in a loop**. Diagnose why it was aborted first.

## Test Harness

`test-debug.sh` is a bash harness for testing the xc-debug MCP server end-to-end via JSON-RPC over pipes.

```bash
# Build and launch app under LLDB (stopped at entry)
./test-debug.sh <project_path> <scheme>

# Full workflow: build, launch, enable view borders, take screenshot
./test-debug.sh <project_path> <scheme> screenshot

# Example with thesis project
./test-debug.sh /Users/jason/Developer/toba/thesis/Thesis.xcodeproj Standard screenshot
```

Modes:
- `build` (default) — builds and launches under LLDB, stopped at entry
- `screenshot` — builds, launches, continues, interrupts, enables view borders via LLDB, continues, then takes a screenshot via ScreenCaptureKit

The harness manages an MCP server process lifecycle (named pipe for stdin, temp files for stdout/stderr), sends JSON-RPC initialize + tool calls, and extracts results. Server stderr is saved to `/tmp/xc-debug-last-stderr.log` for post-mortem debugging.

## Skills

### build-review

Xcode build system knowledge for injected targets (via XcodeProj). Reference files:

| File | Topic |
|------|-------|
| `SKILL.md` | Required build settings, failure modes table, diagnostic commands |
| `references/debug-dylib.md` | ENABLE_DEBUG_DYLIB mechanics and known issues |
| `references/mergeable-libraries.md` | Mergeable library internals, _relinkableLibraryClasses |
| `references/new-linker.md` | ld_prime timeline, ld_classic removal |
| `references/swift-driver.md` | Compilation modes and optimization levels |
| `references/swift-syntax-preview.md` | Alternative #Preview extraction via swift-syntax |

## Development Notes

- Each tool is a separate Swift file organized by category
- Tools follow a consistent pattern with `tool()` and `execute()` methods
- XcodeProj library handles .xcodeproj file manipulation
- Runner utilities in `Sources/Core/Runners/` wrap command-line tools (xcodebuild, simctl, devicectl, lldb, swift, xctrace, accessibility)
- **Testing**: swift-testing framework (506 tests)
- **Swift 6.2**: Strict concurrency enabled (`swift-tools-version: 6.2`)
- **Formatting**: `sm` (swiftiomatic from `../swiftiomatic`) before committing

## MCP Protocol Compliance

These rules are specific to building MCP servers and aren't covered by the generic `/swift` skill. Violating them causes the client (Claude Code) to tear down the stdio pipe — the disconnect symptom in `0xp-xz6` / `ive-jzc`.

- **Never respond to a cancelled request.** The [cancellation spec](https://modelcontextprotocol.io/specification/2025-11-25/basic/utilities/cancellation) requires the server to skip *all* responses (success and error) once `notifications/cancelled` arrives. Sending one is a protocol violation that Claude Code treats as fatal.
- **Catch-all error wrappers must rethrow `CancellationError` unchanged.** `Sources/Core/MCP/MCPErrorConvertible.swift::asMCPError()` is the chokepoint — it's `throws` and rethrows cancellation so the SDK's `catch is CancellationError` arm fires. Tool code uses `throw try error.asMCPError()`. Don't reintroduce a non-throwing variant.
- **Ignore SIGPIPE process-wide.** `Sources/CLI.swift` installs `signal(SIGPIPE, SIG_IGN)` in the multicall entry point. A stale `notifications/progress` write after the client half-closes the pipe must surface as `EPIPE` (swallowable), not a fatal signal.
- **Retire progress reporters synchronously on cancel.** `ProgressReporter.stream` cancels the poll task from `onCancel`, not just from `defer`, so no notification fires for a token the client has abandoned.
- **Spawn subprocesses in their own process group and SIGKILL the group on cancel.** See `ProcessResult.runSubprocess` — without this, SPM build plugin grandchildren hold the pipes open and the server appears hung.

## Swift Code Quality Standards

These standards apply to all code changes. Run `/swift` periodically to check for regressions.

### Concurrency

- All async code uses structured concurrency (async/await, TaskGroup, actors) — no completion handlers or GCD
- Use `@concurrent` for CPU-intensive async functions that should run off the caller's actor
- Use `sending` when values cross isolation boundaries
- Prefer actors over classes with locks for shared mutable state
- Use `Task.detached` only when `@concurrent` is insufficient

### Error Handling

- Use typed throws (`throws(ErrorType)`) where a function throws a single error type
- Keep error enums focused — one per domain, not one per file

### Code Duplication

- Runner utilities in `Sources/Core/Runners/` exist to eliminate duplication of process execution patterns — use them
- Extract shared logic into Core when the same pattern appears in 2+ tools
- Use generics to consolidate functions that differ only in types

### Performance

- Avoid `Data.dropFirst()` / `Data.prefix()` in loops (quadratic copies) — use index-based iteration
- Pre-allocate collections with `reserveCapacity` when final size is known
- Use `EmptyCollection()` and `CollectionOfOne(x)` instead of `[]` and `[x]` for parameters typed as `some Collection`/`some Sequence`
- Prefer `ContinuousClock.now` over `Date()` for timing/benchmarks

### Swift 6.2 Idioms

- Use `InlineArray<N, T>` for fixed-size buffers instead of tuples
- Use `Span` / `RawSpan` instead of `UnsafeBufferPointer` when deployment target allows (macOS 26.0+)
- Mark hot public generic functions `@inlinable` in library targets
- Use isolated conformances instead of `nonisolated` workarounds for `@MainActor` types

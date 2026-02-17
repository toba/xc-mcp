# xc-mcp

MCP server for Xcode development on macOS.

## Overview

This project provides an MCP server for Xcode project manipulation with build, test, and run capabilities. It uses:
- [tuist/xcodeproj](https://github.com/tuist/xcodeproj) for project file manipulation
- [modelcontextprotocol/swift-sdk](https://github.com/modelcontextprotocol/swift-sdk) for MCP functionality
- Native `xcodebuild`, `simctl`, and `devicectl` for build and device operations

## Architecture

- **Language**: Swift 6
- **Platform**: macOS 15+
- **Dependencies**: MCP Swift SDK, XcodeProj, ArgumentParser

## Package Structure

```
xc-mcp/
├── Package.swift
├── Sources/
│   ├── CLI.swift                    # Entry point
│   ├── Server/
│   │   ├── XcodeMCPServer.swift     # Main server with tool registry
│   │   └── SessionManager.swift     # Session state management
│   ├── Tools/
│   │   ├── Project/                 # 23 project manipulation tools
│   │   ├── Session/                 # 3 session management tools
│   │   ├── Simulator/               # 17 simulator tools
│   │   ├── Device/                  # 7 device tools
│   │   ├── MacOS/                   # 8 macOS build tools
│   │   ├── Discovery/               # 5 project discovery tools
│   │   ├── Logging/                 # 4 log capture tools
│   │   ├── Debug/                   # 17 LLDB debug tools
│   │   ├── UIAutomation/            # 7 UI automation tools
│   │   ├── SwiftPackage/            # 6 Swift Package Manager tools
│   │   └── Utility/                 # 4 utility tools
│   └── Utilities/
│       ├── PathUtility.swift
│       ├── XcodebuildRunner.swift
│       ├── SimctlRunner.swift
│       ├── DeviceCtlRunner.swift
│       ├── LLDBRunner.swift
│       └── SwiftRunner.swift
├── Tests/                           # Unit tests (315 tests)
└── CLAUDE.md
```

## Building and Running

```bash
# Build
swift build

# Run the MCP server
swift run xc-mcp

# Run tests
swift test
```

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
- Runner utilities wrap command-line tools (xcodebuild, simctl, devicectl, lldb, swift)
- **Testing**: swift-testing framework (310 tests)
- **Swift 6**: Strict concurrency enabled
- **Formatting**: `swift format -r -i .` then `swiftlint` before committing

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
│   │   ├── MacOS/                   # 6 macOS build tools
│   │   ├── Discovery/               # 5 project discovery tools
│   │   ├── Logging/                 # 4 log capture tools
│   │   ├── Debug/                   # 8 LLDB debug tools
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
├── Tests/                           # Unit tests (310 tests)
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

## Development Notes

- Each tool is a separate Swift file organized by category
- Tools follow a consistent pattern with `tool()` and `execute()` methods
- XcodeProj library handles .xcodeproj file manipulation
- Runner utilities wrap command-line tools (xcodebuild, simctl, devicectl, lldb, swift)
- **Testing**: swift-testing framework (310 tests)
- **Swift 6**: Strict concurrency enabled
- **Formatting**: `swift format -r -i .` then `swiftlint` before committing

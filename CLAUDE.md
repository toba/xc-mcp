# xcode-mcp-server

A comprehensive Model Context Protocol (MCP) server for Xcode development on macOS.

## Overview

This project provides a unified MCP server that combines Xcode project manipulation with full build, test, and run capabilities. It leverages:
- [tuist/xcodeproj](https://github.com/tuist/xcodeproj) for project file manipulation
- [modelcontextprotocol/swift-sdk](https://github.com/modelcontextprotocol/swift-sdk) for MCP functionality
- Native `xcodebuild`, `simctl`, and `devicectl` for build and device operations

## Architecture

- **Language**: Swift
- **Platform**: macOS 13+
- **Dependencies**:
  - ModelContextProtocol (MCP Swift SDK)
  - XcodeProj (Xcode project manipulation)

## Package Structure

```
xcode-mcp-server/
├── Package.swift
├── Sources/
│   ├── XcodeMCP/                    # Library target
│   │   ├── Server/
│   │   │   ├── XcodeMCPServer.swift    # Main server with tool registry
│   │   │   └── SessionManager.swift     # Session state management
│   │   ├── Tools/
│   │   │   ├── Project/                 # 23 project manipulation tools
│   │   │   ├── Session/                 # 3 session management tools
│   │   │   ├── Simulator/               # 17 simulator tools
│   │   │   ├── Device/                  # 7 device tools
│   │   │   ├── MacOS/                   # 6 macOS build tools
│   │   │   ├── Discovery/               # 5 project discovery tools
│   │   │   ├── Logging/                 # 4 log capture tools
│   │   │   ├── Debug/                   # 8 LLDB debug tools
│   │   │   ├── UIAutomation/            # 7 UI automation tools
│   │   │   ├── SwiftPackage/            # 6 Swift Package Manager tools
│   │   │   └── Utility/                 # 4 utility tools
│   │   └── Utilities/
│   │       ├── PathUtility.swift
│   │       ├── XcodebuildRunner.swift
│   │       ├── SimctlRunner.swift
│   │       ├── DeviceCtlRunner.swift
│   │       ├── LLDBRunner.swift
│   │       └── SwiftRunner.swift
│   └── xcode-mcp-server/            # Executable target
│       └── main.swift
├── Tests/
│   └── XcodeMCPTests/               # Test target
│       └── [tool tests]
└── CLAUDE.md
```

### Targets

- **XcodeMCP** (Library): Core functionality and MCP tools (93 tools)
- **xcode-mcp-server** (Executable): Command-line interface
- **XcodeMCPTests** (Test): Unit tests using swift-testing framework

## Tool Categories

### Session Management (3 tools)
- `set_session_defaults` - Set default project, scheme, simulator, device
- `show_session_defaults` - Show current session defaults
- `clear_session_defaults` - Clear all session defaults

### Project Management (23 tools)
- Project creation, file/target management, build settings, dependencies, app extensions

### Simulator (17 tools)
- List, boot, build, run, test, record video, set location/appearance, UI automation

### Device (7 tools)
- List devices, build, install, run, test on physical devices

### macOS (6 tools)
- Build, run, test macOS applications

### Discovery (5 tools)
- Discover projects, list schemes, show build settings, get bundle IDs

### Logging (4 tools)
- Capture simulator and device logs

### Debug (8 tools)
- LLDB integration: attach, breakpoints, stack, variables, commands

### UI Automation (7 tools)
- Tap, swipe, type, press keys/buttons, screenshot

### Swift Package Manager (6 tools)
- Build, test, run, clean, list dependencies

### Utilities (4 tools)
- Clean build products, doctor diagnostics, scaffold iOS/macOS projects

## Building and Running

```bash
# Build the project
swift build

# Run the MCP server
swift run xcode-mcp-server

# Run tests
swift test
```

## Development Notes

- Each tool is implemented as a separate Swift file organized by category
- Tools follow a consistent pattern with `tool()` and `execute()` methods
- XcodeProj library handles .xcodeproj file manipulation
- Runner utilities wrap command-line tools (xcodebuild, simctl, devicectl, lldb, swift)
- **Testing**: All tests use swift-testing framework (166 tests)
- **Swift 6**: Strict concurrency enabled
- **Formatting**: Execute `swift format -r -i .` before committing

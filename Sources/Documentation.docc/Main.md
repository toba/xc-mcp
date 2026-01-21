# ``xc_mcp``

MCP server for Xcode development on macOS.

## Overview

xc-mcp is a Model Context Protocol (MCP) server that provides comprehensive tools for Xcode project manipulation, building, testing, and device management. It enables AI assistants and other MCP clients to interact with Xcode projects programmatically.

The server uses:
- [tuist/xcodeproj](https://github.com/tuist/xcodeproj) for project file manipulation
- [modelcontextprotocol/swift-sdk](https://github.com/modelcontextprotocol/swift-sdk) for MCP functionality
- Native `xcodebuild`, `simctl`, and `devicectl` for build and device operations

## Getting Started

### Running the Server

```bash
# Build and run
swift build
swift run xc-mcp

# Run with a specific base path
swift run xc-mcp /path/to/projects

# Enable verbose logging
swift run xc-mcp --verbose
```

### MCP Client Configuration

Add xc-mcp to your MCP client configuration:

```json
{
  "mcpServers": {
    "xcode": {
      "command": "/path/to/xc-mcp",
      "args": ["/path/to/projects"]
    }
  }
}
```

## Tool Categories

The server exposes over 90 tools organized into functional categories:

### Project Tools

Tools for manipulating Xcode project files (.xcodeproj):

- Create new projects
- Add/remove files and targets
- Manage build settings and configurations
- Add Swift packages and frameworks
- Create groups and manage project structure

### Simulator Tools

Tools for iOS/tvOS/watchOS Simulator operations:

- List and boot simulators
- Build and install apps
- Launch and terminate apps
- Record video and take screenshots
- Set location and appearance

### Device Tools

Tools for physical device operations:

- List connected devices
- Build for device
- Install and launch apps
- Run tests on device

### macOS Tools

Tools for macOS application development:

- Build macOS apps
- Launch and terminate apps
- Run tests

### Debug Tools

Tools for LLDB debugging:

- Attach to processes
- Set and manage breakpoints
- Inspect stack traces and variables
- Execute LLDB commands

### UI Automation Tools

Tools for simulator UI interaction:

- Tap, swipe, and long press
- Type text and press keys
- Press hardware buttons
- Take screenshots

### Swift Package Tools

Tools for Swift Package Manager:

- Build packages
- Run tests
- Execute package products
- Manage dependencies

### Utility Tools

Additional utility tools:

- Clean build artifacts
- Scaffold new projects
- Doctor command for environment verification

## Session Management

The server maintains session state to reduce repetitive parameter passing. Use the session tools to set defaults:

- `set_session_defaults`: Configure default project, scheme, simulator, and device
- `show_session_defaults`: View current session state
- `clear_session_defaults`: Reset session state

Once defaults are set, tools will use them automatically when parameters are not explicitly provided.

## Topics

### Essentials

- ``XcodeMCPServer``
- ``XcodeMCPServerCLI``
- ``SessionManager``

### Utilities

- ``PathUtility``
- ``XcodebuildRunner``
- ``SimctlRunner``
- ``DeviceCtlRunner``
- ``LLDBRunner``
- ``SwiftRunner``

### Result Types

- ``XcodebuildResult``
- ``SimctlResult``
- ``DeviceCtlResult``
- ``LLDBResult``
- ``SwiftResult``

### Data Types

- ``SimulatorDevice``
- ``ConnectedDevice``
- ``ToolName``

### Errors

- ``PathError``
- ``SimctlError``
- ``DeviceCtlError``
- ``LLDBError``

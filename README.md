# xcode-mcp-server

![GitHub Workflow Status (with event)](https://img.shields.io/github/actions/workflow/status/giginet/xcodeproj-mcp-server/tests.yml?style=flat-square&logo=github)
![Swift 6.1](https://img.shields.io/badge/Swift-6.1-FA7343?logo=swift&style=flat-square)
[![Xcode 16.4](https://img.shields.io/badge/Xcode-16.4-16C5032a?style=flat-square&logo=xcode&link=https%3A%2F%2Fdeveloper.apple.com%2Fxcode%2F)](https://developer.apple.com/xcode/)
[![SwiftPM](https://img.shields.io/badge/SwiftPM-compatible-green?logo=swift&style=flat-square)](https://swift.org/package-manager/)
![Platforms](https://img.shields.io/badge/Platform-macOS-lightgray?logo=apple&style=flat-square)
[![License](https://img.shields.io/badge/License-MIT-darkgray?style=flat-square)
](https://github.com/giginet/xcodeproj-mcp-server/blob/main/LICENSE.md)

A comprehensive Model Context Protocol (MCP) server for Xcode development on macOS. Build, test, run, and debug iOS, macOS, watchOS, and tvOS apps on simulators and physical devices with full project manipulation capabilities.

![Adding Post Build Phase for all targets](Documentation/demo.png)

## Overview

xcode-mcp-server is a unified MCP server that combines Xcode project manipulation with full build, test, and run capabilities. It leverages:
- [tuist/xcodeproj](https://github.com/tuist/xcodeproj) for reliable project file manipulation
- [swift-sdk](https://github.com/modelcontextprotocol/swift-sdk) for MCP implementation
- Native `xcodebuild`, `simctl`, and `devicectl` for build and device operations

This server enables AI assistants and other MCP clients to:
- Create, scaffold, and manage Xcode projects
- Build and run apps on simulators and physical devices
- Run tests and capture logs
- Control simulator state, appearance, and location
- Debug apps with LLDB integration
- Automate UI interactions on simulators
- Work with Swift Package Manager projects

## Features

### Project Management (23 tools)
- Create and scaffold iOS/macOS projects
- Manage targets, files, groups, and build configurations
- Add dependencies, frameworks, and Swift packages
- Configure app extensions (widgets, notification services, etc.)

### Build & Run (19 tools)
- Build for simulator, device, and macOS
- Run and stop apps
- Test on simulators and devices
- Clean build products

### Simulator Management (17 tools)
- List, boot, and manage simulators
- Install and launch apps
- Record video and capture screenshots
- Set location, appearance, and status bar
- UI automation (tap, swipe, type, etc.)

### Device Management (7 tools)
- List connected devices
- Build, install, and run on physical devices
- Run tests on devices

### Debug (8 tools)
- Attach/detach debugger
- Set and remove breakpoints
- View stack traces and variables
- Execute LLDB commands

### Logging (4 tools)
- Capture simulator and device logs
- Start and stop log sessions

### Swift Package Manager (6 tools)
- Build, test, and run Swift packages
- List dependencies
- Clean build artifacts

### Session Management (3 tools)
- Set default project, scheme, and device
- Persist settings across tool calls

## How to set up for Claude Desktop and Claude Code

### Prerequisites

- Docker
- macOS (for running Xcode projects)

### Installation using Docker

Pull the pre-built Docker image from GitHub Container Registry:

```bash
docker pull ghcr.io/giginet/xcodeproj-mcp-server
```

### Configuration for Claude Code

```bash
claude mcp add xcodeproj -- docker run --pull=always --rm -i -v $PWD:/workspace ghcr.io/giginet/xcodeproj-mcp-server:latest /workspace
```

We need to mount the current working directory (`$PWD`) to `/workspace` inside the container. This allows the server to access your Xcode projects.

#### Recommended settings

Enabling `ENABLE_TOOL_SEARCH` in `.claude/settings.json` activates dynamic MCP tool loading. This prevents unused MCP tools from consuming context.

```json
{
  "env": {
    "ENABLE_TOOL_SEARCH": "1"
  }
}
```

### Configuration for Claude Desktop

Add the following to your Claude Desktop configuration file:

**macOS**: `~/Library/Application Support/Claude/claude_desktop_config.json`

```json
{
  "mcpServers": {
    "xcodeproj": {
      "command": "docker",
      "args": [
        "run",
        "--rm",
        "-i",
        "-v",
        "${workspaceFolder}:/workspace",
        "ghcr.io/giginet/xcodeproj-mcp-server",
        "/workspace"
      ]
    }
  }
}
```

### Path Security

The MCP server supports restricting file operations to a specific base directory. When you provide a base path as a command-line argument:

- All `project_path` and file path parameters will be resolved relative to this base path
- Absolute paths are validated to ensure they're within the base directory
- Any attempt to access files outside the base directory will result in an error

This is especially useful when running the server in Docker containers or other sandboxed environments.

## Available Tools

### Session Management

| Tool | Description |
|------|-------------|
| `set_session_defaults` | Set default project, scheme, simulator, device, and configuration for the session |
| `show_session_defaults` | Show current session defaults |
| `clear_session_defaults` | Clear all session defaults |

### Project Management

| Tool | Description |
|------|-------------|
| `create_xcodeproj` | Create a new Xcode project |
| `scaffold_ios_project` | Create a new iOS project with workspace + SPM architecture |
| `scaffold_macos_project` | Create a new macOS project with workspace + SPM architecture |
| `list_targets` | List all targets in a project |
| `list_build_configurations` | List all build configurations |
| `list_files` | List all files in a specific target |
| `list_groups` | List all groups in the project with hierarchical paths |
| `add_file` | Add a file to the project |
| `remove_file` | Remove a file from the project |
| `move_file` | Move or rename a file within the project |
| `add_synchronized_folder` | Add a synchronized folder reference to the project |
| `create_group` | Create a new group in the project navigator |
| `add_target` | Create a new target |
| `remove_target` | Remove an existing target |
| `duplicate_target` | Duplicate an existing target |
| `add_dependency` | Add dependency between targets |
| `get_build_settings` | Get build settings for a target |
| `set_build_setting` | Modify build settings |
| `add_framework` | Add framework dependencies |
| `add_build_phase` | Add custom build phases |
| `add_app_extension` | Add an App Extension target and embed it in a host app |
| `remove_app_extension` | Remove an App Extension target |

### Swift Package Management (in Xcode projects)

| Tool | Description |
|------|-------------|
| `add_swift_package` | Add a Swift Package dependency to the project |
| `list_swift_packages` | List all Swift Package dependencies in the project |
| `remove_swift_package` | Remove a Swift Package dependency from the project |

### Discovery

| Tool | Description |
|------|-------------|
| `discover_projs` | Discover Xcode projects and workspaces in a directory |
| `list_schemes` | List all schemes in a project or workspace |
| `show_build_settings` | Show build settings for a scheme |
| `get_app_bundle_id` | Get the bundle identifier for an iOS/watchOS/tvOS app |
| `get_mac_bundle_id` | Get the bundle identifier for a macOS app |

### Simulator

| Tool | Description |
|------|-------------|
| `list_sims` | List available simulators |
| `boot_sim` | Boot a simulator |
| `open_sim` | Open Simulator.app with a specific simulator |
| `build_sim` | Build an app for the simulator |
| `build_run_sim` | Build and run an app on the simulator |
| `install_app_sim` | Install an app on a simulator |
| `launch_app_sim` | Launch an app on a simulator |
| `stop_app_sim` | Stop a running app on a simulator |
| `get_sim_app_path` | Get the path to an installed app on a simulator |
| `test_sim` | Run tests on a simulator |
| `record_sim_video` | Record a video of the simulator |
| `launch_app_logs_sim` | Launch an app and capture logs |
| `erase_sims` | Erase (reset) a simulator |
| `set_sim_location` | Set the simulated location for a simulator |
| `reset_sim_location` | Reset the simulated location for a simulator |
| `set_sim_appearance` | Set the appearance (light/dark mode) for a simulator |
| `sim_statusbar` | Override status bar settings (time, battery, etc.) |

### Device

| Tool | Description |
|------|-------------|
| `list_devices` | List connected physical devices |
| `build_device` | Build an app for a physical device |
| `install_app_device` | Install an app on a physical device |
| `launch_app_device` | Launch an app on a physical device |
| `stop_app_device` | Stop a running app on a physical device |
| `get_device_app_path` | Get the path to an installed app on a device |
| `test_device` | Run tests on a physical device |

### macOS

| Tool | Description |
|------|-------------|
| `build_macos` | Build a macOS app |
| `build_run_macos` | Build and run a macOS app |
| `launch_mac_app` | Launch a macOS app |
| `stop_mac_app` | Stop a running macOS app |
| `get_mac_app_path` | Get the path to a built macOS app |
| `test_macos` | Run tests for a macOS app |

### Logging

| Tool | Description |
|------|-------------|
| `start_sim_log_cap` | Start capturing logs from a simulator |
| `stop_sim_log_cap` | Stop capturing logs and return results |
| `start_device_log_cap` | Start capturing logs from a device |
| `stop_device_log_cap` | Stop capturing device logs and return results |

### Debug

| Tool | Description |
|------|-------------|
| `debug_attach_sim` | Attach LLDB debugger to an app on a simulator |
| `debug_detach` | Detach the debugger from the current session |
| `debug_breakpoint_add` | Add a breakpoint |
| `debug_breakpoint_remove` | Remove a breakpoint |
| `debug_continue` | Continue execution after hitting a breakpoint |
| `debug_stack` | Print the current stack trace |
| `debug_variables` | Print local variables in the current frame |
| `debug_lldb_command` | Execute an arbitrary LLDB command |

### UI Automation

| Tool | Description |
|------|-------------|
| `tap` | Tap at a coordinate on the simulator |
| `long_press` | Long press at a coordinate on the simulator |
| `swipe` | Swipe from one point to another on the simulator |
| `type_text` | Type text on the simulator |
| `key_press` | Press a hardware key on the simulator |
| `button` | Press a hardware button on the simulator |
| `screenshot` | Take a screenshot of the simulator |

### Swift Package Manager

| Tool | Description |
|------|-------------|
| `swift_package_build` | Build a Swift package |
| `swift_package_test` | Run tests for a Swift package |
| `swift_package_run` | Run an executable from a Swift package |
| `swift_package_clean` | Clean build artifacts for a Swift package |
| `swift_package_list` | List dependencies for a Swift package |
| `swift_package_stop` | Stop a running Swift package executable |

### Utilities

| Tool | Description |
|------|-------------|
| `clean` | Clean build products using xcodebuild |
| `doctor` | Diagnose the Xcode development environment |

## Use Cases

### Project Creation and Setup
- **Create projects from scratch**: Generate new Xcode projects with custom configurations without opening Xcode
- **Scaffold modern projects**: Create iOS/macOS projects with workspace + SPM architecture
- **Multi-target project scaffolding**: Set up complex projects with multiple apps, frameworks, tests, and extensions

### Development Workflow Automation
- **Add new files to targets**: After creating a new Swift file, automatically add it to the appropriate target
- **Add folder references**: Include external resource folders as synchronized folder references
- **Add build phases**: Integrate code formatters, linters, or custom build scripts
- **Create frameworks and app extensions**: Quickly scaffold new framework targets or app extensions

### Build and Test
- **Build for any platform**: Build for simulators, physical devices, or macOS
- **Run automated tests**: Execute test suites on simulators or devices
- **Capture logs**: Monitor app output during testing

### Simulator Control
- **Manage simulator state**: Boot, shutdown, and reset simulators
- **Test different conditions**: Set location, appearance, and status bar settings
- **Record sessions**: Capture video of simulator interactions

### Debugging
- **Attach debugger**: Debug running apps with LLDB
- **Set breakpoints**: Add breakpoints in source files
- **Inspect state**: View stack traces and variables

## License

This project is licensed under the MIT License.

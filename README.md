# xc-mcp

A Model Context Protocol (MCP) server for Xcode development on macOS. Build, test, run, and debug iOS, macOS, watchOS, and tvOS apps on simulators and physical devices with full project manipulation capabilities.

## Overview

xc-mcp is a unified MCP server that combines Xcode project manipulation with build, test, and run capabilities. It uses:

- [tuist/xcodeproj](https://github.com/tuist/xcodeproj) for project file manipulation
- [modelcontextprotocol/swift-sdk](https://github.com/modelcontextprotocol/swift-sdk) for MCP implementation
- Native `xcodebuild`, `simctl`, and `devicectl` for build and device operations

This server enables AI assistants and MCP clients to:

- Create and manage Xcode projects
- Build and run apps on simulators and physical devices
- Run tests and capture logs
- Control simulator state, appearance, and location
- Debug apps with LLDB
- Automate UI interactions
- Work with Swift Package Manager projects

## Multi-Server Architecture

xc-mcp provides both a monolithic server (all 89 tools) and focused servers for token efficiency:

| Server | Tools | Token Overhead | Description |
|--------|-------|----------------|-------------|
| `xc-mcp` | 89 | ~50K | Full monolithic server |
| `xc-project` | 23 | ~5K | .xcodeproj file manipulation |
| `xc-simulator` | 29 | ~6K | Simulator, UI automation, logs |
| `xc-device` | 12 | ~2K | Physical iOS devices |
| `xc-debug` | 8 | ~2K | LLDB debugging |
| `xc-swift` | 6 | ~1.5K | Swift Package Manager |
| `xc-build` | 18 | ~3K | macOS builds, discovery, utilities |
| `xc-strings` | 18 | ~6K | Xcode String Catalog (.xcstrings) localization |

**When to use focused servers:**
- Use `xc-project` for project file editing (no CLI alternative exists)
- Use `xc-simulator` for build+run workflows on simulators
- Use `xc-device` for physical device deployment
- Use `xc-debug` for debugging sessions
- Use `xc-swift` for Swift package operations
- Use `xc-strings` for localization management with .xcstrings files

**Configuration presets:**

```json
// Minimal (~5K tokens) - project editing only
{
  "mcpServers": {
    "xc-project": { "command": "/opt/homebrew/bin/xc-project" }
  }
}

// Standard (~14K tokens) - project + simulator + build
{
  "mcpServers": {
    "xc-project": { "command": "/opt/homebrew/bin/xc-project" },
    "xc-simulator": { "command": "/opt/homebrew/bin/xc-simulator" },
    "xc-build": { "command": "/opt/homebrew/bin/xc-build" }
  }
}

// Full (~20K tokens) - all capabilities
{
  "mcpServers": {
    "xc-project": { "command": "/opt/homebrew/bin/xc-project" },
    "xc-simulator": { "command": "/opt/homebrew/bin/xc-simulator" },
    "xc-device": { "command": "/opt/homebrew/bin/xc-device" },
    "xc-debug": { "command": "/opt/homebrew/bin/xc-debug" },
    "xc-swift": { "command": "/opt/homebrew/bin/xc-swift" },
    "xc-build": { "command": "/opt/homebrew/bin/xc-build" }
  }
}
```

## Requirements

- macOS 15+
- Xcode (for `xcodebuild`, `simctl`, `devicectl`)

## Installation

### Homebrew (Recommended)

```bash
brew tap toba/xc-mcp
brew install xc-mcp
```

### From Source

```bash
git clone https://github.com/toba/xc-mcp.git
cd xc-mcp
swift build -c release
```

## Configuration

### Claude Code

```bash
# With Homebrew
claude mcp add xc-mcp -- $(brew --prefix)/bin/xc-mcp

# From source
claude mcp add xc-mcp -- /path/to/xc-mcp/.build/release/xc-mcp
```

### Claude Desktop

Add to `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "xc-mcp": {
      "command": "/opt/homebrew/bin/xc-mcp"
    }
  }
}
```

For Intel Macs, use `/usr/local/bin/xc-mcp` instead.

## Tools

### Session Management (3 tools)

| Tool | Description |
|------|-------------|
| `set_session_defaults` | Set default project, scheme, simulator, device, and configuration |
| `show_session_defaults` | Show current session defaults |
| `clear_session_defaults` | Clear all session defaults |

### Project Management (23 tools)

| Tool | Description |
|------|-------------|
| `create_xcodeproj` | Create a new Xcode project |
| `scaffold_ios_project` | Create iOS project with workspace + SPM architecture |
| `scaffold_macos_project` | Create macOS project with workspace + SPM architecture |
| `list_targets` | List all targets in a project |
| `list_build_configurations` | List all build configurations |
| `list_files` | List all files in a target |
| `list_groups` | List all groups in the project |
| `add_file` | Add a file to the project |
| `remove_file` | Remove a file from the project |
| `move_file` | Move or rename a file |
| `add_synchronized_folder` | Add a synchronized folder reference |
| `create_group` | Create a new group |
| `add_target` | Create a new target |
| `remove_target` | Remove a target |
| `duplicate_target` | Duplicate a target |
| `add_dependency` | Add dependency between targets |
| `get_build_settings` | Get build settings for a target |
| `set_build_setting` | Modify build settings |
| `add_framework` | Add framework dependencies |
| `add_build_phase` | Add custom build phases |
| `add_app_extension` | Add an App Extension target |
| `remove_app_extension` | Remove an App Extension target |
| `add_swift_package` | Add a Swift Package dependency |
| `list_swift_packages` | List Swift Package dependencies |
| `remove_swift_package` | Remove a Swift Package dependency |

### Discovery (5 tools)

| Tool | Description |
|------|-------------|
| `discover_projs` | Discover Xcode projects and workspaces |
| `list_schemes` | List all schemes |
| `show_build_settings` | Show build settings for a scheme |
| `get_app_bundle_id` | Get bundle identifier for iOS/watchOS/tvOS app |
| `get_mac_bundle_id` | Get bundle identifier for macOS app |

### Simulator (17 tools)

| Tool | Description |
|------|-------------|
| `list_sims` | List available simulators |
| `boot_sim` | Boot a simulator |
| `open_sim` | Open Simulator.app with a specific simulator |
| `build_sim` | Build an app for simulator |
| `build_run_sim` | Build and run on simulator |
| `install_app_sim` | Install an app on simulator |
| `launch_app_sim` | Launch an app on simulator |
| `stop_app_sim` | Stop a running app |
| `get_sim_app_path` | Get path to installed app |
| `test_sim` | Run tests on simulator |
| `record_sim_video` | Record video of simulator |
| `launch_app_logs_sim` | Launch app and capture logs |
| `erase_sims` | Reset a simulator |
| `set_sim_location` | Set simulated location |
| `reset_sim_location` | Reset simulated location |
| `set_sim_appearance` | Set appearance (light/dark mode) |
| `sim_statusbar` | Override status bar settings |

### Device (7 tools)

| Tool | Description |
|------|-------------|
| `list_devices` | List connected physical devices |
| `build_device` | Build for physical device |
| `install_app_device` | Install on physical device |
| `launch_app_device` | Launch on physical device |
| `stop_app_device` | Stop app on physical device |
| `get_device_app_path` | Get path to installed app |
| `test_device` | Run tests on physical device |

### macOS (6 tools)

| Tool | Description |
|------|-------------|
| `build_macos` | Build a macOS app |
| `build_run_macos` | Build and run macOS app |
| `launch_mac_app` | Launch a macOS app |
| `stop_mac_app` | Stop a macOS app |
| `get_mac_app_path` | Get path to built macOS app |
| `test_macos` | Run tests for macOS app |

### Logging (4 tools)

| Tool | Description |
|------|-------------|
| `start_sim_log_cap` | Start capturing simulator logs |
| `stop_sim_log_cap` | Stop capturing and return results |
| `start_device_log_cap` | Start capturing device logs |
| `stop_device_log_cap` | Stop capturing device logs |

### Debug (8 tools)

| Tool | Description |
|------|-------------|
| `debug_attach_sim` | Attach LLDB to app on simulator |
| `debug_detach` | Detach debugger |
| `debug_breakpoint_add` | Add a breakpoint |
| `debug_breakpoint_remove` | Remove a breakpoint |
| `debug_continue` | Continue execution |
| `debug_stack` | Print stack trace |
| `debug_variables` | Print local variables |
| `debug_lldb_command` | Execute LLDB command |

### UI Automation (7 tools)

| Tool | Description |
|------|-------------|
| `tap` | Tap at coordinate |
| `long_press` | Long press at coordinate |
| `swipe` | Swipe between points |
| `type_text` | Type text |
| `key_press` | Press hardware key |
| `button` | Press hardware button |
| `screenshot` | Take screenshot |

### Swift Package Manager (6 tools)

| Tool | Description |
|------|-------------|
| `swift_package_build` | Build a Swift package |
| `swift_package_test` | Run package tests |
| `swift_package_run` | Run package executable |
| `swift_package_clean` | Clean build artifacts |
| `swift_package_list` | List dependencies |
| `swift_package_stop` | Stop running executable |

### Utilities (4 tools)

| Tool | Description |
|------|-------------|
| `clean` | Clean build products |
| `doctor` | Diagnose Xcode environment |
| `scaffold_ios_project` | Scaffold iOS project |
| `scaffold_macos_project` | Scaffold macOS project |

### Localization (18 tools)

| Tool | Description |
|------|-------------|
| `xcstrings_list_keys` | List all localization keys |
| `xcstrings_list_languages` | List all languages in file |
| `xcstrings_list_untranslated` | List untranslated keys for language |
| `xcstrings_get_source_language` | Get the source language |
| `xcstrings_get_key` | Get translations for a key |
| `xcstrings_check_key` | Check if a key exists |
| `xcstrings_stats_coverage` | Get overall coverage statistics |
| `xcstrings_stats_progress` | Get progress for a language |
| `xcstrings_batch_stats_coverage` | Get coverage for multiple files |
| `xcstrings_create_file` | Create a new xcstrings file |
| `xcstrings_add_translation` | Add a single translation |
| `xcstrings_add_translations` | Add multiple translations (batch) |
| `xcstrings_update_translation` | Update a single translation |
| `xcstrings_update_translations` | Update multiple translations (batch) |
| `xcstrings_rename_key` | Rename a localization key |
| `xcstrings_delete_key` | Delete a key and all translations |
| `xcstrings_delete_translation` | Delete a single translation |
| `xcstrings_delete_translations` | Delete multiple translations (batch) |

## Path Security

When providing a base path as a command-line argument, all file operations are restricted to that directory.

## License

MIT License. See [LICENSE](LICENSE) for details.

This project is based on [giginet/xcodeproj-mcp-server](https://github.com/giginet/xcodeproj-mcp-server). Build output parsing and code coverage are adapted from [ldomaradzki/xcsift](https://github.com/ldomaradzki/xcsift). The localization functionality is based on [Ryu0118/xcstrings-crud](https://github.com/Ryu0118/xcstrings-crud).

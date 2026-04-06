---
name: xcode
description: Intelligent Xcode development operations
---

# Xcode Development Skill

This skill provides guidance for using xc-mcp tools efficiently based on the task at hand. It routes operations to the appropriate MCP server or native CLI to minimize token overhead.

## Server Architecture

The xc-mcp toolset is split into focused servers for token efficiency:

| Server | Tools | Token Overhead | Use Case |
|--------|-------|----------------|----------|
| **xc-project** | 23 | ~5K | .xcodeproj file manipulation |
| **xc-simulator** | 29 | ~6K | iOS Simulator, UI automation, sim logs |
| **xc-device** | 12 | ~2K | Physical iOS devices |
| **xc-debug** | 8 | ~2K | LLDB debugging |
| **xc-swift** | 6 | ~1.5K | Swift Package Manager |
| **xc-build** | 18 | ~3K | macOS builds, discovery, utilities |
| **xc-mcp** | 89 | ~50K | All tools (monolithic) |

## Routing Guidelines

### Project File Manipulation → xc-project MCP

Use `mcp__xc-project__*` tools for operations that modify .xcodeproj files:
- Adding/removing files, targets, groups
- Modifying build settings
- Managing Swift packages
- Adding frameworks and dependencies

**These operations require the XcodeProj library - no CLI equivalent exists.**

### iOS Simulator Operations → xc-simulator MCP

Use `mcp__xc-simulator__*` tools for:
- Build and run workflows (`build_run_sim`)
- Simulator management (boot, list, erase)
- UI automation (tap, swipe, type text)
- Screenshot capture
- App installation and launch

### Physical Device Operations → xc-device MCP

Use `mcp__xc-device__*` tools for:
- Building for devices
- Installing and launching apps on devices
- Device log capture

### Debug Sessions → xc-debug MCP

Use `mcp__xc-debug__*` tools for:
- Attaching to running processes
- Setting/removing breakpoints
- Inspecting variables and stack
- Executing LLDB commands

**Debug sessions maintain persistent state - use this server for multi-step debugging workflows.**

### Swift Packages → xc-swift MCP

Use `mcp__xc-swift__*` tools for:
- Building Swift packages
- Running tests
- Executing package binaries

### macOS & Discovery → xc-build MCP

Use `mcp__xc-build__*` tools for:
- macOS application builds
- Project/scheme discovery
- Build settings queries
- Project scaffolding
- Clean operations

### Simple Queries → Bash (Direct CLI)

For read-only queries, use Bash directly to avoid MCP overhead:

```bash
# List schemes
xcodebuild -list -json

# List simulators
xcrun simctl list devices --json

# Simple SPM build
swift build
```

## Configuration Presets

Users can configure which servers to enable in their `.mcp.json`:

### Minimal (project editing only) - ~5K tokens
```json
{
  "mcpServers": {
    "xc-project": { "command": "xc-project" }
  }
}
```

### Standard (build + project) - ~14K tokens
```json
{
  "mcpServers": {
    "xc-project": { "command": "xc-project" },
    "xc-build": { "command": "xc-build" },
    "xc-simulator": { "command": "xc-simulator" }
  }
}
```

### Full (all capabilities) - ~20K tokens
```json
{
  "mcpServers": {
    "xc-project": { "command": "xc-project" },
    "xc-build": { "command": "xc-build" },
    "xc-simulator": { "command": "xc-simulator" },
    "xc-device": { "command": "xc-device" },
    "xc-debug": { "command": "xc-debug" },
    "xc-swift": { "command": "xc-swift" }
  }
}
```

### Monolithic (all tools, single server) - ~50K tokens
```json
{
  "mcpServers": {
    "xc-mcp": { "command": "xc-mcp" }
  }
}
```

## Decision Matrix

| Task | Recommended Approach |
|------|---------------------|
| Edit .xcodeproj file | MCP xc-project |
| Build and run iOS app | MCP xc-simulator `build_run_sim` |
| Take screenshot | MCP xc-simulator `screenshot` |
| Debug crash | MCP xc-debug |
| Build Swift package | MCP xc-swift or Bash `swift build` |
| List schemes | Bash `xcodebuild -list` |
| Query build settings | Bash `xcodebuild -showBuildSettings` |
| Install on device | MCP xc-device |

## Fallback Behavior

If no MCP server is configured for a capability:
1. Attempt to use native CLI via Bash
2. For project file edits: suggest using xcodegen with spec files
3. Inform user about available MCP servers for better experience

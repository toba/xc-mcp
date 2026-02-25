# xc-mcp

An exhaustive MCP server for Swift development on a Mac. Build, test, run, and debug iOS and macOS apps — on simulators, physical devices, and the Mac itself — with 178 tools for project manipulation, LLDB debugging, UI automation, Instruments profiling, localization, and SwiftUI preview capture.

I began working on this because every other, similar MCP I tried crashed or, worse, corrupted the configuration of complex projects (multiple targets, multiple platforms, mix of dependency types). I also thought it would be nice if it was written in Swift rather than TypeScript or Python.

## Be Wary

This project [iterates rapidly](CHANGELOG.md). Fairly complex issues had to be solved to get to this point which is both reassuring and disconcerting. There is good linting and strong tests, including fixtures that are actual, open source Swift projects, but no genuine QA process. As with any agent work, ensure your files are committed or otherwise backed up before releasing the kraken.

## Notable Powers

- **Token Efficiency**: run a single server with all tools or use some combination of smaller MCPs with just the subset of tools relevant to your work.
- **Screenshot any macOS app window**: `screenshot_mac_window` uses ScreenCaptureKit to capture any window, including your debug build, without needing a simulator.
- **UI automation for macOS apps via Accessibility**: The `interact_` tools use the macOS Accessibility API (AXUIElement) to click buttons, read values, navigate menus, type text, and dump the full UI element tree. It is *semantic*, able to click "Save" rather than a pixel coordinate. Eight tools: `interact_ui_tree`, `interact_click`, `interact_set_value`, `interact_get_value`, `interact_menu`, `interact_focus`, `interact_key`, `interact_find`.
- **Capture SwiftUI previews as screenshots**: `preview_capture` extracts `#Preview` blocks from your Swift source, generates a temporary host app, builds it, launches it (iOS Simulator or macOS), takes a screenshot, and cleans up. Handles complex project configurations: mergeable library architectures, SPM transitive dependencies, cross-project framework embedding, local Swift packages (files inside `Packages/` directories referenced by the Xcode project), and nested struct previews that crash the compiler when naively inlined. Programmatic preview screenshots without opening Xcode.
- **Paint view borders on a running app**: `debug_view_borders` injects colored `CALayer` borders onto every view in a running macOS app via LLDB. Pair with `screenshot_mac_window` to see the result. No code changes, no restarts.
- **Full LLDB debugging over MCP**: Persistent LLDB sessions backed by a pseudo-TTY, so breakpoints survive across tool calls. Breakpoints, watchpoints, stepping, expression evaluation, memory inspection, view hierarchy dumps, symbol lookup — the full debugger experience, minus the GUI.
- **Gesture presets**: `gesture` provides named presets — `scroll_up`, `pull_to_refresh`, `swipe_from_left_edge`, etc. — so agents don't have to do coordinate math every time they want to scroll a list. Eight presets, all computed as fractions of the screen dimensions you give it.
- **Xcode state sync**: `sync_xcode_defaults` reads your active scheme and run destination straight from Xcode's `UserInterfaceState.xcuserstate`. Open a project in Xcode, pick your scheme, then let the agent inherit that context without manual configuration.
- **Dynamic tool workflows**: `manage_workflows` lets you enable or disable entire tool categories (project, simulator, debug, etc.) at runtime. When an agent doesn't need 130 tools cluttering its context, disable the irrelevant ones. The server sends `tools/list_changed` notifications so clients update automatically.

## Built On

- [tuist/xcodeproj](https://github.com/tuist/xcodeproj) — project file manipulation
- [modelcontextprotocol/swift-sdk](https://github.com/modelcontextprotocol/swift-sdk) — MCP implementation
- Native `xcodebuild`, `simctl`, `devicectl`, `lldb`, and `xctrace` — the usual suspects

Originally based on [giginet/xcodeproj-mcp-server](https://github.com/giginet/xcodeproj-mcp-server). Build output parsing adapted from [ldomaradzki/xcsift](https://github.com/ldomaradzki/xcsift). Localization from [Ryu0118/xcstrings-crud](https://github.com/Ryu0118/xcstrings-crud).

## Table of Contents

- [Multi-Server Architecture](#multi-server-architecture)
- [Installation](#installation)
- [Configuration](#configuration)
- [Requirements](#requirements)
- [Tools](#tools)
  - [macOS UI Automation](#macos-ui-automation-8-tools)
  - [macOS Screenshots & Builds](#macos-screenshots--builds-10-tools)
  - [SwiftUI Preview Capture](#swiftui-preview-capture-1-tool)
  - [Debug](#debug-18-tools)
  - [Simulator](#simulator-17-tools)
  - [Simulator UI Automation](#simulator-ui-automation-8-tools)
  - [Device](#device-7-tools)
  - [Project Management](#project-management-54-tools)
  - [Discovery](#discovery-6-tools)
  - [Instruments](#instruments-3-tools)
  - [Logging](#logging-4-tools)
  - [Swift Package Manager](#swift-package-manager-9-tools)
  - [Localization](#localization-24-tools)
  - [Session & Utilities](#session--utilities-8-tools)
- [Tests](#tests)
- [Path Security](#path-security)
- [License](#license)

## Multi-Server Architecture

xc-mcp provides both a monolithic server and focused servers for token efficiency:

| Server | Tools | Token Overhead | Description |
|--------|-------|----------------|-------------|
| `xc-mcp` | 178 | ~50K | Full monolithic server |
| `xc-project` | 54 | ~12K | .xcodeproj file manipulation |
| `xc-simulator` | 29 | ~6K | Simulator, UI automation, simulator logs |
| `xc-device` | 12 | ~2K | Physical iOS devices |
| `xc-debug` | 22 | ~4K | LLDB debugging, view borders, screenshots, session defaults |
| `xc-swift` | 12 | ~2K | Swift Package Manager, swiftformat, swiftlint, diagnostics + session defaults |
| `xc-build` | 21 | ~3K | macOS builds, discovery, logging, diagnostics, utilities |
| `xc-strings` | 24 | ~8K | Xcode String Catalog (.xcstrings) localization |

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

## Requirements

- macOS 15+
- Xcode (for `xcodebuild`, `simctl`, `devicectl`)

### macOS Permissions

Some tools require macOS privacy permissions granted via **System Settings > Privacy & Security**:

| Permission | Tools | Notes |
|-----------|-------|-------|
| **Accessibility** | `interact_*` tools | Required for AXUIElement API access |
| **Screen Recording** | `screenshot_mac_window` | Required for ScreenCaptureKit window capture |

macOS grants these permissions to the **responsible process** — the GUI app at the top of the process tree, not the `xc-mcp` binary itself. This means:

- **Claude Desktop** needs the relevant permission when using xc-mcp as an MCP server
- **VS Code / Cursor** needs it when running xc-mcp through an MCP extension
- **Terminal / iTerm** needs it when running xc-mcp via Claude Code

The `xc-mcp` binary won't appear in System Settings because it's a CLI tool — TCC (Transparency, Consent, and Control) always resolves up to the parent GUI application.

## Tools

### macOS UI Automation (8 tools)

Semantic UI automation for macOS apps via the Accessibility API. These work on *any* running macOS app — your own debug builds, system apps, whatever has accessibility enabled. You interact with elements by role, title, and ID rather than screen coordinates.

| Tool | Description |
|------|-------------|
| `interact_ui_tree` | Dump the full UI element tree with assigned IDs for targeting |
| `interact_click` | Click a UI element by ID or role+title search |
| `interact_set_value` | Set value on a UI element (text fields, sliders, etc.) |
| `interact_get_value` | Read the current value of a UI element |
| `interact_menu` | Navigate and select menu bar items |
| `interact_focus` | Focus or activate a UI element |
| `interact_key` | Send keyboard input to the focused element |
| `interact_find` | Search for UI elements by properties |

### macOS Screenshots & Builds (10 tools)

| Tool | Description |
|------|-------------|
| `screenshot_mac_window` | Capture a macOS app window via ScreenCaptureKit. Match by app name, bundle ID, or window title. Returns inline base64 PNG. Works with `debug_view_borders` to capture visual debugging output |
| `build_macos` | Build a macOS app |
| `build_run_macos` | Build and run macOS app |
| `launch_mac_app` | Launch a macOS app |
| `stop_mac_app` | Stop a macOS app |
| `get_mac_app_path` | Get path to built macOS app |
| `test_macos` | Run tests for macOS app |
| `start_mac_log_cap` | Start capturing macOS app logs via unified logging |
| `stop_mac_log_cap` | Stop capturing and return macOS log results |
| `diagnostics` | Clean-build an Xcode project and collect all compiler warnings, errors, and lint violations. Same idea as `swift_diagnostics` but for `.xcodeproj`/`.xcworkspace` projects. Filters out dependency warnings so you only see your own code's problems |

### SwiftUI Preview Capture (1 tool)

| Tool | Description |
|------|-------------|
| `preview_capture` | Extract a `#Preview` block from a Swift file, build a temporary host app, launch on iOS Simulator or macOS, capture a screenshot, and clean up. Works with mergeable library projects, cross-project dependencies (GRDB, etc.), local Swift packages within the Xcode project, and previews containing nested types. Supports multi-preview files via `preview_index`, configurable `render_delay`, and optional `save_path` |

### Debug (18 tools)

Debug tools use persistent LLDB sessions backed by a pseudo-TTY — a single LLDB process stays alive across tool calls, so breakpoints are preserved and there are no hangs from rapid attach/detach cycles. Attach once with `debug_attach_sim`, then use any combination of debug tools against the live session.

**Build & debug launch:**

| Tool | Description |
|------|-------------|
| `build_debug_macos` | Build and launch a macOS app under LLDB — the equivalent of Xcode's Run button. Builds incrementally, launches via Launch Services and attaches LLDB with `--waitfor`. Handles sandboxed and hardened-runtime apps: symlinks non-embedded frameworks into the app bundle and rewrites install names to `@rpath/`. Supports custom args, env vars, and stop-at-entry |

**Session management:**

| Tool | Description |
|------|-------------|
| `debug_attach_sim` | Attach LLDB to app on simulator |
| `debug_detach` | Detach debugger and end session |
| `debug_process_status` | Get current process state (running, stopped, signal info) |

**Breakpoints and watchpoints:**

| Tool | Description |
|------|-------------|
| `debug_breakpoint_add` | Add a breakpoint (by symbol name or file:line) |
| `debug_breakpoint_remove` | Remove a breakpoint by ID |
| `debug_watchpoint` | Manage watchpoints — add (by variable or address with optional condition), remove, or list |

**Execution control:**

| Tool | Description |
|------|-------------|
| `debug_continue` | Continue execution |
| `debug_step` | Step through code — `in`, `over`, `out`, or `instruction`. Returns new source location |

**Inspection:**

| Tool | Description |
|------|-------------|
| `debug_stack` | Print stack trace (single thread or all threads) |
| `debug_variables` | Print local variables in a stack frame |
| `debug_threads` | List all threads, optionally select one to switch context |
| `debug_evaluate` | Evaluate expressions — `po` (object description), `p` (value), Swift or ObjC |
| `debug_memory` | Read memory at an address in hex, bytes, ASCII, or disassembly format |
| `debug_symbol_lookup` | Look up symbols by address, name (regex), or type name |
| `debug_view_hierarchy` | Dump the live UI view hierarchy (iOS or macOS), inspect by address, show Auto Layout constraints |
| `debug_view_borders` | Toggle colored borders on all views in a running macOS app via LLDB. Configurable color and width. Resume with `debug_continue` and screenshot to see results |

**Passthrough:**

| Tool | Description |
|------|-------------|
| `debug_lldb_command` | Execute arbitrary LLDB command for anything not covered above |

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

### Simulator UI Automation (8 tools)

Coordinate-based touch and gesture automation for iOS Simulators via `simctl io`.

| Tool | Description |
|------|-------------|
| `tap` | Tap at coordinate |
| `long_press` | Long press at coordinate |
| `swipe` | Swipe between points |
| `gesture` | Named gesture presets — `scroll_up`, `scroll_down`, `scroll_left`, `scroll_right`, `swipe_from_left_edge`, `swipe_from_right_edge`, `pull_to_refresh`, `swipe_down_to_dismiss`. Coordinates computed from screen dimensions (default iPhone 15 Pro) |
| `type_text` | Type text |
| `key_press` | Press hardware key |
| `button` | Press hardware button |
| `screenshot` | Take simulator screenshot |

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

### Project Management (54 tools)

| Tool | Description |
|------|-------------|
| `create_xcodeproj` | Create a new Xcode project |
| `scaffold_ios_project` | Create iOS project with workspace + SPM architecture |
| `scaffold_macos_project` | Create macOS project with workspace + SPM architecture |
| `list_targets` | List all targets in a project |
| `list_build_configurations` | List all build configurations |
| `list_files` | List all files in a target — enumerates disk files in synchronized folders (subtracting membership exceptions), handles both target-linked and exception-set-linked sync groups |
| `list_groups` | List all groups in the project |
| `add_file` | Add a file to the project |
| `remove_file` | Remove a file from the project |
| `move_file` | Move or rename a file |
| `create_group` | Create a new group |
| `remove_group` | Remove a group from the project navigator |
| `add_target` | Create a new target |
| `remove_target` | Remove a target |
| `rename_target` | Rename a target in-place — updates product name, build settings, dependencies, copy-files phases, product references, and group names. Optionally sets a new bundle identifier. Cross-target scan updates `TEST_TARGET_NAME`, `TEST_HOST`, `LD_RUNPATH_SEARCH_PATHS`, and `FRAMEWORK_SEARCH_PATHS` in other targets. Also patches `BuildableName` and `BlueprintName` in `.xcscheme` files |
| `rename_scheme` | Rename an `.xcscheme` file on disk (shared or user schemes) |
| `create_scheme` | Create a new `.xcscheme` file with build, test, and launch actions. Supports test targets, test plan references, build configurations, and pre-build shell script actions |
| `validate_scheme` | Validate a scheme's integrity — checks that build target references, testable target references, test plan files, and build configurations all exist in the project |
| `create_test_plan` | Generate a `.xctestplan` JSON file from project targets. Resolves target UUIDs from the `.xcodeproj`, supports code coverage toggle |
| `add_target_to_test_plan` | Add a test target entry to an existing `.xctestplan` file (resolves UUID from project) |
| `remove_target_from_test_plan` | Remove a test target from a `.xctestplan` file by name |
| `add_test_plan_to_scheme` | Add a test plan reference to an existing scheme's TestAction. Optionally set as default, which clears the default flag on other plans |
| `remove_test_plan_from_scheme` | Remove a test plan reference from a scheme's TestAction |
| `set_test_plan_target_enabled` | Enable or disable a test target in a `.xctestplan` file without removing it |
| `set_test_target_application` | Set the target application (macro expansion) for a UI test target in a scheme's Test action |
| `list_test_plans` | Find all `.xctestplan` files under the project directory and list their targets and configurations |
| `rename_group` | Rename a group in the project navigator by slash-separated path (e.g. `Sources/OldName`) |
| `duplicate_target` | Duplicate a target |
| `add_dependency` | Add dependency between targets |
| `get_build_settings` | Get build settings for a target |
| `set_build_setting` | Modify build settings |
| `add_framework` | Add framework dependencies |
| `add_build_phase` | Add custom build phases |
| `add_app_extension` | Add an App Extension target |
| `remove_app_extension` | Remove an App Extension target |
| `add_swift_package` | Add a Swift Package dependency — remote (by URL with version requirement) or local (by relative path). Mutually exclusive; local packages don't need a version |
| `list_swift_packages` | List Swift Package dependencies (both remote and local) |
| `remove_swift_package` | Remove a Swift Package dependency — remote (by URL) or local (by relative path). Optionally removes associated product dependencies from all targets |
| `add_synchronized_folder` | Add a synchronized folder reference |
| `remove_synchronized_folder` | Remove a synchronized folder reference (does not delete from disk) |
| `add_target_to_synchronized_folder` | Share an existing synchronized folder with another target |
| `remove_target_from_synchronized_folder` | Unlink a synchronized folder from a target |
| `add_synchronized_folder_exception` | Exclude specific files from a target in a synchronized folder |
| `remove_synchronized_folder_exception` | Remove a file or entire exception set from a synchronized folder |
| `list_synchronized_folder_exceptions` | List all exception sets on a synchronized folder with target names and excluded files |
| `add_copy_files_phase` | Create a new Copy Files build phase with a destination |
| `add_to_copy_files_phase` | Add files to an existing Copy Files build phase |
| `list_copy_files_phases` | List all Copy Files build phases for a target |
| `remove_copy_files_phase` | Remove a Copy Files build phase from a target |
| `list_document_types` | List document types (`CFBundleDocumentTypes`) in a target's Info.plist |
| `manage_document_type` | Add, update, or remove a document type in a target's Info.plist |
| `list_type_identifiers` | List exported/imported type identifiers (`UTExportedTypeDeclarations` / `UTImportedTypeDeclarations`) |
| `manage_type_identifier` | Add, update, or remove an exported or imported type identifier |
| `list_url_types` | List URL types (`CFBundleURLTypes`) — custom URL schemes the app handles |
| `manage_url_type` | Add, update, or remove a URL type (custom URL scheme) |
| `validate_project` | Validate an Xcode project for common configuration issues — checks embed phase settings (`dstSubfolderSpec`), detects frameworks that are linked but not embedded (or vice versa), flags duplicate embeds across copy-files phases, empty copy-files phases, and missing or unused target dependencies |

### Discovery (6 tools)

| Tool | Description |
|------|-------------|
| `discover_projs` | Discover Xcode projects and workspaces |
| `list_schemes` | List all schemes |
| `show_build_settings` | Show build settings for a scheme |
| `get_app_bundle_id` | Get bundle identifier for iOS/watchOS/tvOS app |
| `get_mac_bundle_id` | Get bundle identifier for macOS app |
| `list_test_plan_targets` | List test targets referenced by a scheme's test plans (via `xcodebuild`) |

### Instruments (3 tools)

Profiling via `xctrace` — record traces, list available templates and instruments, and export trace data as XML for analysis.

| Tool | Description |
|------|-------------|
| `xctrace_list` | List available Instruments templates, instruments, or devices |
| `xctrace_record` | Start or stop an Instruments trace recording (Time Profiler, Allocations, etc.) |
| `xctrace_export` | Export data from a `.trace` file as XML — use `toc=true` to see available tables, then query with xpath |

### Logging (4 tools)

| Tool | Description |
|------|-------------|
| `start_sim_log_cap` | Start capturing simulator logs |
| `stop_sim_log_cap` | Stop capturing and return results |
| `start_device_log_cap` | Start capturing device logs |
| `stop_device_log_cap` | Stop capturing device logs |

### Swift Package Manager (9 tools)

| Tool | Description |
|------|-------------|
| `swift_package_build` | Build a Swift package |
| `swift_package_test` | Run package tests |
| `swift_package_run` | Run package executable |
| `swift_package_clean` | Clean build artifacts |
| `swift_package_list` | List dependencies |
| `swift_package_stop` | Stop running executable |
| `swift_format` | Run `swiftformat` on a package or specific paths. Supports `dry_run` to preview changes. Auto-detects `.swiftformat` config |
| `swift_lint` | Run `swiftlint` on a package or specific paths. Parses JSON output into structured violations grouped by file. Supports `fix` mode for auto-correction. Auto-detects `.swiftlint.yml` config |
| `swift_diagnostics` | Clean-build a package and collect *all* compiler warnings, errors, and lint violations in one shot. Cached builds swallow warnings on success — this forces recompilation so nothing hides. Optionally includes swiftlint. Returns diagnostics even when the build succeeds |

### Localization (24 tools)

Full CRUD for Apple's `.xcstrings` format — add, update, rename, delete keys and translations, plus coverage stats and stale key detection. Batch operations are atomic.

| Tool | Description |
|------|-------------|
| `xcstrings_list_keys` | List all localization keys |
| `xcstrings_list_languages` | List all languages in file |
| `xcstrings_list_untranslated` | List untranslated keys for language |
| `xcstrings_list_stale` | List keys with "stale" extraction state (potentially unused) |
| `xcstrings_get_source_language` | Get the source language |
| `xcstrings_get_key` | Get translations for a key |
| `xcstrings_check_key` | Check if a key exists |
| `xcstrings_check_coverage` | Check translation coverage for a specific key |
| `xcstrings_batch_check_keys` | Check if multiple keys exist in one call |
| `xcstrings_stats_coverage` | Get overall coverage statistics |
| `xcstrings_stats_progress` | Get progress for a language |
| `xcstrings_batch_stats_coverage` | Get coverage for multiple files |
| `xcstrings_batch_list_stale` | List stale keys across multiple files |
| `xcstrings_create_file` | Create a new xcstrings file |
| `xcstrings_add_translation` | Add a single translation |
| `xcstrings_add_translations` | Add multiple translations for one key |
| `xcstrings_batch_add_translations` | Add translations for multiple keys atomically |
| `xcstrings_update_translation` | Update a single translation |
| `xcstrings_update_translations` | Update multiple translations for one key |
| `xcstrings_batch_update_translations` | Update translations for multiple keys atomically |
| `xcstrings_rename_key` | Rename a localization key |
| `xcstrings_delete_key` | Delete a key and all translations |
| `xcstrings_delete_translation` | Delete a single translation |
| `xcstrings_delete_translations` | Delete multiple translations (batch) |

### Session & Utilities (8 tools)

Project, workspace, and package paths are **auto-detected from the working directory** — the server walks up from `cwd` looking for `Package.swift`, `.xcodeproj`, or `.xcworkspace`, so you often don't need to call `set_session_defaults` at all. Explicit arguments and session defaults still take precedence when set.

| Tool | Description |
|------|-------------|
| `set_session_defaults` | Set default project, scheme, simulator, device, and configuration |
| `show_session_defaults` | Show current session defaults |
| `clear_session_defaults` | Clear all session defaults |
| `sync_xcode_defaults` | Read active scheme and run destination from Xcode's IDE state (`UserInterfaceState.xcuserstate`) and apply as session defaults |
| `manage_workflows` | Enable or disable tool workflow categories (project, simulator, debug, etc.) to reduce tool surface area. Server sends `tools/list_changed` so clients update automatically |
| `clean` | Clean build products |
| `doctor` | Diagnose Xcode environment — checks Xcode, CLT, xcodebuild, simctl, devicectl, Swift, LLDB, SDKs, DerivedData, session state, and active debug sessions |
| `search_crash_reports` | Search `~/Library/Logs/DiagnosticReports/` for recent `.ips` crash reports by process name or bundle ID. Parses exception type, signal, termination reason, and dyld details — so you don't have to squint at JSON in Console.app |

## Build Output Parsing

Test tools parse both **XCTest** and **Swift Testing** output formats, extracting structured pass/fail results with test names, durations, and failure details. Supported formats include:

- XCTest sequential and parallel test output
- Swift Testing quoted and unquoted function names (e.g., `"testExample()"` or `testExample()`)
- Swift Testing symbol-prefixed output (e.g., `✘`, `✓`, or SF Symbol codepoints)
- Failure summaries with suite and issue counts

## Tests

578 tests — unit tests that run in seconds, and integration tests that build, run, screenshot, and preview-capture real open-source projects. The unit tests use in-memory fixtures and mock runners. The integration tests use *actual Xcode builds* against actual repos, which is both thorough and time-consuming.

### Unit Tests

```bash
swift test
```

Every tool has unit tests covering argument validation, success paths, and error cases. These don't require Xcode projects on disk — they use bundled `.xcodeproj` fixtures and mock runners that return canned output. Fast, deterministic, no simulator needed.

### Integration Tests

Integration tests exercise tools end-to-end against three open-source repos: [Alamofire](https://github.com/Alamofire/Alamofire), [SwiftFormat](https://github.com/nicklockwood/SwiftFormat), and [IceCubesApp](https://github.com/Dimillian/IceCubesApp). Each repo is pinned to a specific commit so tests don't break when upstream changes.

```bash
# Fetch fixture repos (idempotent, ~1 minute)
./scripts/fetch-fixtures.sh

# Run all integration tests
swift test --filter Integration

# Just the build/run/screenshot tests
swift test --filter BuildRunScreenshot
```

Without the fixture repos, integration tests auto-skip — `swift test` won't fail, it just won't run them. Simulator-dependent tests additionally gate on a resolvable iPhone simulator UDID.

**What's tested:**

| Project | Build | Run | Screenshot | Preview Capture |
|---------|-------|-----|------------|-----------------|
| Alamofire | `build_sim` (iOS), `build_macos` | — | — | — |
| SwiftFormat | `build_macos` | — | — | — |
| IceCubesApp | — | `build_run_sim` | `screenshot` (sim) | `preview_capture` |

Plus read-only introspection tests (`list_targets`, `list_files`, `list_groups`, `list_build_configurations`, `get_build_settings`, `list_swift_packages`, `discover_projects`) across all three repos.

Build tests carry a 10-minute timeout because — well — *Xcode*. The IceCubesApp preview capture test exercises local Swift package detection — `PlaceholderView.swift` lives in `Packages/DesignSystem/`, not a native target, so the tool must infer the module name and link the local package product into the preview host.

## Path Security

When providing a base path as a command-line argument, all file operations are restricted to that directory.

## License

MIT License. See [LICENSE](LICENSE) for details.

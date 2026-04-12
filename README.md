# xc-mcp

An exhaustive MCP server for Swift development on a Mac. Build, test, run, and debug iOS and macOS apps — on simulators, physical devices, and the Mac itself — with 200 tools for project manipulation, LLDB debugging, UI automation, Instruments profiling, memory diagnostics, crash symbolication, notarization, localization, icon composition, and SwiftUI preview capture.

I began working on this because every other, similar MCP I tried crashed or, worse, corrupted the configuration of complex projects (multiple targets, multiple platforms, mix of dependency types). I also thought it would be nice if it was written in Swift rather than TypeScript or Python.

## Be Wary

This project [iterates rapidly](CHANGELOG.md). Fairly complex issues had to be solved to get to this point which is both reassuring and disconcerting. There is good linting and strong tests, including fixtures that are actual, open source Swift projects, but no genuine QA process. As with any agent work, ensure your files are committed or otherwise backed up before releasing the kraken.

## Built On

- [tuist/xcodeproj](https://github.com/tuist/xcodeproj) — project file manipulation
- [modelcontextprotocol/swift-sdk](https://github.com/modelcontextprotocol/swift-sdk) — MCP implementation
- Native `xcodebuild`, `simctl`, `devicectl`, `lldb`, and `xctrace` — the usual suspects

Originally based on [giginet/xcodeproj-mcp-server](https://github.com/giginet/xcodeproj-mcp-server). Build output parsing adapted from [ldomaradzki/xcsift](https://github.com/ldomaradzki/xcsift). Localization from [Ryu0118/xcstrings-crud](https://github.com/Ryu0118/xcstrings-crud). Memory diagnostics, symbolication, and other CLI tool integrations inspired by [Terryc21/Xcode-tools](https://github.com/Terryc21/Xcode-tools)' catalog of hidden Xcode CLIs. Icon composition informed by [ethbak/icon-composer-mcp](https://github.com/ethbak/icon-composer-mcp).

---

## What's Inside

Nine tool categories. Use the monolithic server for everything, or mix focused servers to keep token overhead low.

| | Category | Tools | What it does |
|---|---|:---:|---|
| [1](#debugging) | [Debugging](#debugging) | 24 | LLDB sessions, memory diagnostics, crash symbolication, view borders |
| [2](#macos-builds--screenshots) | [macOS Builds](#macos-builds--screenshots) | 14 | Build, test, run, screenshot, coverage, profiling |
| [3](#simulators) | [Simulators](#simulators) | 25 | Build, run, screenshot, touch/gesture automation, logs |
| [4](#devices) | [Devices](#devices) | 9 | Build, deploy, test on physical iOS devices |
| [5](#project-management) | [Project Management](#project-management) | 58 | Full .xcodeproj manipulation — targets, groups, packages, schemes, test plans |
| [6](#icon-composition) | [Icon Composition](#icon-composition) | 9 | Create and edit Icon Composer `.icon` bundles, render via `ictool` |
| [7](#swift-packages) | [Swift Packages](#swift-packages) | 12 | SPM build/test/run, swiftformat, swiftlint, unused code detection |
| [8](#localization) | [Localization](#localization) | 24 | Full CRUD for `.xcstrings` files — keys, translations, coverage |
| [9](#session--utilities) | [Session & Utilities](#session--utilities) | 12 | Auto-detection, environment, Xcode sync, notarization, version management |

Plus a handful of cross-cutting capabilities described in [Notable Powers](#notable-powers).

---

## Installation

### Homebrew (Recommended)

```bash
brew tap toba/tap
brew install xc-mcp
```

### From Source

```bash
git clone https://github.com/toba/xc-mcp.git
cd xc-mcp
swift build -c release
```

### Configuration

**Claude Code:**

```bash
# With Homebrew
claude mcp add xc-mcp -- $(brew --prefix)/bin/xc-mcp

# From source
claude mcp add xc-mcp -- /path/to/xc-mcp/.build/release/xc-mcp
```

**Claude Desktop** — add to `~/Library/Application Support/Claude/claude_desktop_config.json`:

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

### Requirements

- macOS 15+
- Xcode (for `xcodebuild`, `simctl`, `devicectl`)
- Some tools require macOS privacy permissions — see [Permissions](#macos-permissions)

---

## Multi-Server Architecture

Run a single server with all tools, or use focused servers to reduce token overhead. Every tool is in `xc-mcp`; the focused servers are strict subsets.

| Server | Tools | Tokens | What's in it |
|--------|:-----:|:------:|---|
| `xc-mcp` | 187 | ~30K | Everything |
| `xc-project` | 61 | ~9K | .xcodeproj manipulation |
| `xc-build` | 44 | ~7K | macOS builds, profiling, discovery, diagnostics, icons, versioning, notarization |
| `xc-simulator` | 29 | ~5K | Simulator + UI automation + simulator logs |
| `xc-debug` | 28 | ~4K | LLDB, memory diagnostics, crash symbolication, screenshots |
| `xc-strings` | 24 | ~3K | .xcstrings localization |
| `xc-swift` | 15 | ~3K | SPM, swiftformat, swiftlint, diagnostics, coverage |
| `xc-device` | 14 | ~3K | Physical iOS devices |

<details>
<summary><strong>Configuration presets</strong></summary>

```json
// Minimal (~9K tokens) — project editing only
{
  "mcpServers": {
    "xc-project": { "command": "/opt/homebrew/bin/xc-project" }
  }
}

// Standard (~19K tokens) — project + simulator + build
{
  "mcpServers": {
    "xc-project": { "command": "/opt/homebrew/bin/xc-project" },
    "xc-simulator": { "command": "/opt/homebrew/bin/xc-simulator" },
    "xc-build": { "command": "/opt/homebrew/bin/xc-build" }
  }
}

// Full (~27K tokens) — all capabilities
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

</details>

---

## Notable Powers

A few things worth calling out because they're unusual, non-obvious, or the reason this project exists.

**Screenshot any macOS app window** — `screenshot_mac_window` uses ScreenCaptureKit to capture any window by app name, bundle ID, or title. No simulator required. Pair with `debug_view_borders` to see layout issues.

**Semantic macOS UI automation** — The `interact_*` tools use the Accessibility API to click "Save" rather than a pixel coordinate. Dump the UI tree, click buttons, read values, navigate menus, type text. Works on any running macOS app.

**SwiftUI preview capture** — `preview_capture` extracts `#Preview` blocks, generates a temporary host app, builds and launches it, screenshots, and cleans up. Handles mergeable libraries, SPM transitive dependencies, local packages in `Packages/`, and nested struct previews that crash the compiler.

**Full LLDB over MCP** — Persistent sessions backed by a pseudo-TTY. Breakpoints survive across tool calls. The full debugger minus the GUI.

**Paint view borders on a running app** — `debug_view_borders` injects colored `CALayer` borders onto every view via LLDB. No code changes, no restarts.

**Memory diagnostics** — Wraps `leaks`, `heap`, `vmmap`, `stringdups`, and `malloc_history` — the ones buried inside the Developer directory that most people don't know exist. An LLM is *particularly* good at these because the output is dense, repetitive, and begging for someone (something?) to summarize.

**One-call device deployment** — `build_deploy_device` does build → stop → install → launch in a single tool call. No four-step dance.

**Xcode state sync** — `sync_xcode_defaults` reads your active scheme and run destination from Xcode's user state. Open a project, pick your scheme, let the agent inherit it.

**Icon Composer bundles** — Full `.icon` bundle creation and editing — layers, fills, glass effects, dark mode — without opening Icon Composer. Render via `ictool`.

**Unused code detection** — Wraps [Periphery](https://github.com/peripheryapp/periphery). Returns a persistent checklist agents can mark off as they clean up.

**Dynamic tool workflows** — `manage_workflows` enables or disables tool categories at runtime so 187 tools don't all sit in context when you only need six.

---

## Category Details

Each section below describes a tool category with highlights, then expands to the full tool reference.

---

### Debugging

24 tools. LLDB sessions backed by a pseudo-TTY — breakpoints survive across tool calls, no hangs from rapid attach/detach. Plus standalone memory diagnostics and crash symbolication that work on any running process.

<details>
<summary><strong>Build & attach</strong></summary>

| Tool | Description |
|------|-------------|
| `build_debug_macos` | Build and launch a macOS app under LLDB. Handles sandboxed and hardened-runtime apps: symlinks frameworks and rewrites install names |
| `debug_attach_sim` | Attach LLDB to app on simulator |
| `debug_detach` | Detach debugger and end session |
| `debug_process_status` | Get current process state |

</details>

<details>
<summary><strong>Breakpoints, watchpoints & execution</strong></summary>

| Tool | Description |
|------|-------------|
| `debug_breakpoint_add` | Add a breakpoint (by symbol or file:line) |
| `debug_breakpoint_remove` | Remove a breakpoint by ID |
| `debug_watchpoint` | Add, remove, or list watchpoints |
| `debug_continue` | Continue execution |
| `debug_step` | Step in, over, out, or by instruction |

</details>

<details>
<summary><strong>Inspection</strong></summary>

| Tool | Description |
|------|-------------|
| `debug_stack` | Print stack trace |
| `debug_variables` | Print local variables |
| `debug_threads` | List threads, optionally switch |
| `debug_evaluate` | Evaluate expressions — `po`, `p`, Swift or ObjC |
| `debug_memory` | Read memory in hex, bytes, ASCII, or disassembly |
| `debug_symbol_lookup` | Look up symbols by address, name, or type |
| `debug_view_hierarchy` | Dump live UI view hierarchy, inspect Auto Layout constraints |
| `debug_view_borders` | Toggle colored borders on all views via LLDB |
| `debug_lldb_command` | Execute arbitrary LLDB command |

</details>

<details>
<summary><strong>Memory diagnostics</strong></summary>

Standalone CLI wrappers — work on any running process by PID or bundle ID.

| Tool | Description |
|------|-------------|
| `memory_leaks` | Detect leaks via `leaks` — counts, sizes, backtraces |
| `memory_heap` | Examine heap via `heap` — objects by class, sorted by size or count |
| `memory_vmmap` | Virtual memory mapping via `vmmap` — dirty/clean/swapped per region |
| `memory_stringdups` | Duplicate strings via `stringdups` — wasted bytes |
| `memory_malloc_history` | Allocation backtrace for an address (requires `MallocStackLogging=1`) |
| `symbolicate_address` | Convert addresses to symbols via `atos` — batch support |

</details>

---

### macOS Builds & Screenshots

14 tools. Build, test, run, screenshot macOS apps. Coverage reports, performance baselines, launch profiling, and build diagnostics.

<details>
<summary><strong>All tools</strong></summary>

| Tool | Description |
|------|-------------|
| `screenshot_mac_window` | Capture any macOS window via ScreenCaptureKit — match by app name, bundle ID, or title |
| `build_macos` | Build a macOS app |
| `build_run_macos` | Build and run |
| `launch_mac_app` | Launch a macOS app |
| `stop_mac_app` | Stop a macOS app |
| `get_mac_app_path` | Get path to built app |
| `test_macos` | Run tests |
| `start_mac_log_cap` | Start capturing logs via unified logging |
| `stop_mac_log_cap` | Stop and return log results |
| `get_test_attachments` | Extract test attachments from `.xcresult` bundles |
| `sample_mac_app` | Sample call stacks via `/usr/bin/sample` |
| `profile_app_launch` | Build, launch, sample startup call stacks |
| `get_coverage_report` | Per-target code coverage from `.xcresult` bundles |
| `get_file_coverage` | Per-function coverage drill-down |
| `get_performance_metrics` | Extract `measure(metrics:)` timing data |
| `set_performance_baseline` | Create `.xcbaseline` plists for regression detection |
| `show_performance_baselines` | Read existing baselines in human-readable form |
| `diagnostics` | Clean-build and collect all warnings, errors, and lint violations |

</details>

**SwiftUI Preview Capture** (1 tool):

| Tool | Description |
|------|-------------|
| `preview_capture` | Extract `#Preview`, build temp host app, launch, screenshot, clean up. Handles mergeable libraries, cross-project deps, local Swift packages, nested struct previews |

---

### Simulators

25 tools. Simulator management, build-and-run, and coordinate-based touch automation via `simctl io`.

<details>
<summary><strong>Simulator management</strong></summary>

| Tool | Description |
|------|-------------|
| `list_sims` | List available simulators |
| `boot_sim` | Boot a simulator |
| `open_sim` | Open Simulator.app |
| `build_sim` | Build for simulator |
| `build_run_sim` | Build and run |
| `install_app_sim` | Install an app |
| `launch_app_sim` | Launch an app |
| `stop_app_sim` | Stop an app |
| `get_sim_app_path` | Get installed app path |
| `test_sim` | Run tests |
| `record_sim_video` | Record video |
| `launch_app_logs_sim` | Launch and capture logs |
| `erase_sims` | Reset a simulator |
| `set_sim_location` | Set simulated location |
| `reset_sim_location` | Reset location |
| `set_sim_appearance` | Light/dark mode |
| `sim_statusbar` | Override status bar |

</details>

<details>
<summary><strong>Touch & gesture automation</strong></summary>

| Tool | Description |
|------|-------------|
| `tap` | Tap at coordinate |
| `long_press` | Long press at coordinate |
| `swipe` | Swipe between points |
| `gesture` | Named presets — `scroll_up`, `pull_to_refresh`, `swipe_from_left_edge`, etc. Coordinates computed from screen dimensions |
| `type_text` | Type text |
| `key_press` | Press hardware key |
| `button` | Press hardware button |
| `screenshot` | Take simulator screenshot |

</details>

---

### Devices

9 tools. Physical iOS device management, including one-call deployment pipelines.

<details>
<summary><strong>All tools</strong></summary>

| Tool | Description |
|------|-------------|
| `list_devices` | List connected devices |
| `build_device` | Build for device |
| `install_app_device` | Install on device |
| `launch_app_device` | Launch on device |
| `stop_app_device` | Stop app — resolves bundle ID to PID via `devicectl` |
| `get_device_app_path` | Get installed app path |
| `test_device` | Run tests on device |
| `deploy_device` | Stop → install → launch (post-build) |
| `build_deploy_device` | Build → stop → install → launch (full pipeline) |

</details>

---

### Project Management

58 tools. Full `.xcodeproj` manipulation — targets, groups, files, schemes, test plans, Swift packages, synchronized folders, build phases, document types, URL types. All through the XcodeProj library, no `xcodebuild` needed.

<details>
<summary><strong>Files & groups</strong></summary>

| Tool | Description |
|------|-------------|
| `add_file` | Add a file — handles `.icon`, `.xcassets`, and files above the xcodeproj directory |
| `remove_file` | Remove a file |
| `move_file` | Move or rename |
| `list_files` | List files in a target — enumerates synchronized folders, respects membership exceptions |
| `create_group` | Create a group |
| `remove_group` | Remove a group |
| `rename_group` | Rename by slash-separated path |
| `list_groups` | List all groups |

</details>

<details>
<summary><strong>Targets</strong></summary>

| Tool | Description |
|------|-------------|
| `create_xcodeproj` | Create a new project |
| `scaffold_ios_project` | iOS project with workspace + SPM architecture |
| `scaffold_macos_project` | macOS project with workspace + SPM architecture |
| `list_targets` | List all targets |
| `add_target` | Create a target |
| `remove_target` | Remove a target |
| `rename_target` | Rename in-place — updates product name, settings, deps, schemes |
| `duplicate_target` | Duplicate a target |
| `add_dependency` | Add inter-target dependency |
| `add_app_extension` | Add App Extension target |
| `remove_app_extension` | Remove App Extension target |
| `scaffold_module` | Create framework module in one call — target + test target + sync folder + dep + embed + test plan |

</details>

<details>
<summary><strong>Build settings & phases</strong></summary>

| Tool | Description |
|------|-------------|
| `list_build_configurations` | List configurations |
| `get_build_settings` | Get build settings for a target |
| `set_build_setting` | Modify build settings |
| `add_framework` | Add framework dependency |
| `remove_framework` | Remove framework — cleans link + embed phases |
| `add_build_phase` | Add custom build phase |
| `add_copy_files_phase` | Create Copy Files build phase |
| `add_to_copy_files_phase` | Add files to Copy Files phase |
| `list_copy_files_phases` | List Copy Files phases |
| `remove_copy_files_phase` | Remove Copy Files phase |
| `validate_project` | Check embed settings, duplicate embeds, missing deps |

</details>

<details>
<summary><strong>Schemes & test plans</strong></summary>

| Tool | Description |
|------|-------------|
| `create_scheme` | Create `.xcscheme` with build, test, and launch actions |
| `rename_scheme` | Rename `.xcscheme` file |
| `validate_scheme` | Check target refs, test plans, configs |
| `create_test_plan` | Generate `.xctestplan` from targets |
| `add_target_to_test_plan` | Add test target to plan |
| `remove_target_from_test_plan` | Remove from plan |
| `set_test_plan_target_enabled` | Enable/disable without removing |
| `set_test_plan_skipped_tags` | Set skipped test tags |
| `add_test_plan_to_scheme` | Add plan to scheme's TestAction |
| `remove_test_plan_from_scheme` | Remove plan from scheme |
| `list_test_plans` | Find all `.xctestplan` files |
| `set_test_target_application` | Set target app for UI tests |

</details>

<details>
<summary><strong>Swift packages</strong></summary>

| Tool | Description |
|------|-------------|
| `add_swift_package` | Add remote (URL + version) or local package |
| `list_swift_packages` | List package dependencies |
| `remove_swift_package` | Remove package + optionally its product deps |
| `add_package_product` | Add package product to target |
| `remove_package_product` | Remove package product |
| `list_package_products` | List products |

</details>

<details>
<summary><strong>Synchronized folders</strong></summary>

| Tool | Description |
|------|-------------|
| `add_synchronized_folder` | Add folder reference |
| `remove_synchronized_folder` | Remove folder reference |
| `add_target_to_synchronized_folder` | Share folder with another target |
| `remove_target_from_synchronized_folder` | Unlink folder from target |
| `add_synchronized_folder_exception` | Exclude files from a target |
| `remove_synchronized_folder_exception` | Remove exclusion |
| `list_synchronized_folder_exceptions` | List all exclusions |

</details>

<details>
<summary><strong>Document types & URL schemes</strong></summary>

| Tool | Description |
|------|-------------|
| `list_document_types` | List `CFBundleDocumentTypes` |
| `manage_document_type` | Add, update, or remove document type |
| `list_type_identifiers` | List UTI declarations |
| `manage_type_identifier` | Add, update, or remove UTI |
| `list_url_types` | List URL schemes |
| `manage_url_type` | Add, update, or remove URL scheme |

</details>

---

### Icon Composition

9 tools. Create and edit Apple's Icon Composer `.icon` bundles — multi-layer icons with fills, glass effects, shadows, translucency, and dark mode variants. Render to PNG via `ictool`. Add to Xcode projects with the correct `lastKnownFileType`.

<details>
<summary><strong>All tools</strong></summary>

| Tool | Description |
|------|-------------|
| `create_icon` | Create `.icon` bundle from a PNG — fill, effects, dark mode, optional Xcode project wiring |
| `export_icon` | Render `.icon` to PNG via `ictool` — platform, rendition, size, scale, tint |
| `read_icon` | Inspect bundle — manifest summary, asset list, raw JSON |
| `add_icon_layer` | Add image layer to existing bundle — new group or append to existing |
| `remove_icon_layer` | Remove layer or group — auto-purges unreferenced assets |
| `set_icon_fill` | Set background — solid, automatic gradient, linear gradient, or clear |
| `set_icon_effects` | Configure group effects — specular, shadow, translucency, blur, lighting |
| `set_icon_layer_position` | Adjust scale and offset of a layer or group |
| `set_icon_appearances` | Dark/tinted mode fill specializations |

</details>

---

### Swift Packages

12 tools. SPM operations, formatting, linting, and unused code detection.

<details>
<summary><strong>All tools</strong></summary>

| Tool | Description |
|------|-------------|
| `swift_package_build` | Build a Swift package |
| `swift_package_test` | Run tests |
| `swift_package_run` | Run executable |
| `swift_package_clean` | Clean build artifacts |
| `swift_package_list` | List dependencies |
| `swift_package_stop` | Stop running executable |
| `swift_format` | Run swiftformat — supports dry_run |
| `swift_lint` | Run swiftlint — supports fix mode |
| `swift_diagnostics` | Clean-build and collect all compiler warnings and lint violations |
| `detect_unused_code` | Find unused code via [Periphery](https://github.com/peripheryapp/periphery) — summary, detail, or checklist format |
| `get_coverage_report` | Per-target coverage from `.xcresult` |
| `get_file_coverage` | Per-function coverage drill-down |
| `swift_symbols` | Search Swift symbols |

</details>

---

### Localization

24 tools. Full CRUD for Apple's `.xcstrings` format — keys, translations, coverage stats, stale key detection. Batch operations are atomic.

<details>
<summary><strong>Read operations</strong></summary>

| Tool | Description |
|------|-------------|
| `xcstrings_list_keys` | List all keys |
| `xcstrings_list_languages` | List all languages |
| `xcstrings_list_untranslated` | Untranslated keys for a language |
| `xcstrings_list_stale` | Keys with "stale" extraction state |
| `xcstrings_get_source_language` | Get source language |
| `xcstrings_get_key` | Get translations for a key |
| `xcstrings_check_key` | Check if key exists |
| `xcstrings_check_coverage` | Coverage for a specific key |
| `xcstrings_batch_check_keys` | Check multiple keys |
| `xcstrings_stats_coverage` | Overall coverage statistics |
| `xcstrings_stats_progress` | Progress for a language |
| `xcstrings_batch_stats_coverage` | Coverage for multiple files |
| `xcstrings_batch_list_stale` | Stale keys across multiple files |

</details>

<details>
<summary><strong>Write operations</strong></summary>

| Tool | Description |
|------|-------------|
| `xcstrings_create_file` | Create new `.xcstrings` file |
| `xcstrings_add_translation` | Add single translation |
| `xcstrings_add_translations` | Add multiple translations for one key |
| `xcstrings_batch_add_translations` | Add translations for multiple keys atomically |
| `xcstrings_update_translation` | Update single translation |
| `xcstrings_update_translations` | Update multiple for one key |
| `xcstrings_batch_update_translations` | Update multiple keys atomically |
| `xcstrings_rename_key` | Rename a key |
| `xcstrings_delete_key` | Delete key and all translations |
| `xcstrings_delete_translation` | Delete single translation |
| `xcstrings_delete_translations` | Delete multiple translations |

</details>

---

### Session & Utilities

12 tools. Project paths are auto-detected from the working directory — the server walks up from `cwd` looking for `Package.swift`, `.xcodeproj`, or `.xcworkspace`.

<details>
<summary><strong>Session management</strong></summary>

| Tool | Description |
|------|-------------|
| `set_session_defaults` | Set default project, scheme, simulator, device, config, env vars. Env vars deep-merge and apply to all commands |
| `show_session_defaults` | Show current defaults |
| `clear_session_defaults` | Clear all defaults |
| `sync_xcode_defaults` | Read active scheme and run destination from Xcode's IDE state |
| `manage_workflows` | Enable/disable tool categories at runtime |

</details>

<details>
<summary><strong>Discovery</strong></summary>

| Tool | Description |
|------|-------------|
| `discover_projs` | Discover projects and workspaces |
| `list_schemes` | List all schemes |
| `show_build_settings` | Show build settings for a scheme |
| `get_app_bundle_id` | Bundle ID for iOS/watchOS/tvOS app |
| `get_mac_bundle_id` | Bundle ID for macOS app |
| `list_test_plan_targets` | Test targets from a scheme's test plans |

</details>

<details>
<summary><strong>Distribution & diagnostics</strong></summary>

| Tool | Description |
|------|-------------|
| `clean` | Clean build products |
| `doctor` | Diagnose Xcode environment — Xcode, CLT, SDKs, DerivedData, sessions |
| `search_crash_reports` | Search `~/Library/Logs/DiagnosticReports/` for recent crashes |
| `version_management` | Read/set/bump marketing version and build numbers via `agvtool` |
| `notarize` | Full notarization pipeline — submit, wait, check, log, staple |
| `validate_asset_catalog` | Validate `.xcassets` via `actool` |
| `open_in_xcode` | Open file or project in Xcode, optionally at a line number |

</details>

<details>
<summary><strong>Instruments</strong></summary>

| Tool | Description |
|------|-------------|
| `xctrace_list` | List Instruments templates, instruments, or devices |
| `xctrace_record` | Start/stop Instruments trace recording |
| `xctrace_export` | Export `.trace` data as XML |

</details>

<details>
<summary><strong>Logging</strong></summary>

| Tool | Description |
|------|-------------|
| `start_sim_log_cap` | Start capturing simulator logs |
| `stop_sim_log_cap` | Stop and return results |
| `start_device_log_cap` | Start capturing device logs |
| `stop_device_log_cap` | Stop and return results |

</details>

---

## macOS Permissions

Some tools require macOS privacy permissions granted via **System Settings > Privacy & Security**:

| Permission | Tools | Notes |
|-----------|-------|-------|
| **Accessibility** | `interact_*` tools | Required for AXUIElement API |
| **Screen Recording** | `screenshot_mac_window` | Required for ScreenCaptureKit |

macOS grants these to the **responsible process** — the GUI app at the top of the process tree, not `xc-mcp` itself. So **Claude Desktop**, **VS Code/Cursor**, or your **terminal emulator** needs the permission. The `xc-mcp` binary won't appear in System Settings — TCC always resolves up to the parent GUI app.

## Build Output Parsing

Test tools parse both **XCTest** and **Swift Testing** output formats, extracting structured pass/fail results with test names, durations, and failure details. Handles parallel output, backtick-escaped function names, SF Symbol prefixes, and failure summaries.

## Tests

826 tests — fast unit tests with in-memory fixtures and mock runners, plus integration tests that build and screenshot real open-source projects.

```bash
# Unit tests (fast, no Xcode projects needed)
swift test

# Integration tests (requires fixture repos)
./scripts/fetch-fixtures.sh   # ~1 minute, idempotent
swift test --filter Integration
```

Integration tests run against [Alamofire](https://github.com/Alamofire/Alamofire), [SwiftFormat](https://github.com/nicklockwood/SwiftFormat), and [IceCubesApp](https://github.com/Dimillian/IceCubesApp), each pinned to a specific commit. Without fixture repos, they auto-skip.

## Path Security

When providing a base path as a command-line argument, all file operations are restricted to that directory.

## License

MIT License. See [LICENSE](LICENSE) for details.

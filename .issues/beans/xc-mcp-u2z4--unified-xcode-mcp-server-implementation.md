---
# xc-mcp-u2z4
title: Unified Xcode MCP Server Implementation
status: completed
type: milestone
priority: normal
created_at: 2026-01-21T05:03:16Z
updated_at: 2026-01-21T05:03:16Z
sync:
    github:
        issue_number: "19"
        synced_at: "2026-02-15T22:08:23Z"
---

Merge xcodeproj-mcp-server (23 tools) with XcodeBuildMCP (71 tools) into a single Swift-based MCP server with full feature parity (~94 tools).

## Final Status
- **93 tools implemented** (23 original + 70 new)
- All phases complete
- All tests pass (166 tests)
- Swift 6 strict concurrency enabled
- README and CLAUDE.md updated

## Key Files Created
- Sources/XcodeMCP/Server/SessionManager.swift - Session state management
- Sources/XcodeMCP/Server/XcodeMCPServer.swift - Main server with tool registry
- Sources/XcodeMCP/Utilities/XcodebuildRunner.swift - xcodebuild wrapper
- Sources/XcodeMCP/Utilities/SimctlRunner.swift - simctl wrapper
- Sources/XcodeMCP/Utilities/DeviceCtlRunner.swift - devicectl wrapper
- Sources/XcodeMCP/Utilities/LLDBRunner.swift - LLDB wrapper
- Sources/XcodeMCP/Utilities/SwiftRunner.swift - Swift CLI wrapper
- Sources/XcodeMCP/Tools/Session/*.swift - 3 session tools
- Sources/XcodeMCP/Tools/Simulator/*.swift - 17 simulator tools
- Sources/XcodeMCP/Tools/Device/*.swift - 7 device tools
- Sources/XcodeMCP/Tools/MacOS/*.swift - 6 macOS tools
- Sources/XcodeMCP/Tools/Discovery/*.swift - 5 discovery tools
- Sources/XcodeMCP/Tools/Logging/*.swift - 4 logging tools
- Sources/XcodeMCP/Tools/Debug/*.swift - 8 debug tools
- Sources/XcodeMCP/Tools/UIAutomation/*.swift - 7 UI automation tools
- Sources/XcodeMCP/Tools/SwiftPackage/*.swift - 6 SPM tools
- Sources/XcodeMCP/Tools/Utility/*.swift - 4 utility tools

## Checklist

### Phase 1: Foundation & Session Management
- [x] Rename package from xcodeproj-mcp-server to xcode-mcp
- [x] Create SessionManager.swift
- [x] Implement set_session_defaults tool
- [x] Implement show_session_defaults tool
- [x] Implement clear_session_defaults tool
- [x] Create XcodebuildRunner utility

### Phase 2: Simulator Management (12 tools)
- [x] Create SimctlRunner utility
- [x] list_sims tool
- [x] boot_sim tool
- [x] open_sim tool
- [x] build_sim tool
- [x] build_run_sim tool
- [x] install_app_sim tool
- [x] launch_app_sim tool
- [x] stop_app_sim tool
- [x] get_sim_app_path tool
- [x] test_sim tool
- [x] record_sim_video tool
- [x] launch_app_logs_sim tool

### Phase 3: Device Management (7 tools)
- [x] Create DeviceCtlRunner utility
- [x] list_devices tool
- [x] build_device tool
- [x] install_app_device tool
- [x] launch_app_device tool
- [x] stop_app_device tool
- [x] get_device_app_path tool
- [x] test_device tool

### Phase 4: macOS Build Tools (6 tools)
- [x] build_macos tool
- [x] build_run_macos tool
- [x] launch_mac_app tool
- [x] stop_mac_app tool
- [x] get_mac_app_path tool
- [x] test_macos tool

### Phase 5: Project Discovery (5 tools)
- [x] discover_projs tool
- [x] list_schemes tool
- [x] show_build_settings tool
- [x] get_app_bundle_id tool
- [x] get_mac_bundle_id tool

### Phase 6: Log Capture (4 tools)
- [x] start_sim_log_cap tool
- [x] stop_sim_log_cap tool
- [x] start_device_log_cap tool
- [x] stop_device_log_cap tool

### Phase 7: Simulator Management Extended (5 tools)
- [x] erase_sims tool
- [x] set_sim_location tool
- [x] reset_sim_location tool
- [x] set_sim_appearance tool
- [x] sim_statusbar tool

### Phase 8: LLDB Debugging (8 tools)
- [x] Create LLDBRunner utility
- [x] debug_attach_sim tool
- [x] debug_detach tool
- [x] debug_breakpoint_add tool
- [x] debug_breakpoint_remove tool
- [x] debug_continue tool
- [x] debug_stack tool
- [x] debug_variables tool
- [x] debug_lldb_command tool

### Phase 9: UI Automation (7 tools)
- [x] tap tool
- [x] long_press tool
- [x] swipe tool
- [x] type_text tool
- [x] key_press tool
- [x] button tool
- [x] screenshot tool

### Phase 10: Swift Package Manager (6 tools)
- [x] SwiftRunner utility
- [x] swift_package_build tool
- [x] swift_package_test tool
- [x] swift_package_run tool
- [x] swift_package_clean tool
- [x] swift_package_list tool
- [x] swift_package_stop tool

### Phase 11: Utilities (4 tools)
- [x] clean tool
- [x] doctor tool
- [x] scaffold_ios_project tool
- [x] scaffold_macos_project tool

### Final Steps
- [x] Update README documentation
- [x] Ensure all tests pass (166 tests)
- [x] Format codebase
- [x] Update CLAUDE.md

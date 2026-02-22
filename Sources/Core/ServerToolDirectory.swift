/// Maps tool names to their home focused server, enabling cross-server hints
/// when an agent calls a tool that exists in a different server.
public enum ServerToolDirectory {
    /// Returns a hint string if the tool exists in another server, nil otherwise.
    public static func hint(for toolName: String, currentServer: String) -> String? {
        guard let server = toolToServer[toolName], server != currentServer else { return nil }
        return "This tool is available in the '\(server)' server."
    }

    // MARK: - Tool → Server mapping

    private static let toolToServer: [String: String] = {
        var map = [String: String]()
        map.reserveCapacity(
            buildTools.count + simulatorTools.count + debugTools.count
                + projectTools.count + deviceTools.count + swiftTools.count + stringsTools.count,
        )
        for name in buildTools {
            map[name] = "xc-build"
        }
        for name in simulatorTools {
            map[name] = "xc-simulator"
        }
        for name in debugTools {
            map[name] = "xc-debug"
        }
        for name in projectTools {
            map[name] = "xc-project"
        }
        for name in deviceTools {
            map[name] = "xc-device"
        }
        for name in swiftTools {
            map[name] = "xc-swift"
        }
        for name in stringsTools {
            map[name] = "xc-strings"
        }
        return map
    }()

    // Keep these in sync with each server's ToolName enum.

    private static let buildTools: [String] = [
        "build_macos", "build_run_macos", "launch_mac_app", "stop_mac_app",
        "get_mac_app_path", "test_macos", "start_mac_log_cap", "stop_mac_log_cap",
        "discover_projs", "list_schemes", "show_build_settings",
        "get_app_bundle_id", "get_mac_bundle_id", "list_test_plan_targets",
        "clean", "doctor", "scaffold_ios_project", "scaffold_macos_project",
    ]

    private static let simulatorTools: [String] = [
        "list_sims", "boot_sim", "open_sim", "build_sim", "build_run_sim",
        "install_app_sim", "launch_app_sim", "stop_app_sim", "get_sim_app_path",
        "test_sim", "record_sim_video", "launch_app_logs_sim", "erase_sims",
        "set_sim_location", "reset_sim_location", "set_sim_appearance", "sim_statusbar",
        "tap", "long_press", "swipe", "type_text", "key_press",
        "button", "screenshot",
        "start_sim_log_cap", "stop_sim_log_cap",
    ]

    private static let debugTools: [String] = [
        "build_debug_macos", "debug_attach_sim", "debug_detach",
        "debug_breakpoint_add", "debug_breakpoint_remove",
        "debug_continue", "debug_stack", "debug_variables",
        "debug_lldb_command", "debug_evaluate", "debug_threads",
        "debug_watchpoint", "debug_step", "debug_memory",
        "debug_symbol_lookup", "debug_view_hierarchy",
        "debug_view_borders", "debug_process_status",
        "screenshot_mac_window",
    ]

    private static let projectTools: [String] = [
        "create_xcodeproj", "list_targets", "list_build_configurations",
        "list_files", "get_build_settings", "add_file", "remove_file", "move_file",
        "create_group", "remove_group", "add_target", "remove_target",
        "rename_target", "rename_scheme", "create_scheme", "validate_scheme",
        "create_test_plan", "add_target_to_test_plan", "remove_target_from_test_plan",
        "set_test_plan_target_enabled", "add_test_plan_to_scheme",
        "remove_test_plan_from_scheme", "list_test_plans",
        "set_test_target_application", "rename_group",
        "add_dependency", "set_build_setting", "add_framework", "add_build_phase",
        "duplicate_target", "add_swift_package", "list_swift_packages",
        "remove_swift_package", "list_groups",
        "add_synchronized_folder", "remove_synchronized_folder",
        "add_app_extension", "remove_app_extension",
        "add_target_to_synchronized_folder", "remove_target_from_synchronized_folder",
        "add_synchronized_folder_exception", "remove_synchronized_folder_exception",
        "list_synchronized_folder_exceptions",
        "list_copy_files_phases", "add_copy_files_phase",
        "add_to_copy_files_phase", "remove_copy_files_phase",
        "list_document_types", "manage_document_type",
        "list_type_identifiers", "manage_type_identifier",
        "list_url_types", "manage_url_type",
    ]

    private static let deviceTools: [String] = [
        "list_devices", "build_device", "install_app_device",
        "launch_app_device", "stop_app_device", "get_device_app_path", "test_device",
        "start_device_log_cap", "stop_device_log_cap",
    ]

    private static let swiftTools: [String] = [
        "swift_package_build", "swift_package_test", "swift_package_run",
        "swift_package_clean", "swift_package_list", "swift_package_stop",
    ]

    private static let stringsTools: [String] = [
        "xcstrings_list_keys", "xcstrings_list_languages", "xcstrings_list_untranslated",
        "xcstrings_get_source_language", "xcstrings_get_key", "xcstrings_check_key",
        "xcstrings_stats_coverage", "xcstrings_stats_progress",
        "xcstrings_batch_stats_coverage",
        "xcstrings_create_file", "xcstrings_add_translation", "xcstrings_add_translations",
        "xcstrings_update_translation", "xcstrings_update_translations",
        "xcstrings_rename_key", "xcstrings_delete_key",
        "xcstrings_delete_translation", "xcstrings_delete_translations",
        "xcstrings_list_stale", "xcstrings_batch_list_stale",
        "xcstrings_batch_check_keys", "xcstrings_batch_add_translations",
        "xcstrings_batch_update_translations", "xcstrings_check_coverage",
    ]
}

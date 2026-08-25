import MCP
import XCMCPCore

extension ToolRegistry {
    /// Utility tools.
    static let utility: [ToolRegistration] = [
    ToolRegistration("add_icon_layer", .utility, [.monolith, .build]) { deps in
        let tool = AddIconLayerTool()
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("audit_build_settings", .utility, [.monolith, .build]) { deps in
        let tool = AuditBuildSettingsTool(xcodebuildRunner: deps.xcodebuild, sessionManager: deps.session, pathUtility: deps.paths)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("benchmark_build", .utility, [.monolith, .build]) { deps in
        let tool = BenchmarkBuildTool(xcodebuildRunner: deps.xcodebuild, sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("check_output_file_map", .utility, [.monolith, .build]) { deps in
        let tool = CheckOutputFileMapTool(xcodebuildRunner: deps.xcodebuild, sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("clean", .utility, [.monolith, .build]) { deps in
        let tool = CleanTool(xcodebuildRunner: deps.xcodebuild, sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("create_icon", .utility, [.monolith, .build]) { deps in
        let tool = CreateIconTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("diagnostics", .utility, [.monolith, .build]) { deps in
        let tool = DiagnosticsTool(xcodebuildRunner: deps.xcodebuild, sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("diff_build_settings", .utility, [.monolith, .build]) { deps in
        let tool = DiffBuildSettingsTool(xcodebuildRunner: deps.xcodebuild, sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("doctor", .utility, [.monolith, .build]) { deps in
        let tool = DoctorTool(sessionManager: deps.session)
        return (tool.tool(), { await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("export_icon", .utility, [.monolith, .build]) { deps in
        let tool = ExportIconTool()
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("extract_crash_traces", .utility, [.monolith, .build]) { deps in
        let tool = ExtractCrashTracesTool(xcodebuildRunner: deps.xcodebuild, sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("find_compile_hotspots", .utility, [.monolith, .build]) { deps in
        let tool = FindCompileHotspotsTool(xcodebuildRunner: deps.xcodebuild, sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("list_build_phase_status", .utility, [.monolith, .build]) { deps in
        let tool = ListBuildPhaseStatusTool(xcodebuildRunner: deps.xcodebuild, sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("notarize", .utility, [.monolith, .build]) { deps in
        let tool = NotarizeTool()
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("open_in_xcode", .utility, [.monolith, .build]) { deps in
        let tool = OpenInXcodeTool()
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("read_icon", .utility, [.monolith, .build]) { deps in
        let tool = ReadIconTool()
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("read_serialized_diagnostics", .utility, [.monolith, .build]) { deps in
        let tool = ReadSerializedDiagnosticsTool(xcodebuildRunner: deps.xcodebuild, sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("remove_icon_layer", .utility, [.monolith, .build]) { deps in
        let tool = RemoveIconLayerTool()
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("scaffold_ios_project", .utility, [.monolith, .build]) { deps in
        let tool = ScaffoldIOSProjectTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("scaffold_macos_project", .utility, [.monolith, .build]) { deps in
        let tool = ScaffoldMacOSProjectTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("search_crash_reports", .utility, [.monolith, .build]) { deps in
        let tool = SearchCrashReportsTool()
        return (tool.tool(), { tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("set_icon_appearances", .utility, [.monolith, .build]) { deps in
        let tool = SetIconAppearancesTool()
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("set_icon_effects", .utility, [.monolith, .build]) { deps in
        let tool = SetIconEffectsTool()
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("set_icon_fill", .utility, [.monolith, .build]) { deps in
        let tool = SetIconFillTool()
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("set_icon_layer_position", .utility, [.monolith, .build]) { deps in
        let tool = SetIconLayerPositionTool()
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("show_build_dependency_graph", .utility, [.monolith, .build]) { deps in
        let tool = ShowBuildDependencyGraphTool(xcodebuildRunner: deps.xcodebuild, sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("validate_asset_catalog", .utility, [.monolith, .build]) { deps in
        let tool = ValidateAssetCatalogTool()
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("version_management", .utility, [.monolith, .build]) { deps in
        let tool = VersionManagementTool()
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("profile_app_launch", .instruments, [.monolith, .build]) { deps in
        let tool = ProfileAppLaunchTool(xcodebuildRunner: deps.xcodebuild, xctraceRunner: deps.xctrace, sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("sample_mac_app", .instruments, [.monolith, .build]) { deps in
        let tool = SampleMacAppTool()
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("xctrace_export", .instruments, [.monolith]) { deps in
        let tool = XctraceExportTool(xctraceRunner: deps.xctrace)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("xctrace_list", .instruments, [.monolith]) { deps in
        let tool = XctraceListTool(xctraceRunner: deps.xctrace)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("xctrace_record", .instruments, [.monolith]) { deps in
        let tool = XctraceRecordTool(xctraceRunner: deps.xctrace, sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ]
}

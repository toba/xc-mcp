import MCP
import XCMCPCore

extension ToolRegistry {
    /// MacOS tools.
    static let macOS: [ToolRegistration] = [
    ToolRegistration("analyze_app_bundle", .macos, [.monolith, .build]) { deps in
        let tool = AnalyzeAppBundleTool(xcodebuildRunner: deps.xcodebuild, sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("archive", .macos, [.monolith, .build]) { deps in
        let tool = ArchiveTool(xcodebuildRunner: deps.xcodebuild, sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("build_macos", .macos, [.monolith, .build]) { deps in
        let tool = BuildMacOSTool(xcodebuildRunner: deps.xcodebuild, sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("build_run_macos", .macos, [.monolith, .build]) { deps in
        let tool = BuildRunMacOSTool(xcodebuildRunner: deps.xcodebuild, sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("export_archive", .macos, [.monolith, .build]) { deps in
        let tool = ExportArchiveTool(xcodebuildRunner: deps.xcodebuild)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("get_coverage_report", .macos, [.monolith, .build, .swift]) { deps in
        let tool = GetCoverageReportTool()
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("get_file_coverage", .macos, [.monolith, .build, .swift]) { deps in
        let tool = GetFileCoverageTool()
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("get_mac_app_path", .macos, [.monolith, .build]) { deps in
        let tool = GetMacAppPathTool(xcodebuildRunner: deps.xcodebuild, sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("get_performance_metrics", .macos, [.monolith, .build]) { deps in
        let tool = GetPerformanceMetricsTool()
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("get_test_attachments", .macos, [.monolith, .build]) { deps in
        let tool = GetTestAttachmentsTool()
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("launch_mac_app", .macos, [.monolith, .build]) { deps in
        let tool = LaunchMacAppTool(sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("screenshot_mac_window", .macos, [.monolith, .debug]) { deps in
        let tool = ScreenshotMacWindowTool()
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("set_performance_baseline", .macos, [.monolith, .build]) { deps in
        let tool = SetPerformanceBaselineTool(sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("show_build_log", .macos, [.monolith, .build]) { deps in
        let tool = ShowBuildLogTool(xcodebuildRunner: deps.xcodebuild, sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("show_last_build_raw", .macos, [.monolith, .build, .swift]) { deps in
        let tool = ShowLastBuildRawTool()
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("show_mac_log", .macos, [.monolith, .build]) { deps in
        let tool = ShowMacLogTool(sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("show_performance_baselines", .macos, [.monolith, .build]) { deps in
        let tool = ShowPerformanceBaselinesTool(sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("start_mac_log_cap", .macos, [.monolith, .build]) { deps in
        let tool = StartMacLogCapTool(sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("stop_mac_app", .macos, [.monolith, .build]) { deps in
        let tool = StopMacAppTool(sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("stop_mac_log_cap", .macos, [.monolith, .build]) { deps in
        let tool = StopMacLogCapTool(sessionManager: deps.session)
        return (tool.tool(), { await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("test_macos", .macos, [.monolith, .build]) { deps in
        let tool = TestMacOSTool(xcodebuildRunner: deps.xcodebuild, sessionManager: deps.session)
        return (tool.tool(), { call in
            try await call.withProgress { onProgress in
                try await tool.execute(arguments: call.arguments, onProgress: onProgress)
            }
        })
    },
    ToolRegistration("discover_projs", .discovery, [.monolith, .build]) { deps in
        let tool = DiscoverProjectsTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("get_app_bundle_id", .discovery, [.monolith, .build]) { deps in
        let tool = GetAppBundleIDTool(xcodebuildRunner: deps.xcodebuild, sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("get_mac_bundle_id", .discovery, [.monolith, .build]) { deps in
        let tool = GetMacBundleIDTool(xcodebuildRunner: deps.xcodebuild, sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("list_schemes", .discovery, [.monolith, .build]) { deps in
        let tool = ListSchemesTool(xcodebuildRunner: deps.xcodebuild, sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("list_test_plan_targets", .discovery, [.monolith, .build]) { deps in
        let tool = ListTestPlanTargetsTool(xcodebuildRunner: deps.xcodebuild, sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("show_build_settings", .discovery, [.monolith, .build]) { deps in
        let tool = ShowBuildSettingsTool(xcodebuildRunner: deps.xcodebuild, sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("swift_symbols", .discovery, [.monolith, .swift]) { deps in
        let tool = SwiftSymbolsTool()
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ]
}

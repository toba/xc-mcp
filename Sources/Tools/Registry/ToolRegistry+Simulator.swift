import MCP
import XCMCPCore

extension ToolRegistry {
    /// Simulator tools.
    static let simulator: [ToolRegistration] = [
    ToolRegistration("boot_sim", .simulator, [.monolith, .simulator]) { deps in
        let tool = BootSimTool(simctlRunner: deps.simctl)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("build_run_sim", .simulator, [.monolith, .simulator]) { deps in
        let tool = BuildRunSimTool(xcodebuildRunner: deps.xcodebuild, simctlRunner: deps.simctl, sessionManager: deps.session)
        return (tool.tool(), { call in
            try await call.withProgress { onProgress in
                try await tool.execute(arguments: call.arguments, onProgress: onProgress)
            }
        })
    },
    ToolRegistration("build_sim", .simulator, [.monolith, .simulator]) { deps in
        let tool = BuildSimTool(xcodebuildRunner: deps.xcodebuild, sessionManager: deps.session)
        return (tool.tool(), { call in
            try await call.withProgress { onProgress in
                try await tool.execute(arguments: call.arguments, onProgress: onProgress)
            }
        })
    },
    ToolRegistration("erase_sims", .simulator, [.monolith, .simulator]) { deps in
        let tool = EraseSimTool(simctlRunner: deps.simctl, sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("get_sim_app_path", .simulator, [.monolith, .simulator]) { deps in
        let tool = GetSimAppPathTool(simctlRunner: deps.simctl, sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("install_app_sim", .simulator, [.monolith, .simulator]) { deps in
        let tool = InstallAppSimTool(simctlRunner: deps.simctl, sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("launch_app_logs_sim", .simulator, [.monolith, .simulator]) { deps in
        let tool = LaunchAppLogsSimTool(simctlRunner: deps.simctl, sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("launch_app_sim", .simulator, [.monolith, .simulator]) { deps in
        let tool = LaunchAppSimTool(simctlRunner: deps.simctl, sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("list_sims", .simulator, [.monolith, .simulator]) { deps in
        let tool = ListSimsTool(simctlRunner: deps.simctl)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("open_sim", .simulator, [.monolith, .simulator]) { deps in
        let tool = OpenSimTool()
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("preview_capture", .simulator, [.monolith]) { deps in
        let tool = PreviewCaptureTool(xcodebuildRunner: deps.xcodebuild, simctlRunner: deps.simctl, pathUtility: deps.paths, sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("record_sim_video", .simulator, [.monolith, .simulator]) { deps in
        let tool = RecordSimVideoTool(simctlRunner: deps.simctl, sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("reset_sim_location", .simulator, [.monolith, .simulator]) { deps in
        let tool = ResetSimLocationTool(simctlRunner: deps.simctl, sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("set_sim_appearance", .simulator, [.monolith, .simulator]) { deps in
        let tool = SetSimAppearanceTool(simctlRunner: deps.simctl, sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("set_sim_location", .simulator, [.monolith, .simulator]) { deps in
        let tool = SetSimLocationTool(simctlRunner: deps.simctl, sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("sim_statusbar", .simulator, [.monolith, .simulator]) { deps in
        let tool = SimStatusBarTool(simctlRunner: deps.simctl, sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("stop_app_sim", .simulator, [.monolith, .simulator]) { deps in
        let tool = StopAppSimTool(simctlRunner: deps.simctl, sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("test_sim", .simulator, [.monolith, .simulator]) { deps in
        let tool = TestSimTool(xcodebuildRunner: deps.xcodebuild, sessionManager: deps.session)
        return (tool.tool(), { call in
            try await call.withProgress { onProgress in
                try await tool.execute(arguments: call.arguments, onProgress: onProgress)
            }
        })
    },
    ToolRegistration("toggle_hardware_keyboard", .simulator, [.monolith, .simulator]) { deps in
        let tool = ToggleHardwareKeyboardTool(simctlRunner: deps.simctl, sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("toggle_software_keyboard", .simulator, [.monolith, .simulator]) { deps in
        let tool = ToggleSoftwareKeyboardTool(simctlRunner: deps.simctl, sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("button", .uiAutomation, [.monolith, .simulator]) { deps in
        let tool = ButtonTool(uiInput: deps.simulatorInput, sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("gesture", .uiAutomation, [.monolith]) { deps in
        let tool = GestureTool(uiInput: deps.simulatorInput, sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("key_press", .uiAutomation, [.monolith, .simulator]) { deps in
        let tool = KeyPressTool(uiInput: deps.simulatorInput, sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("long_press", .uiAutomation, [.monolith, .simulator]) { deps in
        let tool = LongPressTool(uiInput: deps.simulatorInput, sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("screenshot", .uiAutomation, [.monolith, .simulator]) { deps in
        let tool = ScreenshotTool(simctlRunner: deps.simctl, sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("swipe", .uiAutomation, [.monolith, .simulator]) { deps in
        let tool = SwipeTool(uiInput: deps.simulatorInput, sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("tap", .uiAutomation, [.monolith, .simulator]) { deps in
        let tool = TapTool(uiInput: deps.simulatorInput, sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("type_text", .uiAutomation, [.monolith, .simulator]) { deps in
        let tool = TypeTextTool(uiInput: deps.simulatorInput, sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ]
}

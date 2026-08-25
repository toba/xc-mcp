import MCP
import XCMCPCore

extension ToolRegistry {
    /// Session tools.
    static let session: [ToolRegistration] = [
    ToolRegistration("clear_session_defaults", .session, [.monolith, .build, .debug, .device, .simulator, .swift]) { deps in
        let tool = ClearSessionDefaultsTool(sessionManager: deps.session)
        return (tool.tool(), { await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("manage_workflows", .session, [.monolith], ignoresWorkflowGate: true) { deps in
        let tool = ManageWorkflowsTool(workflowManager: deps.workflows)
        return (tool.tool(), { call in
            let (result, changed) = try await tool.execute(arguments: call.arguments)
            // the visible tool list shrinks or grows whenever a workflow is toggled
            if changed { try await deps.notifyToolListChanged() }
            return result
        })
    },
    ToolRegistration("set_session_defaults", .session, [.monolith, .build, .debug, .device, .simulator, .swift]) { deps in
        let tool = SetSessionDefaultsTool(sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("show_session_defaults", .session, [.monolith, .build, .debug, .device, .simulator, .swift]) { deps in
        let tool = ShowSessionDefaultsTool(sessionManager: deps.session)
        return (tool.tool(), { await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("sync_xcode_defaults", .session, [.monolith]) { deps in
        let tool = SyncXcodeDefaultsTool(sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("start_device_log_cap", .logging, [.monolith, .device]) { deps in
        let tool = StartDeviceLogCapTool(deviceCtlRunner: deps.devicectl, sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("start_sim_log_cap", .logging, [.monolith, .simulator]) { deps in
        let tool = StartSimLogCapTool(simctlRunner: deps.simctl, sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("stop_device_log_cap", .logging, [.monolith, .device]) { deps in
        let tool = StopDeviceLogCapTool(sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("stop_sim_log_cap", .logging, [.monolith, .simulator]) { deps in
        let tool = StopSimLogCapTool(sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ]
}

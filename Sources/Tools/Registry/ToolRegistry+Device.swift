import MCP
import XCMCPCore

extension ToolRegistry {
    /// Device tools.
    static let device: [ToolRegistration] = [
    ToolRegistration("build_deploy_device", .device, [.monolith, .device]) { deps in
        let tool = BuildDeployDeviceTool(xcodebuildRunner: deps.xcodebuild, deviceCtlRunner: deps.devicectl, sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("build_device", .device, [.monolith, .device]) { deps in
        let tool = BuildDeviceTool(xcodebuildRunner: deps.xcodebuild, sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("deploy_device", .device, [.monolith, .device]) { deps in
        let tool = DeployDeviceTool(deviceCtlRunner: deps.devicectl, sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("get_device_app_path", .device, [.monolith, .device]) { deps in
        let tool = GetDeviceAppPathTool(deviceCtlRunner: deps.devicectl, sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("install_app_device", .device, [.monolith, .device]) { deps in
        let tool = InstallAppDeviceTool(deviceCtlRunner: deps.devicectl, sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("launch_app_device", .device, [.monolith, .device]) { deps in
        let tool = LaunchAppDeviceTool(deviceCtlRunner: deps.devicectl, sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("list_devices", .device, [.monolith, .device]) { deps in
        let tool = ListDevicesTool(deviceCtlRunner: deps.devicectl)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("stop_app_device", .device, [.monolith, .device]) { deps in
        let tool = StopAppDeviceTool(deviceCtlRunner: deps.devicectl, sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("test_device", .device, [.monolith, .device]) { deps in
        let tool = TestDeviceTool(xcodebuildRunner: deps.xcodebuild, sessionManager: deps.session)
        return (tool.tool(), { call in
            try await call.withProgress { onProgress in
                try await tool.execute(arguments: call.arguments, onProgress: onProgress)
            }
        })
    },
    ]
}

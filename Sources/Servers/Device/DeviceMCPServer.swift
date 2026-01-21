import Foundation
import Logging
import MCP
import XCMCPCore
import XCMCPTools

/// All available tool names exposed by the xc-device MCP server.
public enum DeviceToolName: String, CaseIterable, Sendable {
    // Device tools
    case listDevices = "list_devices"
    case buildDevice = "build_device"
    case installAppDevice = "install_app_device"
    case launchAppDevice = "launch_app_device"
    case stopAppDevice = "stop_app_device"
    case getDeviceAppPath = "get_device_app_path"
    case testDevice = "test_device"

    // Logging tools
    case startDeviceLogCap = "start_device_log_cap"
    case stopDeviceLogCap = "stop_device_log_cap"

    // Session tools
    case setSessionDefaults = "set_session_defaults"
    case showSessionDefaults = "show_session_defaults"
    case clearSessionDefaults = "clear_session_defaults"
}

/// MCP server for physical iOS device operations.
///
/// This focused server provides tools for managing physical iOS devices,
/// building and running apps, and capturing logs.
///
/// ## Token Efficiency
///
/// This server exposes 12 tools with approximately 2K token overhead, compared to
/// ~50K for the full monolithic xc-mcp server. Use this server when you only need
/// physical device capabilities.
///
/// ## Tool Categories
///
/// - **Device management**: list connected devices
/// - **Build & run**: build, install, launch, stop apps
/// - **Logging**: capture device logs
/// - **Session**: manage default device and project settings
public struct DeviceMCPServer: Sendable {
    private let basePath: String
    private let logger: Logger

    public init(basePath: String, logger: Logger) {
        self.basePath = basePath
        self.logger = logger
    }

    public func run() async throws {
        let server = Server(
            name: "xc-device",
            version: "1.0.0",
            capabilities: .init(tools: .init())
        )

        // Create utilities
        let xcodebuildRunner = XcodebuildRunner()
        let deviceCtlRunner = DeviceCtlRunner()
        let sessionManager = SessionManager()

        // Create device tools
        let listDevicesTool = ListDevicesTool(deviceCtlRunner: deviceCtlRunner)
        let buildDeviceTool = BuildDeviceTool(
            xcodebuildRunner: xcodebuildRunner, sessionManager: sessionManager)
        let installAppDeviceTool = InstallAppDeviceTool(
            deviceCtlRunner: deviceCtlRunner, sessionManager: sessionManager)
        let launchAppDeviceTool = LaunchAppDeviceTool(
            deviceCtlRunner: deviceCtlRunner, sessionManager: sessionManager)
        let stopAppDeviceTool = StopAppDeviceTool(
            deviceCtlRunner: deviceCtlRunner, sessionManager: sessionManager)
        let getDeviceAppPathTool = GetDeviceAppPathTool(
            deviceCtlRunner: deviceCtlRunner, sessionManager: sessionManager)
        let testDeviceTool = TestDeviceTool(
            xcodebuildRunner: xcodebuildRunner, sessionManager: sessionManager)

        // Create logging tools
        let startDeviceLogCapTool = StartDeviceLogCapTool(
            deviceCtlRunner: deviceCtlRunner, sessionManager: sessionManager)
        let stopDeviceLogCapTool = StopDeviceLogCapTool(sessionManager: sessionManager)

        // Create session tools
        let setSessionDefaultsTool = SetSessionDefaultsTool(sessionManager: sessionManager)
        let showSessionDefaultsTool = ShowSessionDefaultsTool(sessionManager: sessionManager)
        let clearSessionDefaultsTool = ClearSessionDefaultsTool(sessionManager: sessionManager)

        // Register tools/list handler
        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: [
                // Device tools
                listDevicesTool.tool(),
                buildDeviceTool.tool(),
                installAppDeviceTool.tool(),
                launchAppDeviceTool.tool(),
                stopAppDeviceTool.tool(),
                getDeviceAppPathTool.tool(),
                testDeviceTool.tool(),
                // Logging tools
                startDeviceLogCapTool.tool(),
                stopDeviceLogCapTool.tool(),
                // Session tools
                setSessionDefaultsTool.tool(),
                showSessionDefaultsTool.tool(),
                clearSessionDefaultsTool.tool(),
            ])
        }

        // Register tools/call handler
        await server.withMethodHandler(CallTool.self) { params in
            guard let toolName = DeviceToolName(rawValue: params.name) else {
                throw MCPError.methodNotFound("Unknown tool: \(params.name)")
            }

            let arguments = params.arguments ?? [:]

            switch toolName {
            // Device tools
            case .listDevices:
                return try await listDevicesTool.execute(arguments: arguments)
            case .buildDevice:
                return try await buildDeviceTool.execute(arguments: arguments)
            case .installAppDevice:
                return try await installAppDeviceTool.execute(arguments: arguments)
            case .launchAppDevice:
                return try await launchAppDeviceTool.execute(arguments: arguments)
            case .stopAppDevice:
                return try await stopAppDeviceTool.execute(arguments: arguments)
            case .getDeviceAppPath:
                return try await getDeviceAppPathTool.execute(arguments: arguments)
            case .testDevice:
                return try await testDeviceTool.execute(arguments: arguments)

            // Logging tools
            case .startDeviceLogCap:
                return try await startDeviceLogCapTool.execute(arguments: arguments)
            case .stopDeviceLogCap:
                return try await stopDeviceLogCapTool.execute(arguments: arguments)

            // Session tools
            case .setSessionDefaults:
                return try await setSessionDefaultsTool.execute(arguments: arguments)
            case .showSessionDefaults:
                return try await showSessionDefaultsTool.execute(arguments: arguments)
            case .clearSessionDefaults:
                return try await clearSessionDefaultsTool.execute(arguments: arguments)
            }
        }

        let transport = StdioTransport(logger: logger)
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    }
}

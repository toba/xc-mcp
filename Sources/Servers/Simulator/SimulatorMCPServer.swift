import Foundation
import Logging
import MCP
import XCMCPCore
import XCMCPTools

/// All available tool names exposed by the xc-simulator MCP server.
public enum SimulatorToolName: String, CaseIterable, Sendable {
    // Simulator tools
    case listSims = "list_sims"
    case bootSim = "boot_sim"
    case openSim = "open_sim"
    case buildSim = "build_sim"
    case buildRunSim = "build_run_sim"
    case installAppSim = "install_app_sim"
    case launchAppSim = "launch_app_sim"
    case stopAppSim = "stop_app_sim"
    case getSimAppPath = "get_sim_app_path"
    case testSim = "test_sim"
    case recordSimVideo = "record_sim_video"
    case launchAppLogsSim = "launch_app_logs_sim"
    case eraseSims = "erase_sims"
    case setSimLocation = "set_sim_location"
    case resetSimLocation = "reset_sim_location"
    case setSimAppearance = "set_sim_appearance"
    case simStatusbar = "sim_statusbar"

    // UI Automation tools
    case tap = "tap"
    case longPress = "long_press"
    case swipe = "swipe"
    case typeText = "type_text"
    case keyPress = "key_press"
    case button = "button"
    case screenshot = "screenshot"

    // Logging tools
    case startSimLogCap = "start_sim_log_cap"
    case stopSimLogCap = "stop_sim_log_cap"

    // Session tools
    case setSessionDefaults = "set_session_defaults"
    case showSessionDefaults = "show_session_defaults"
    case clearSessionDefaults = "clear_session_defaults"
}

/// MCP server for iOS Simulator operations.
///
/// This focused server provides tools for managing iOS simulators, building and
/// running apps, UI automation, and log capture.
///
/// ## Token Efficiency
///
/// This server exposes 29 tools with approximately 6K token overhead, compared to
/// ~50K for the full monolithic xc-mcp server. Use this server when you only need
/// simulator capabilities.
///
/// ## Tool Categories
///
/// - **Simulator management**: list, boot, open, erase simulators
/// - **Build & run**: build, install, launch, stop apps
/// - **UI automation**: tap, swipe, type text, press keys, take screenshots
/// - **Logging**: capture simulator logs
/// - **Session**: manage default simulator and project settings
public struct SimulatorMCPServer: Sendable {
    private let basePath: String
    private let logger: Logger

    public init(basePath: String, logger: Logger) {
        self.basePath = basePath
        self.logger = logger
    }

    public func run() async throws {
        let server = Server(
            name: "xc-simulator",
            version: "1.0.0",
            capabilities: .init(tools: .init())
        )

        // Create utilities
        let xcodebuildRunner = XcodebuildRunner()
        let simctlRunner = SimctlRunner()
        let sessionManager = SessionManager()

        // Create simulator tools
        let listSimsTool = ListSimsTool(simctlRunner: simctlRunner)
        let bootSimTool = BootSimTool(simctlRunner: simctlRunner)
        let openSimTool = OpenSimTool()
        let buildSimTool = BuildSimTool(
            xcodebuildRunner: xcodebuildRunner, sessionManager: sessionManager)
        let buildRunSimTool = BuildRunSimTool(
            xcodebuildRunner: xcodebuildRunner,
            simctlRunner: simctlRunner,
            sessionManager: sessionManager
        )
        let installAppSimTool = InstallAppSimTool(
            simctlRunner: simctlRunner, sessionManager: sessionManager)
        let launchAppSimTool = LaunchAppSimTool(
            simctlRunner: simctlRunner, sessionManager: sessionManager)
        let stopAppSimTool = StopAppSimTool(
            simctlRunner: simctlRunner, sessionManager: sessionManager)
        let getSimAppPathTool = GetSimAppPathTool(
            simctlRunner: simctlRunner, sessionManager: sessionManager)
        let testSimTool = TestSimTool(
            xcodebuildRunner: xcodebuildRunner, sessionManager: sessionManager)
        let recordSimVideoTool = RecordSimVideoTool(
            simctlRunner: simctlRunner, sessionManager: sessionManager)
        let launchAppLogsSimTool = LaunchAppLogsSimTool(
            simctlRunner: simctlRunner, sessionManager: sessionManager)
        let eraseSimTool = EraseSimTool(simctlRunner: simctlRunner, sessionManager: sessionManager)
        let setSimLocationTool = SetSimLocationTool(
            simctlRunner: simctlRunner, sessionManager: sessionManager)
        let resetSimLocationTool = ResetSimLocationTool(
            simctlRunner: simctlRunner, sessionManager: sessionManager)
        let setSimAppearanceTool = SetSimAppearanceTool(
            simctlRunner: simctlRunner, sessionManager: sessionManager)
        let simStatusBarTool = SimStatusBarTool(
            simctlRunner: simctlRunner, sessionManager: sessionManager)

        // Create UI automation tools
        let tapTool = TapTool(simctlRunner: simctlRunner, sessionManager: sessionManager)
        let longPressTool = LongPressTool(
            simctlRunner: simctlRunner, sessionManager: sessionManager)
        let swipeTool = SwipeTool(simctlRunner: simctlRunner, sessionManager: sessionManager)
        let typeTextTool = TypeTextTool(simctlRunner: simctlRunner, sessionManager: sessionManager)
        let keyPressTool = KeyPressTool(simctlRunner: simctlRunner, sessionManager: sessionManager)
        let buttonTool = ButtonTool(simctlRunner: simctlRunner, sessionManager: sessionManager)
        let screenshotTool = ScreenshotTool(
            simctlRunner: simctlRunner, sessionManager: sessionManager)

        // Create logging tools
        let startSimLogCapTool = StartSimLogCapTool(
            simctlRunner: simctlRunner, sessionManager: sessionManager)
        let stopSimLogCapTool = StopSimLogCapTool(sessionManager: sessionManager)

        // Create session tools
        let setSessionDefaultsTool = SetSessionDefaultsTool(sessionManager: sessionManager)
        let showSessionDefaultsTool = ShowSessionDefaultsTool(sessionManager: sessionManager)
        let clearSessionDefaultsTool = ClearSessionDefaultsTool(sessionManager: sessionManager)

        // Register tools/list handler
        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: [
                // Simulator tools
                listSimsTool.tool(),
                bootSimTool.tool(),
                openSimTool.tool(),
                buildSimTool.tool(),
                buildRunSimTool.tool(),
                installAppSimTool.tool(),
                launchAppSimTool.tool(),
                stopAppSimTool.tool(),
                getSimAppPathTool.tool(),
                testSimTool.tool(),
                recordSimVideoTool.tool(),
                launchAppLogsSimTool.tool(),
                eraseSimTool.tool(),
                setSimLocationTool.tool(),
                resetSimLocationTool.tool(),
                setSimAppearanceTool.tool(),
                simStatusBarTool.tool(),
                // UI Automation tools
                tapTool.tool(),
                longPressTool.tool(),
                swipeTool.tool(),
                typeTextTool.tool(),
                keyPressTool.tool(),
                buttonTool.tool(),
                screenshotTool.tool(),
                // Logging tools
                startSimLogCapTool.tool(),
                stopSimLogCapTool.tool(),
                // Session tools
                setSessionDefaultsTool.tool(),
                showSessionDefaultsTool.tool(),
                clearSessionDefaultsTool.tool(),
            ])
        }

        // Register tools/call handler
        await server.withMethodHandler(CallTool.self) { params in
            guard let toolName = SimulatorToolName(rawValue: params.name) else {
                throw MCPError.methodNotFound("Unknown tool: \(params.name)")
            }

            let arguments = params.arguments ?? [:]

            switch toolName {
            // Simulator tools
            case .listSims:
                return try await listSimsTool.execute(arguments: arguments)
            case .bootSim:
                return try await bootSimTool.execute(arguments: arguments)
            case .openSim:
                return try await openSimTool.execute(arguments: arguments)
            case .buildSim:
                return try await buildSimTool.execute(arguments: arguments)
            case .buildRunSim:
                return try await buildRunSimTool.execute(arguments: arguments)
            case .installAppSim:
                return try await installAppSimTool.execute(arguments: arguments)
            case .launchAppSim:
                return try await launchAppSimTool.execute(arguments: arguments)
            case .stopAppSim:
                return try await stopAppSimTool.execute(arguments: arguments)
            case .getSimAppPath:
                return try await getSimAppPathTool.execute(arguments: arguments)
            case .testSim:
                return try await testSimTool.execute(arguments: arguments)
            case .recordSimVideo:
                return try await recordSimVideoTool.execute(arguments: arguments)
            case .launchAppLogsSim:
                return try await launchAppLogsSimTool.execute(arguments: arguments)
            case .eraseSims:
                return try await eraseSimTool.execute(arguments: arguments)
            case .setSimLocation:
                return try await setSimLocationTool.execute(arguments: arguments)
            case .resetSimLocation:
                return try await resetSimLocationTool.execute(arguments: arguments)
            case .setSimAppearance:
                return try await setSimAppearanceTool.execute(arguments: arguments)
            case .simStatusbar:
                return try await simStatusBarTool.execute(arguments: arguments)

            // UI Automation tools
            case .tap:
                return try await tapTool.execute(arguments: arguments)
            case .longPress:
                return try await longPressTool.execute(arguments: arguments)
            case .swipe:
                return try await swipeTool.execute(arguments: arguments)
            case .typeText:
                return try await typeTextTool.execute(arguments: arguments)
            case .keyPress:
                return try await keyPressTool.execute(arguments: arguments)
            case .button:
                return try await buttonTool.execute(arguments: arguments)
            case .screenshot:
                return try await screenshotTool.execute(arguments: arguments)

            // Logging tools
            case .startSimLogCap:
                return try await startSimLogCapTool.execute(arguments: arguments)
            case .stopSimLogCap:
                return try await stopSimLogCapTool.execute(arguments: arguments)

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

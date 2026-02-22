import MCP
import Logging
import XCMCPCore
import Foundation
import XCMCPTools

/// All available tool names exposed by the xc-build MCP server.
public enum BuildToolName: String, CaseIterable, Sendable {
    // macOS tools
    case buildMacOS = "build_macos"
    case buildRunMacOS = "build_run_macos"
    case launchMacApp = "launch_mac_app"
    case stopMacApp = "stop_mac_app"
    case getMacAppPath = "get_mac_app_path"
    case testMacOS = "test_macos"
    case startMacLogCap = "start_mac_log_cap"
    case stopMacLogCap = "stop_mac_log_cap"

    // Discovery tools
    case discoverProjs = "discover_projs"
    case listSchemes = "list_schemes"
    case showBuildSettings = "show_build_settings"
    case getAppBundleId = "get_app_bundle_id"
    case getMacBundleId = "get_mac_bundle_id"
    case listTestPlanTargets = "list_test_plan_targets"

    // Utility tools
    case clean
    case doctor
    case scaffoldIOS = "scaffold_ios_project"
    case scaffoldMacOS = "scaffold_macos_project"

    case searchCrashReports = "search_crash_reports"

    // Session tools
    case setSessionDefaults = "set_session_defaults"
    case showSessionDefaults = "show_session_defaults"
    case clearSessionDefaults = "clear_session_defaults"
}

/// MCP server for build orchestration, discovery, and utility tools.
///
/// This focused server provides tools for macOS builds, project discovery,
/// and general utilities like clean and scaffolding.
///
/// ## Token Efficiency
///
/// This server exposes 18 tools with approximately 3K token overhead, compared to
/// ~50K for the full monolithic xc-mcp server. Use this server when you need
/// macOS build capabilities or project discovery features.
///
/// ## Tool Categories
///
/// - **macOS build**: build, test, run macOS applications
/// - **Discovery**: find projects, list schemes, query build settings
/// - **Utility**: clean, doctor, scaffold new projects
/// - **Session**: manage default project and build settings
public struct BuildMCPServer: Sendable {
    private let basePath: String
    private let sandboxEnabled: Bool
    private let logger: Logger

    /// Creates a new build MCP server instance.
    ///
    /// - Parameters:
    ///   - basePath: The root directory for file operations.
    ///   - sandboxEnabled: Whether to enforce that paths stay within the base directory.
    ///     Defaults to `true`.
    ///   - logger: Logger instance for diagnostic output.
    public init(basePath: String, sandboxEnabled: Bool = true, logger: Logger) {
        self.basePath = basePath
        self.sandboxEnabled = sandboxEnabled
        self.logger = logger
    }

    public func run() async throws {
        let server = Server(
            name: "xc-build",
            version: "1.0.0",
            capabilities: .init(tools: .init()),
        )

        // Create utilities
        let pathUtility = PathUtility(basePath: basePath, sandboxEnabled: sandboxEnabled)
        let xcodebuildRunner = XcodebuildRunner()
        let sessionManager = SessionManager()

        // Create macOS tools
        let buildMacOSTool = BuildMacOSTool(
            xcodebuildRunner: xcodebuildRunner, sessionManager: sessionManager,
        )
        let buildRunMacOSTool = BuildRunMacOSTool(
            xcodebuildRunner: xcodebuildRunner, sessionManager: sessionManager,
        )
        let launchMacAppTool = LaunchMacAppTool(sessionManager: sessionManager)
        let stopMacAppTool = StopMacAppTool(sessionManager: sessionManager)
        let getMacAppPathTool = GetMacAppPathTool(
            xcodebuildRunner: xcodebuildRunner, sessionManager: sessionManager,
        )
        let testMacOSTool = TestMacOSTool(
            xcodebuildRunner: xcodebuildRunner, sessionManager: sessionManager,
        )
        let startMacLogCapTool = StartMacLogCapTool(sessionManager: sessionManager)
        let stopMacLogCapTool = StopMacLogCapTool(sessionManager: sessionManager)

        // Create discovery tools
        let discoverProjsTool = DiscoverProjectsTool(pathUtility: pathUtility)
        let listSchemesTool = ListSchemesTool(
            xcodebuildRunner: xcodebuildRunner, sessionManager: sessionManager,
        )
        let showBuildSettingsTool = ShowBuildSettingsTool(
            xcodebuildRunner: xcodebuildRunner, sessionManager: sessionManager,
        )
        let getAppBundleIdTool = GetAppBundleIdTool(
            xcodebuildRunner: xcodebuildRunner, sessionManager: sessionManager,
        )
        let getMacBundleIdTool = GetMacBundleIdTool(
            xcodebuildRunner: xcodebuildRunner, sessionManager: sessionManager,
        )
        let listTestPlanTargetsTool = ListTestPlanTargetsTool(
            xcodebuildRunner: xcodebuildRunner, sessionManager: sessionManager,
        )

        // Create utility tools
        let cleanTool = CleanTool(
            xcodebuildRunner: xcodebuildRunner, sessionManager: sessionManager,
        )
        let doctorTool = DoctorTool(sessionManager: sessionManager)
        let scaffoldIOSTool = ScaffoldIOSProjectTool(pathUtility: pathUtility)
        let scaffoldMacOSTool = ScaffoldMacOSProjectTool(pathUtility: pathUtility)
        let searchCrashReportsTool = SearchCrashReportsTool()

        // Create session tools
        let setSessionDefaultsTool = SetSessionDefaultsTool(sessionManager: sessionManager)
        let showSessionDefaultsTool = ShowSessionDefaultsTool(sessionManager: sessionManager)
        let clearSessionDefaultsTool = ClearSessionDefaultsTool(sessionManager: sessionManager)

        // Register tools/list handler
        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: [
                // macOS tools
                buildMacOSTool.tool(),
                buildRunMacOSTool.tool(),
                launchMacAppTool.tool(),
                stopMacAppTool.tool(),
                getMacAppPathTool.tool(),
                testMacOSTool.tool(),
                startMacLogCapTool.tool(),
                stopMacLogCapTool.tool(),
                // Discovery tools
                discoverProjsTool.tool(),
                listSchemesTool.tool(),
                showBuildSettingsTool.tool(),
                getAppBundleIdTool.tool(),
                getMacBundleIdTool.tool(),
                listTestPlanTargetsTool.tool(),
                // Utility tools
                cleanTool.tool(),
                doctorTool.tool(),
                scaffoldIOSTool.tool(),
                scaffoldMacOSTool.tool(),
                searchCrashReportsTool.tool(),
                // Session tools
                setSessionDefaultsTool.tool(),
                showSessionDefaultsTool.tool(),
                clearSessionDefaultsTool.tool(),
            ])
        }

        // Register tools/call handler
        await server.withMethodHandler(CallTool.self) { params in
            guard let toolName = BuildToolName(rawValue: params.name) else {
                let hint = ServerToolDirectory.hint(for: params.name, currentServer: "xc-build")
                let message =
                    hint.map { "Unknown tool: \(params.name). \($0)" }
                        ?? "Unknown tool: \(params.name)"
                throw MCPError.methodNotFound(message)
            }

            let arguments = params.arguments ?? [:]

            switch toolName {
                // macOS tools
                case .buildMacOS:
                    return try await buildMacOSTool.execute(arguments: arguments)
                case .buildRunMacOS:
                    return try await buildRunMacOSTool.execute(arguments: arguments)
                case .launchMacApp:
                    return try await launchMacAppTool.execute(arguments: arguments)
                case .stopMacApp:
                    return try await stopMacAppTool.execute(arguments: arguments)
                case .getMacAppPath:
                    return try await getMacAppPathTool.execute(arguments: arguments)
                case .testMacOS:
                    return try await testMacOSTool.execute(arguments: arguments)
                case .startMacLogCap:
                    return try await startMacLogCapTool.execute(arguments: arguments)
                case .stopMacLogCap:
                    return try await stopMacLogCapTool.execute(arguments: arguments)
                // Discovery tools
                case .discoverProjs:
                    return try discoverProjsTool.execute(arguments: arguments)
                case .listSchemes:
                    return try await listSchemesTool.execute(arguments: arguments)
                case .showBuildSettings:
                    return try await showBuildSettingsTool.execute(arguments: arguments)
                case .getAppBundleId:
                    return try await getAppBundleIdTool.execute(arguments: arguments)
                case .getMacBundleId:
                    return try await getMacBundleIdTool.execute(arguments: arguments)
                case .listTestPlanTargets:
                    return try await listTestPlanTargetsTool.execute(arguments: arguments)
                // Utility tools
                case .clean:
                    return try await cleanTool.execute(arguments: arguments)
                case .doctor:
                    return try await doctorTool.execute(arguments: arguments)
                case .scaffoldIOS:
                    return try scaffoldIOSTool.execute(arguments: arguments)
                case .scaffoldMacOS:
                    return try scaffoldMacOSTool.execute(arguments: arguments)
                case .searchCrashReports:
                    return try searchCrashReportsTool.execute(arguments: arguments)
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

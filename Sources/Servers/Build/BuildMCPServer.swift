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
    case getTestAttachments = "get_test_attachments"
    case getCoverageReport = "get_coverage_report"
    case getFileCoverage = "get_file_coverage"
    case startMacLogCap = "start_mac_log_cap"
    case stopMacLogCap = "stop_mac_log_cap"
    case showMacLog = "show_mac_log"
    case showBuildLog = "show_build_log"

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
    case exportIcon = "export_icon"
    case createIcon = "create_icon"
    case readIcon = "read_icon"
    case addIconLayer = "add_icon_layer"
    case removeIconLayer = "remove_icon_layer"
    case setIconFill = "set_icon_fill"
    case setIconEffects = "set_icon_effects"
    case setIconLayerPosition = "set_icon_layer_position"
    case setIconAppearances = "set_icon_appearances"
    case diagnostics

    // Build diagnostics tools
    case checkOutputFileMap = "check_output_file_map"
    case extractCrashTraces = "extract_crash_traces"
    case listBuildPhaseStatus = "list_build_phase_status"
    case readSerializedDiagnostics = "read_serialized_diagnostics"
    case diffBuildSettings = "diff_build_settings"
    case showBuildDependencyGraph = "show_build_dependency_graph"

    // Performance tools
    case getPerformanceMetrics = "get_performance_metrics"
    case setPerformanceBaseline = "set_performance_baseline"
    case showPerformanceBaselines = "show_performance_baselines"

    // Instruments tools
    case sampleMacApp = "sample_mac_app"
    case profileAppLaunch = "profile_app_launch"

    // Distribution tools
    case versionManagement = "version_management"
    case notarize
    case validateAssetCatalog = "validate_asset_catalog"
    case openInXcode = "open_in_xcode"

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
        let getTestAttachmentsTool = GetTestAttachmentsTool()
        let getCoverageReportTool = GetCoverageReportTool()
        let getFileCoverageTool = GetFileCoverageTool()
        let startMacLogCapTool = StartMacLogCapTool(sessionManager: sessionManager)
        let stopMacLogCapTool = StopMacLogCapTool(sessionManager: sessionManager)
        let showMacLogTool = ShowMacLogTool(sessionManager: sessionManager)
        let showBuildLogTool = ShowBuildLogTool(
            xcodebuildRunner: xcodebuildRunner, sessionManager: sessionManager,
        )

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
        let exportIconTool = ExportIconTool()
        let createIconTool = CreateIconTool(pathUtility: pathUtility)
        let readIconTool = ReadIconTool()
        let addIconLayerTool = AddIconLayerTool()
        let removeIconLayerTool = RemoveIconLayerTool()
        let setIconFillTool = SetIconFillTool()
        let setIconEffectsTool = SetIconEffectsTool()
        let setIconLayerPositionTool = SetIconLayerPositionTool()
        let setIconAppearancesTool = SetIconAppearancesTool()
        let diagnosticsTool = DiagnosticsTool(
            xcodebuildRunner: xcodebuildRunner, sessionManager: sessionManager,
        )

        // Create build diagnostics tools
        let checkOutputFileMapTool = CheckOutputFileMapTool(
            xcodebuildRunner: xcodebuildRunner, sessionManager: sessionManager,
        )
        let extractCrashTracesTool = ExtractCrashTracesTool(
            xcodebuildRunner: xcodebuildRunner, sessionManager: sessionManager,
        )
        let listBuildPhaseStatusTool = ListBuildPhaseStatusTool(
            xcodebuildRunner: xcodebuildRunner, sessionManager: sessionManager,
        )
        let readSerializedDiagnosticsTool = ReadSerializedDiagnosticsTool(
            xcodebuildRunner: xcodebuildRunner, sessionManager: sessionManager,
        )
        let diffBuildSettingsTool = DiffBuildSettingsTool(
            xcodebuildRunner: xcodebuildRunner, sessionManager: sessionManager,
        )
        let showBuildDependencyGraphTool = ShowBuildDependencyGraphTool(
            xcodebuildRunner: xcodebuildRunner, sessionManager: sessionManager,
        )

        // Create performance tools
        let getPerformanceMetricsTool = GetPerformanceMetricsTool()
        let setPerformanceBaselineTool = SetPerformanceBaselineTool(
            sessionManager: sessionManager,
        )
        let showPerformanceBaselinesTool = ShowPerformanceBaselinesTool(
            sessionManager: sessionManager,
        )

        // Create instruments tools
        let sampleMacAppTool = SampleMacAppTool()
        let profileAppLaunchTool = ProfileAppLaunchTool(
            xcodebuildRunner: xcodebuildRunner,
            sessionManager: sessionManager,
        )

        // Create distribution/utility tools
        let versionManagementTool = VersionManagementTool()
        let notarizeTool = NotarizeTool()
        let validateAssetCatalogTool = ValidateAssetCatalogTool()
        let openInXcodeTool = OpenInXcodeTool()

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
                getTestAttachmentsTool.tool(),
                getCoverageReportTool.tool(),
                getFileCoverageTool.tool(),
                startMacLogCapTool.tool(),
                stopMacLogCapTool.tool(),
                showMacLogTool.tool(),
                showBuildLogTool.tool(),
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
                exportIconTool.tool(),
                createIconTool.tool(),
                readIconTool.tool(),
                addIconLayerTool.tool(),
                removeIconLayerTool.tool(),
                setIconFillTool.tool(),
                setIconEffectsTool.tool(),
                setIconLayerPositionTool.tool(),
                setIconAppearancesTool.tool(),
                diagnosticsTool.tool(),
                // Build diagnostics tools
                checkOutputFileMapTool.tool(),
                extractCrashTracesTool.tool(),
                listBuildPhaseStatusTool.tool(),
                readSerializedDiagnosticsTool.tool(),
                diffBuildSettingsTool.tool(),
                showBuildDependencyGraphTool.tool(),
                // Performance tools
                getPerformanceMetricsTool.tool(),
                setPerformanceBaselineTool.tool(),
                showPerformanceBaselinesTool.tool(),
                // Instruments tools
                sampleMacAppTool.tool(),
                profileAppLaunchTool.tool(),
                // Distribution/utility tools
                versionManagementTool.tool(),
                notarizeTool.tool(),
                validateAssetCatalogTool.tool(),
                openInXcodeTool.tool(),
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
                case .getTestAttachments:
                    return try await getTestAttachmentsTool.execute(arguments: arguments)
                case .getCoverageReport:
                    return try await getCoverageReportTool.execute(arguments: arguments)
                case .getFileCoverage:
                    return try await getFileCoverageTool.execute(arguments: arguments)
                case .startMacLogCap:
                    return try await startMacLogCapTool.execute(arguments: arguments)
                case .stopMacLogCap:
                    return await stopMacLogCapTool.execute(arguments: arguments)
                case .showMacLog:
                    return try await showMacLogTool.execute(arguments: arguments)
                case .showBuildLog:
                    return try await showBuildLogTool.execute(arguments: arguments)
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
                    return await doctorTool.execute(arguments: arguments)
                case .scaffoldIOS:
                    return try scaffoldIOSTool.execute(arguments: arguments)
                case .scaffoldMacOS:
                    return try scaffoldMacOSTool.execute(arguments: arguments)
                case .searchCrashReports:
                    return searchCrashReportsTool.execute(arguments: arguments)
                case .exportIcon:
                    return try await exportIconTool.execute(arguments: arguments)
                case .createIcon:
                    return try createIconTool.execute(arguments: arguments)
                case .readIcon:
                    return try readIconTool.execute(arguments: arguments)
                case .addIconLayer:
                    return try addIconLayerTool.execute(arguments: arguments)
                case .removeIconLayer:
                    return try removeIconLayerTool.execute(arguments: arguments)
                case .setIconFill:
                    return try setIconFillTool.execute(arguments: arguments)
                case .setIconEffects:
                    return try setIconEffectsTool.execute(arguments: arguments)
                case .setIconLayerPosition:
                    return try setIconLayerPositionTool.execute(arguments: arguments)
                case .setIconAppearances:
                    return try setIconAppearancesTool.execute(arguments: arguments)
                case .diagnostics:
                    return try await diagnosticsTool.execute(arguments: arguments)
                // Build diagnostics tools
                case .checkOutputFileMap:
                    return try await checkOutputFileMapTool.execute(arguments: arguments)
                case .extractCrashTraces:
                    return try await extractCrashTracesTool.execute(arguments: arguments)
                case .listBuildPhaseStatus:
                    return try await listBuildPhaseStatusTool.execute(arguments: arguments)
                case .readSerializedDiagnostics:
                    return try await readSerializedDiagnosticsTool.execute(arguments: arguments)
                case .diffBuildSettings:
                    return try await diffBuildSettingsTool.execute(arguments: arguments)
                case .showBuildDependencyGraph:
                    return try await showBuildDependencyGraphTool.execute(arguments: arguments)
                // Performance tools
                case .getPerformanceMetrics:
                    return try await getPerformanceMetricsTool.execute(arguments: arguments)
                case .setPerformanceBaseline:
                    return try await setPerformanceBaselineTool.execute(arguments: arguments)
                case .showPerformanceBaselines:
                    return try await showPerformanceBaselinesTool.execute(arguments: arguments)
                // Instruments tools
                case .sampleMacApp:
                    return try await sampleMacAppTool.execute(arguments: arguments)
                case .profileAppLaunch:
                    return try await profileAppLaunchTool.execute(arguments: arguments)
                // Distribution/utility tools
                case .versionManagement:
                    return try await versionManagementTool.execute(arguments: arguments)
                case .notarize:
                    return try await notarizeTool.execute(arguments: arguments)
                case .validateAssetCatalog:
                    return try await validateAssetCatalogTool.execute(arguments: arguments)
                case .openInXcode:
                    return try await openInXcodeTool.execute(arguments: arguments)
                // Session tools
                case .setSessionDefaults:
                    return try await setSessionDefaultsTool.execute(arguments: arguments)
                case .showSessionDefaults:
                    return await showSessionDefaultsTool.execute(arguments: arguments)
                case .clearSessionDefaults:
                    return await clearSessionDefaultsTool.execute(arguments: arguments)
            }
        }

        let transport = StdioTransport(logger: logger)
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    }
}

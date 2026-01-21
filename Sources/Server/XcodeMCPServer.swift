import Foundation
import Logging
import MCP
import XCMCPCore
import XCMCPTools

/// All available tool names exposed by the MCP server.
///
/// Each case maps to a specific MCP tool that can be called by clients.
/// The raw values are the actual tool names used in the MCP protocol.
public enum ToolName: String, CaseIterable, Sendable {
    // Project tools
    case createXcodeproj = "create_xcodeproj"
    case listTargets = "list_targets"
    case listBuildConfigurations = "list_build_configurations"
    case listFiles = "list_files"
    case getBuildSettings = "get_build_settings"
    case addFile = "add_file"
    case removeFile = "remove_file"
    case moveFile = "move_file"
    case createGroup = "create_group"
    case addTarget = "add_target"
    case removeTarget = "remove_target"
    case addDependency = "add_dependency"
    case setBuildSetting = "set_build_setting"
    case addFramework = "add_framework"
    case addBuildPhase = "add_build_phase"
    case duplicateTarget = "duplicate_target"
    case addSwiftPackage = "add_swift_package"
    case listSwiftPackages = "list_swift_packages"
    case removeSwiftPackage = "remove_swift_package"
    case listGroups = "list_groups"
    case addSynchronizedFolder = "add_synchronized_folder"
    case addAppExtension = "add_app_extension"
    case removeAppExtension = "remove_app_extension"

    // Session tools
    case setSessionDefaults = "set_session_defaults"
    case showSessionDefaults = "show_session_defaults"
    case clearSessionDefaults = "clear_session_defaults"

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

    // Device tools
    case listDevices = "list_devices"
    case buildDevice = "build_device"
    case installAppDevice = "install_app_device"
    case launchAppDevice = "launch_app_device"
    case stopAppDevice = "stop_app_device"
    case getDeviceAppPath = "get_device_app_path"
    case testDevice = "test_device"

    // macOS tools
    case buildMacOS = "build_macos"
    case buildRunMacOS = "build_run_macos"
    case launchMacApp = "launch_mac_app"
    case stopMacApp = "stop_mac_app"
    case getMacAppPath = "get_mac_app_path"
    case testMacOS = "test_macos"

    // Discovery tools
    case discoverProjs = "discover_projs"
    case listSchemes = "list_schemes"
    case showBuildSettings = "show_build_settings"
    case getAppBundleId = "get_app_bundle_id"
    case getMacBundleId = "get_mac_bundle_id"

    // Logging tools
    case startSimLogCap = "start_sim_log_cap"
    case stopSimLogCap = "stop_sim_log_cap"
    case startDeviceLogCap = "start_device_log_cap"
    case stopDeviceLogCap = "stop_device_log_cap"

    // Extended simulator tools
    case eraseSims = "erase_sims"
    case setSimLocation = "set_sim_location"
    case resetSimLocation = "reset_sim_location"
    case setSimAppearance = "set_sim_appearance"
    case simStatusbar = "sim_statusbar"

    // Debug tools
    case debugAttachSim = "debug_attach_sim"
    case debugDetach = "debug_detach"
    case debugBreakpointAdd = "debug_breakpoint_add"
    case debugBreakpointRemove = "debug_breakpoint_remove"
    case debugContinue = "debug_continue"
    case debugStack = "debug_stack"
    case debugVariables = "debug_variables"
    case debugLLDBCommand = "debug_lldb_command"

    // UI Automation tools
    case tap = "tap"
    case longPress = "long_press"
    case swipe = "swipe"
    case typeText = "type_text"
    case keyPress = "key_press"
    case button = "button"
    case screenshot = "screenshot"

    // Swift Package Manager tools
    case swiftPackageBuild = "swift_package_build"
    case swiftPackageTest = "swift_package_test"
    case swiftPackageRun = "swift_package_run"
    case swiftPackageClean = "swift_package_clean"
    case swiftPackageList = "swift_package_list"
    case swiftPackageStop = "swift_package_stop"

    // Utility tools
    case clean = "clean"
    case doctor = "doctor"
    case scaffoldIOS = "scaffold_ios_project"
    case scaffoldMacOS = "scaffold_macos_project"
}

/// The main MCP server for Xcode development operations.
///
/// `XcodeMCPServer` exposes a comprehensive set of tools for Xcode project manipulation,
/// building, testing, and device management through the Model Context Protocol (MCP).
///
/// ## Overview
///
/// The server provides tools organized into categories:
/// - **Project tools**: Create and modify Xcode projects (.xcodeproj files)
/// - **Simulator tools**: Build, install, and run apps on iOS simulators
/// - **Device tools**: Build, install, and run apps on physical devices
/// - **macOS tools**: Build and run macOS applications
/// - **Debug tools**: LLDB debugging operations
/// - **UI Automation tools**: Interact with simulator UI elements
/// - **Swift Package tools**: Build and test Swift packages
///
/// ## Usage
///
/// ```swift
/// let server = XcodeMCPServer(basePath: "/path/to/projects", logger: logger)
/// try await server.run()
/// ```
public struct XcodeMCPServer: Sendable {
    /// The base path for all file operations.
    private let basePath: String

    /// Logger instance for server diagnostics.
    private let logger: Logger

    /// Manages session state including default project, scheme, and device settings.
    private let sessionManager: SessionManager

    /// Creates a new Xcode MCP server instance.
    ///
    /// - Parameters:
    ///   - basePath: The root directory for file operations. All paths are validated
    ///     to be within this directory for security.
    ///   - logger: Logger instance for diagnostic output.
    public init(basePath: String, logger: Logger) {
        self.basePath = basePath
        self.logger = logger
        self.sessionManager = SessionManager()
    }

    /// Starts the MCP server and begins processing requests.
    ///
    /// This method initializes all tool handlers and starts the server using
    /// stdio transport. It blocks until the server completes or encounters an error.
    ///
    /// - Throws: An error if the server fails to start or encounters a fatal error.
    public func run() async throws {
        let server = Server(
            name: "xcode-mcp-server",
            version: "1.0.0",
            capabilities: .init(tools: .init())
        )

        // Create utilities
        let pathUtility = PathUtility(basePath: basePath)
        let xcodebuildRunner = XcodebuildRunner()
        let simctlRunner = SimctlRunner()
        let deviceCtlRunner = DeviceCtlRunner()

        // Create project tools
        let createXcodeprojTool = CreateXcodeprojTool(pathUtility: pathUtility)
        let listTargetsTool = ListTargetsTool(pathUtility: pathUtility)
        let listBuildConfigurationsTool = ListBuildConfigurationsTool(pathUtility: pathUtility)
        let listFilesTool = ListFilesTool(pathUtility: pathUtility)
        let getBuildSettingsTool = GetBuildSettingsTool(pathUtility: pathUtility)
        let addFileTool = AddFileTool(pathUtility: pathUtility)
        let removeFileTool = RemoveFileTool(pathUtility: pathUtility)
        let moveFileTool = MoveFileTool(pathUtility: pathUtility)
        let createGroupTool = CreateGroupTool(pathUtility: pathUtility)
        let addTargetTool = AddTargetTool(pathUtility: pathUtility)
        let removeTargetTool = RemoveTargetTool(pathUtility: pathUtility)
        let addDependencyTool = AddDependencyTool(pathUtility: pathUtility)
        let setBuildSettingTool = SetBuildSettingTool(pathUtility: pathUtility)
        let addFrameworkTool = AddFrameworkTool(pathUtility: pathUtility)
        let addBuildPhaseTool = AddBuildPhaseTool(pathUtility: pathUtility)
        let duplicateTargetTool = DuplicateTargetTool(pathUtility: pathUtility)
        let addSwiftPackageTool = AddSwiftPackageTool(pathUtility: pathUtility)
        let listSwiftPackagesTool = ListSwiftPackagesTool(pathUtility: pathUtility)
        let removeSwiftPackageTool = RemoveSwiftPackageTool(pathUtility: pathUtility)
        let listGroupsTool = ListGroupsTool(pathUtility: pathUtility)
        let addSynchronizedFolderTool = AddFolderTool(pathUtility: pathUtility)
        let addAppExtensionTool = AddAppExtensionTool(pathUtility: pathUtility)
        let removeAppExtensionTool = RemoveAppExtensionTool(pathUtility: pathUtility)

        // Create session tools
        let setSessionDefaultsTool = SetSessionDefaultsTool(sessionManager: sessionManager)
        let showSessionDefaultsTool = ShowSessionDefaultsTool(sessionManager: sessionManager)
        let clearSessionDefaultsTool = ClearSessionDefaultsTool(sessionManager: sessionManager)

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

        // Create macOS tools
        let buildMacOSTool = BuildMacOSTool(
            xcodebuildRunner: xcodebuildRunner, sessionManager: sessionManager)
        let buildRunMacOSTool = BuildRunMacOSTool(
            xcodebuildRunner: xcodebuildRunner, sessionManager: sessionManager)
        let launchMacAppTool = LaunchMacAppTool(sessionManager: sessionManager)
        let stopMacAppTool = StopMacAppTool(sessionManager: sessionManager)
        let getMacAppPathTool = GetMacAppPathTool(
            xcodebuildRunner: xcodebuildRunner, sessionManager: sessionManager)
        let testMacOSTool = TestMacOSTool(
            xcodebuildRunner: xcodebuildRunner, sessionManager: sessionManager)

        // Create discovery tools
        let discoverProjsTool = DiscoverProjectsTool(pathUtility: pathUtility)
        let listSchemesTool = ListSchemesTool(
            xcodebuildRunner: xcodebuildRunner, sessionManager: sessionManager)
        let showBuildSettingsTool = ShowBuildSettingsTool(
            xcodebuildRunner: xcodebuildRunner, sessionManager: sessionManager)
        let getAppBundleIdTool = GetAppBundleIdTool(
            xcodebuildRunner: xcodebuildRunner, sessionManager: sessionManager)
        let getMacBundleIdTool = GetMacBundleIdTool(
            xcodebuildRunner: xcodebuildRunner, sessionManager: sessionManager)

        // Create logging tools
        let startSimLogCapTool = StartSimLogCapTool(
            simctlRunner: simctlRunner, sessionManager: sessionManager)
        let stopSimLogCapTool = StopSimLogCapTool(sessionManager: sessionManager)
        let startDeviceLogCapTool = StartDeviceLogCapTool(
            deviceCtlRunner: deviceCtlRunner, sessionManager: sessionManager)
        let stopDeviceLogCapTool = StopDeviceLogCapTool(sessionManager: sessionManager)

        // Create extended simulator tools
        let eraseSimTool = EraseSimTool(simctlRunner: simctlRunner, sessionManager: sessionManager)
        let setSimLocationTool = SetSimLocationTool(
            simctlRunner: simctlRunner, sessionManager: sessionManager)
        let resetSimLocationTool = ResetSimLocationTool(
            simctlRunner: simctlRunner, sessionManager: sessionManager)
        let setSimAppearanceTool = SetSimAppearanceTool(
            simctlRunner: simctlRunner, sessionManager: sessionManager)
        let simStatusBarTool = SimStatusBarTool(
            simctlRunner: simctlRunner, sessionManager: sessionManager)

        // Create debug tools
        let lldbRunner = LLDBRunner()
        let debugAttachSimTool = DebugAttachSimTool(
            lldbRunner: lldbRunner, simctlRunner: simctlRunner, sessionManager: sessionManager)
        let debugDetachTool = DebugDetachTool(lldbRunner: lldbRunner)
        let debugBreakpointAddTool = DebugBreakpointAddTool(lldbRunner: lldbRunner)
        let debugBreakpointRemoveTool = DebugBreakpointRemoveTool(lldbRunner: lldbRunner)
        let debugContinueTool = DebugContinueTool(lldbRunner: lldbRunner)
        let debugStackTool = DebugStackTool(lldbRunner: lldbRunner)
        let debugVariablesTool = DebugVariablesTool(lldbRunner: lldbRunner)
        let debugLLDBCommandTool = DebugLLDBCommandTool(lldbRunner: lldbRunner)

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

        // Create Swift Package Manager tools
        let swiftRunner = SwiftRunner()
        let swiftPackageBuildTool = SwiftPackageBuildTool(
            swiftRunner: swiftRunner, sessionManager: sessionManager)
        let swiftPackageTestTool = SwiftPackageTestTool(
            swiftRunner: swiftRunner, sessionManager: sessionManager)
        let swiftPackageRunTool = SwiftPackageRunTool(
            swiftRunner: swiftRunner, sessionManager: sessionManager)
        let swiftPackageCleanTool = SwiftPackageCleanTool(
            swiftRunner: swiftRunner, sessionManager: sessionManager)
        let swiftPackageListTool = SwiftPackageListTool(
            swiftRunner: swiftRunner, sessionManager: sessionManager)
        let swiftPackageStopTool = SwiftPackageStopTool(sessionManager: sessionManager)

        // Create utility tools
        let cleanTool = CleanTool(
            xcodebuildRunner: xcodebuildRunner, sessionManager: sessionManager)
        let doctorTool = DoctorTool()
        let scaffoldIOSTool = ScaffoldIOSProjectTool(pathUtility: pathUtility)
        let scaffoldMacOSTool = ScaffoldMacOSProjectTool(pathUtility: pathUtility)

        // Register tools/list handler
        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: [
                // Project tools
                createXcodeprojTool.tool(),
                listTargetsTool.tool(),
                listBuildConfigurationsTool.tool(),
                listFilesTool.tool(),
                getBuildSettingsTool.tool(),
                addFileTool.tool(),
                removeFileTool.tool(),
                moveFileTool.tool(),
                createGroupTool.tool(),
                addTargetTool.tool(),
                removeTargetTool.tool(),
                addDependencyTool.tool(),
                setBuildSettingTool.tool(),
                addFrameworkTool.tool(),
                addBuildPhaseTool.tool(),
                duplicateTargetTool.tool(),
                addSwiftPackageTool.tool(),
                listSwiftPackagesTool.tool(),
                removeSwiftPackageTool.tool(),
                listGroupsTool.tool(),
                addSynchronizedFolderTool.tool(),
                addAppExtensionTool.tool(),
                removeAppExtensionTool.tool(),
                // Session tools
                setSessionDefaultsTool.tool(),
                showSessionDefaultsTool.tool(),
                clearSessionDefaultsTool.tool(),
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
                // Device tools
                listDevicesTool.tool(),
                buildDeviceTool.tool(),
                installAppDeviceTool.tool(),
                launchAppDeviceTool.tool(),
                stopAppDeviceTool.tool(),
                getDeviceAppPathTool.tool(),
                testDeviceTool.tool(),
                // macOS tools
                buildMacOSTool.tool(),
                buildRunMacOSTool.tool(),
                launchMacAppTool.tool(),
                stopMacAppTool.tool(),
                getMacAppPathTool.tool(),
                testMacOSTool.tool(),
                // Discovery tools
                discoverProjsTool.tool(),
                listSchemesTool.tool(),
                showBuildSettingsTool.tool(),
                getAppBundleIdTool.tool(),
                getMacBundleIdTool.tool(),
                // Logging tools
                startSimLogCapTool.tool(),
                stopSimLogCapTool.tool(),
                startDeviceLogCapTool.tool(),
                stopDeviceLogCapTool.tool(),
                // Extended simulator tools
                eraseSimTool.tool(),
                setSimLocationTool.tool(),
                resetSimLocationTool.tool(),
                setSimAppearanceTool.tool(),
                simStatusBarTool.tool(),
                // Debug tools
                debugAttachSimTool.tool(),
                debugDetachTool.tool(),
                debugBreakpointAddTool.tool(),
                debugBreakpointRemoveTool.tool(),
                debugContinueTool.tool(),
                debugStackTool.tool(),
                debugVariablesTool.tool(),
                debugLLDBCommandTool.tool(),
                // UI Automation tools
                tapTool.tool(),
                longPressTool.tool(),
                swipeTool.tool(),
                typeTextTool.tool(),
                keyPressTool.tool(),
                buttonTool.tool(),
                screenshotTool.tool(),
                // Swift Package Manager tools
                swiftPackageBuildTool.tool(),
                swiftPackageTestTool.tool(),
                swiftPackageRunTool.tool(),
                swiftPackageCleanTool.tool(),
                swiftPackageListTool.tool(),
                swiftPackageStopTool.tool(),
                // Utility tools
                cleanTool.tool(),
                doctorTool.tool(),
                scaffoldIOSTool.tool(),
                scaffoldMacOSTool.tool(),
            ])
        }

        // Register tools/call handler
        await server.withMethodHandler(CallTool.self) { params in
            guard let toolName = ToolName(rawValue: params.name) else {
                throw MCPError.methodNotFound("Unknown tool: \(params.name)")
            }

            let arguments = params.arguments ?? [:]

            switch toolName {
            // Project tools
            case .createXcodeproj:
                return try createXcodeprojTool.execute(arguments: arguments)
            case .listTargets:
                return try listTargetsTool.execute(arguments: arguments)
            case .listBuildConfigurations:
                return try listBuildConfigurationsTool.execute(arguments: arguments)
            case .listFiles:
                return try listFilesTool.execute(arguments: arguments)
            case .getBuildSettings:
                return try getBuildSettingsTool.execute(arguments: arguments)
            case .addFile:
                return try addFileTool.execute(arguments: arguments)
            case .removeFile:
                return try removeFileTool.execute(arguments: arguments)
            case .moveFile:
                return try moveFileTool.execute(arguments: arguments)
            case .createGroup:
                return try createGroupTool.execute(arguments: arguments)
            case .addTarget:
                return try addTargetTool.execute(arguments: arguments)
            case .removeTarget:
                return try removeTargetTool.execute(arguments: arguments)
            case .addDependency:
                return try addDependencyTool.execute(arguments: arguments)
            case .setBuildSetting:
                return try setBuildSettingTool.execute(arguments: arguments)
            case .addFramework:
                return try addFrameworkTool.execute(arguments: arguments)
            case .addBuildPhase:
                return try addBuildPhaseTool.execute(arguments: arguments)
            case .duplicateTarget:
                return try duplicateTargetTool.execute(arguments: arguments)
            case .addSwiftPackage:
                return try addSwiftPackageTool.execute(arguments: arguments)
            case .listSwiftPackages:
                return try listSwiftPackagesTool.execute(arguments: arguments)
            case .removeSwiftPackage:
                return try removeSwiftPackageTool.execute(arguments: arguments)
            case .listGroups:
                return try listGroupsTool.execute(arguments: arguments)
            case .addSynchronizedFolder:
                return try addSynchronizedFolderTool.execute(arguments: arguments)
            case .addAppExtension:
                return try addAppExtensionTool.execute(arguments: arguments)
            case .removeAppExtension:
                return try removeAppExtensionTool.execute(arguments: arguments)

            // Session tools
            case .setSessionDefaults:
                return try await setSessionDefaultsTool.execute(arguments: arguments)
            case .showSessionDefaults:
                return try await showSessionDefaultsTool.execute(arguments: arguments)
            case .clearSessionDefaults:
                return try await clearSessionDefaultsTool.execute(arguments: arguments)

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

            // Logging tools
            case .startSimLogCap:
                return try await startSimLogCapTool.execute(arguments: arguments)
            case .stopSimLogCap:
                return try await stopSimLogCapTool.execute(arguments: arguments)
            case .startDeviceLogCap:
                return try await startDeviceLogCapTool.execute(arguments: arguments)
            case .stopDeviceLogCap:
                return try await stopDeviceLogCapTool.execute(arguments: arguments)

            // Extended simulator tools
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

            // Debug tools
            case .debugAttachSim:
                return try await debugAttachSimTool.execute(arguments: arguments)
            case .debugDetach:
                return try await debugDetachTool.execute(arguments: arguments)
            case .debugBreakpointAdd:
                return try await debugBreakpointAddTool.execute(arguments: arguments)
            case .debugBreakpointRemove:
                return try await debugBreakpointRemoveTool.execute(arguments: arguments)
            case .debugContinue:
                return try await debugContinueTool.execute(arguments: arguments)
            case .debugStack:
                return try await debugStackTool.execute(arguments: arguments)
            case .debugVariables:
                return try await debugVariablesTool.execute(arguments: arguments)
            case .debugLLDBCommand:
                return try await debugLLDBCommandTool.execute(arguments: arguments)

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

            // Swift Package Manager tools
            case .swiftPackageBuild:
                return try await swiftPackageBuildTool.execute(arguments: arguments)
            case .swiftPackageTest:
                return try await swiftPackageTestTool.execute(arguments: arguments)
            case .swiftPackageRun:
                return try await swiftPackageRunTool.execute(arguments: arguments)
            case .swiftPackageClean:
                return try await swiftPackageCleanTool.execute(arguments: arguments)
            case .swiftPackageList:
                return try await swiftPackageListTool.execute(arguments: arguments)
            case .swiftPackageStop:
                return try await swiftPackageStopTool.execute(arguments: arguments)

            // Utility tools
            case .clean:
                return try await cleanTool.execute(arguments: arguments)
            case .doctor:
                return try await doctorTool.execute(arguments: arguments)
            case .scaffoldIOS:
                return try scaffoldIOSTool.execute(arguments: arguments)
            case .scaffoldMacOS:
                return try scaffoldMacOSTool.execute(arguments: arguments)
            }
        }

        // Use stdio transport
        let transport = StdioTransport(logger: logger)
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    }
}

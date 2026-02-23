import MCP
import Logging
import XCMCPCore
import Foundation
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
    case renameTarget = "rename_target"
    case renameScheme = "rename_scheme"
    case createScheme = "create_scheme"
    case validateScheme = "validate_scheme"
    case createTestPlan = "create_test_plan"
    case addTargetToTestPlan = "add_target_to_test_plan"
    case removeTargetFromTestPlan = "remove_target_from_test_plan"
    case setTestPlanTargetEnabled = "set_test_plan_target_enabled"
    case addTestPlanToScheme = "add_test_plan_to_scheme"
    case removeTestPlanFromScheme = "remove_test_plan_from_scheme"
    case listTestPlans = "list_test_plans"
    case setTestTargetApplication = "set_test_target_application"
    case renameGroup = "rename_group"
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
    case addTargetToSynchronizedFolder = "add_target_to_synchronized_folder"
    case addSynchronizedFolderException = "add_synchronized_folder_exception"
    case addAppExtension = "add_app_extension"
    case removeAppExtension = "remove_app_extension"
    case listCopyFilesPhases = "list_copy_files_phases"
    case addCopyFilesPhase = "add_copy_files_phase"
    case addToCopyFilesPhase = "add_to_copy_files_phase"
    case removeCopyFilesPhase = "remove_copy_files_phase"
    case listDocumentTypes = "list_document_types"
    case manageDocumentType = "manage_document_type"
    case listTypeIdentifiers = "list_type_identifiers"
    case manageTypeIdentifier = "manage_type_identifier"
    case listURLTypes = "list_url_types"
    case manageURLType = "manage_url_type"

    // Session tools
    case setSessionDefaults = "set_session_defaults"
    case showSessionDefaults = "show_session_defaults"
    case clearSessionDefaults = "clear_session_defaults"
    case syncXcodeDefaults = "sync_xcode_defaults"
    case manageWorkflows = "manage_workflows"

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
    case previewCapture = "preview_capture"

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
    case startMacLogCap = "start_mac_log_cap"
    case stopMacLogCap = "stop_mac_log_cap"
    case screenshotMacWindow = "screenshot_mac_window"

    // Discovery tools
    case discoverProjs = "discover_projs"
    case listSchemes = "list_schemes"
    case showBuildSettings = "show_build_settings"
    case getAppBundleId = "get_app_bundle_id"
    case getMacBundleId = "get_mac_bundle_id"
    case listTestPlanTargets = "list_test_plan_targets"

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
    case buildDebugMacOS = "build_debug_macos"
    case debugAttachSim = "debug_attach_sim"
    case debugDetach = "debug_detach"
    case debugBreakpointAdd = "debug_breakpoint_add"
    case debugBreakpointRemove = "debug_breakpoint_remove"
    case debugContinue = "debug_continue"
    case debugStack = "debug_stack"
    case debugVariables = "debug_variables"
    case debugLLDBCommand = "debug_lldb_command"
    case debugEvaluate = "debug_evaluate"
    case debugThreads = "debug_threads"
    case debugWatchpoint = "debug_watchpoint"
    case debugStep = "debug_step"
    case debugMemory = "debug_memory"
    case debugSymbolLookup = "debug_symbol_lookup"
    case debugViewHierarchy = "debug_view_hierarchy"
    case debugViewBorders = "debug_view_borders"
    case debugProcessStatus = "debug_process_status"

    // UI Automation tools
    case tap
    case longPress = "long_press"
    case swipe
    case gesture
    case typeText = "type_text"
    case keyPress = "key_press"
    case button
    case screenshot

    // Interact tools (macOS Accessibility API)
    case interactUITree = "interact_ui_tree"
    case interactClick = "interact_click"
    case interactSetValue = "interact_set_value"
    case interactGetValue = "interact_get_value"
    case interactMenu = "interact_menu"
    case interactFocus = "interact_focus"
    case interactKey = "interact_key"
    case interactFind = "interact_find"

    // Swift Package Manager tools
    case swiftPackageBuild = "swift_package_build"
    case swiftPackageTest = "swift_package_test"
    case swiftPackageRun = "swift_package_run"
    case swiftPackageClean = "swift_package_clean"
    case swiftPackageList = "swift_package_list"
    case swiftPackageStop = "swift_package_stop"
    case swiftFormat = "swift_format"
    case swiftLint = "swift_lint"
    case swiftDiagnostics = "swift_diagnostics"

    // Instruments tools
    case xctraceRecord = "xctrace_record"
    case xctraceList = "xctrace_list"
    case xctraceExport = "xctrace_export"

    // Utility tools
    case clean
    case doctor
    case scaffoldIOS = "scaffold_ios_project"
    case scaffoldMacOS = "scaffold_macos_project"
    case searchCrashReports = "search_crash_reports"
    case diagnostics
    /// The workflow category this tool belongs to.
    public var workflow: Workflow {
        switch self {
            // Project
            case .createXcodeproj, .listTargets, .listBuildConfigurations, .listFiles,
                 .getBuildSettings, .addFile, .removeFile, .moveFile, .createGroup,
                 .addTarget, .removeTarget, .renameTarget, .renameScheme, .createScheme,
                 .validateScheme, .createTestPlan, .addTargetToTestPlan,
                 .removeTargetFromTestPlan, .setTestPlanTargetEnabled,
                 .addTestPlanToScheme, .removeTestPlanFromScheme,
                 .listTestPlans, .setTestTargetApplication,
                 .renameGroup,
                 .addDependency, .setBuildSetting,
                 .addFramework,
                 .addBuildPhase, .duplicateTarget, .addSwiftPackage, .listSwiftPackages,
                 .removeSwiftPackage, .listGroups, .addSynchronizedFolder,
                 .addTargetToSynchronizedFolder, .addSynchronizedFolderException,
                 .addAppExtension, .removeAppExtension, .listCopyFilesPhases,
                 .addCopyFilesPhase, .addToCopyFilesPhase, .removeCopyFilesPhase,
                 .listDocumentTypes, .manageDocumentType, .listTypeIdentifiers,
                 .manageTypeIdentifier, .listURLTypes, .manageURLType:
                return .project
            // Session
            case .setSessionDefaults, .showSessionDefaults, .clearSessionDefaults,
                 .syncXcodeDefaults, .manageWorkflows:
                return .session
            // Simulator
            case .listSims, .bootSim, .openSim, .buildSim, .buildRunSim, .installAppSim,
                 .launchAppSim, .stopAppSim, .getSimAppPath, .testSim, .recordSimVideo,
                 .launchAppLogsSim, .previewCapture, .eraseSims, .setSimLocation,
                 .resetSimLocation, .setSimAppearance, .simStatusbar:
                return .simulator
            // Device
            case .listDevices, .buildDevice, .installAppDevice, .launchAppDevice,
                 .stopAppDevice, .getDeviceAppPath, .testDevice:
                return .device
            // macOS
            case .buildMacOS, .buildRunMacOS, .launchMacApp, .stopMacApp, .getMacAppPath,
                 .testMacOS, .startMacLogCap, .stopMacLogCap, .screenshotMacWindow:
                return .macos
            // Discovery
            case .discoverProjs, .listSchemes, .showBuildSettings, .getAppBundleId,
                 .getMacBundleId, .listTestPlanTargets:
                return .discovery
            // Logging
            case .startSimLogCap, .stopSimLogCap, .startDeviceLogCap, .stopDeviceLogCap:
                return .logging
            // Debug
            case .buildDebugMacOS, .debugAttachSim, .debugDetach, .debugBreakpointAdd,
                 .debugBreakpointRemove, .debugContinue, .debugStack, .debugVariables,
                 .debugLLDBCommand, .debugEvaluate, .debugThreads, .debugWatchpoint,
                 .debugStep, .debugMemory, .debugSymbolLookup, .debugViewHierarchy,
                 .debugViewBorders, .debugProcessStatus:
                return .debug
            // UI Automation
            case .tap, .longPress, .swipe, .gesture, .typeText, .keyPress, .button,
                 .screenshot:
                return .uiAutomation
            // Interact
            case .interactUITree, .interactClick, .interactSetValue, .interactGetValue,
                 .interactMenu, .interactFocus, .interactKey, .interactFind:
                return .interact
            // Swift Package
            case .swiftPackageBuild, .swiftPackageTest, .swiftPackageRun, .swiftPackageClean,
                 .swiftPackageList, .swiftPackageStop, .swiftFormat, .swiftLint,
                 .swiftDiagnostics:
                return .swiftPackage
            // Instruments
            case .xctraceRecord, .xctraceList, .xctraceExport:
                return .instruments
            // Utility
            case .clean, .doctor, .scaffoldIOS, .scaffoldMacOS, .searchCrashReports, .diagnostics:
                return .utility
        }
    }
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
        sessionManager = SessionManager()
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
            capabilities: .init(tools: .init(listChanged: true)),
        )

        // Workflow manager
        let workflowManager = WorkflowManager()

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
        let renameTargetTool = RenameTargetTool(pathUtility: pathUtility)
        let renameSchemeTool = RenameSchemeTool(pathUtility: pathUtility)
        let createSchemeTool = CreateSchemeTool(pathUtility: pathUtility)
        let validateSchemeTool = ValidateSchemeTool(pathUtility: pathUtility)
        let createTestPlanTool = CreateTestPlanTool(pathUtility: pathUtility)
        let addTargetToTestPlanTool = AddTargetToTestPlanTool(pathUtility: pathUtility)
        let removeTargetFromTestPlanTool = RemoveTargetFromTestPlanTool(pathUtility: pathUtility)
        let setTestPlanTargetEnabledTool = SetTestPlanTargetEnabledTool(pathUtility: pathUtility)
        let addTestPlanToSchemeTool = AddTestPlanToSchemeTool(pathUtility: pathUtility)
        let removeTestPlanFromSchemeTool = RemoveTestPlanFromSchemeTool(pathUtility: pathUtility)
        let listTestPlansTool = ListTestPlansTool(pathUtility: pathUtility)
        let setTestTargetApplicationTool = SetTestTargetApplicationTool(pathUtility: pathUtility)
        let renameGroupTool = RenameGroupTool(pathUtility: pathUtility)
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
        let addTargetToSynchronizedFolderTool = AddTargetToSynchronizedFolderTool(
            pathUtility: pathUtility,
        )
        let addSynchronizedFolderExceptionTool = AddSynchronizedFolderExceptionTool(
            pathUtility: pathUtility,
        )
        let addAppExtensionTool = AddAppExtensionTool(pathUtility: pathUtility)
        let removeAppExtensionTool = RemoveAppExtensionTool(pathUtility: pathUtility)
        let listCopyFilesPhases = ListCopyFilesPhases(pathUtility: pathUtility)
        let addCopyFilesPhase = AddCopyFilesPhase(pathUtility: pathUtility)
        let addToCopyFilesPhase = AddToCopyFilesPhase(pathUtility: pathUtility)
        let removeCopyFilesPhase = RemoveCopyFilesPhase(pathUtility: pathUtility)
        let listDocumentTypesTool = ListDocumentTypesTool(pathUtility: pathUtility)
        let manageDocumentTypeTool = ManageDocumentTypeTool(pathUtility: pathUtility)
        let listTypeIdentifiersTool = ListTypeIdentifiersTool(pathUtility: pathUtility)
        let manageTypeIdentifierTool = ManageTypeIdentifierTool(pathUtility: pathUtility)
        let listURLTypesTool = ListURLTypesTool(pathUtility: pathUtility)
        let manageURLTypeTool = ManageURLTypeTool(pathUtility: pathUtility)

        // Create session tools
        let setSessionDefaultsTool = SetSessionDefaultsTool(sessionManager: sessionManager)
        let showSessionDefaultsTool = ShowSessionDefaultsTool(sessionManager: sessionManager)
        let clearSessionDefaultsTool = ClearSessionDefaultsTool(sessionManager: sessionManager)
        let syncXcodeDefaultsTool = SyncXcodeDefaultsTool(sessionManager: sessionManager)
        let manageWorkflowsTool = ManageWorkflowsTool(workflowManager: workflowManager)

        // Create simulator tools
        let listSimsTool = ListSimsTool(simctlRunner: simctlRunner)
        let bootSimTool = BootSimTool(simctlRunner: simctlRunner)
        let openSimTool = OpenSimTool()
        let buildSimTool = BuildSimTool(
            xcodebuildRunner: xcodebuildRunner, sessionManager: sessionManager,
        )
        let buildRunSimTool = BuildRunSimTool(
            xcodebuildRunner: xcodebuildRunner,
            simctlRunner: simctlRunner,
            sessionManager: sessionManager,
        )
        let installAppSimTool = InstallAppSimTool(
            simctlRunner: simctlRunner, sessionManager: sessionManager,
        )
        let launchAppSimTool = LaunchAppSimTool(
            simctlRunner: simctlRunner, sessionManager: sessionManager,
        )
        let stopAppSimTool = StopAppSimTool(
            simctlRunner: simctlRunner, sessionManager: sessionManager,
        )
        let getSimAppPathTool = GetSimAppPathTool(
            simctlRunner: simctlRunner, sessionManager: sessionManager,
        )
        let testSimTool = TestSimTool(
            xcodebuildRunner: xcodebuildRunner, sessionManager: sessionManager,
        )
        let recordSimVideoTool = RecordSimVideoTool(
            simctlRunner: simctlRunner, sessionManager: sessionManager,
        )
        let launchAppLogsSimTool = LaunchAppLogsSimTool(
            simctlRunner: simctlRunner, sessionManager: sessionManager,
        )
        let previewCaptureTool = PreviewCaptureTool(
            xcodebuildRunner: xcodebuildRunner,
            simctlRunner: simctlRunner,
            pathUtility: pathUtility,
            sessionManager: sessionManager,
        )

        // Create device tools
        let listDevicesTool = ListDevicesTool(deviceCtlRunner: deviceCtlRunner)
        let buildDeviceTool = BuildDeviceTool(
            xcodebuildRunner: xcodebuildRunner, sessionManager: sessionManager,
        )
        let installAppDeviceTool = InstallAppDeviceTool(
            deviceCtlRunner: deviceCtlRunner, sessionManager: sessionManager,
        )
        let launchAppDeviceTool = LaunchAppDeviceTool(
            deviceCtlRunner: deviceCtlRunner, sessionManager: sessionManager,
        )
        let stopAppDeviceTool = StopAppDeviceTool(
            deviceCtlRunner: deviceCtlRunner, sessionManager: sessionManager,
        )
        let getDeviceAppPathTool = GetDeviceAppPathTool(
            deviceCtlRunner: deviceCtlRunner, sessionManager: sessionManager,
        )
        let testDeviceTool = TestDeviceTool(
            xcodebuildRunner: xcodebuildRunner, sessionManager: sessionManager,
        )

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
        let screenshotMacWindowTool = ScreenshotMacWindowTool()

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

        // Create logging tools
        let startSimLogCapTool = StartSimLogCapTool(
            simctlRunner: simctlRunner, sessionManager: sessionManager,
        )
        let stopSimLogCapTool = StopSimLogCapTool(sessionManager: sessionManager)
        let startDeviceLogCapTool = StartDeviceLogCapTool(
            deviceCtlRunner: deviceCtlRunner, sessionManager: sessionManager,
        )
        let stopDeviceLogCapTool = StopDeviceLogCapTool(sessionManager: sessionManager)

        // Create extended simulator tools
        let eraseSimTool = EraseSimTool(simctlRunner: simctlRunner, sessionManager: sessionManager)
        let setSimLocationTool = SetSimLocationTool(
            simctlRunner: simctlRunner, sessionManager: sessionManager,
        )
        let resetSimLocationTool = ResetSimLocationTool(
            simctlRunner: simctlRunner, sessionManager: sessionManager,
        )
        let setSimAppearanceTool = SetSimAppearanceTool(
            simctlRunner: simctlRunner, sessionManager: sessionManager,
        )
        let simStatusBarTool = SimStatusBarTool(
            simctlRunner: simctlRunner, sessionManager: sessionManager,
        )

        // Create debug tools
        let lldbRunner = LLDBRunner()
        let buildDebugMacOSTool = BuildDebugMacOSTool(
            xcodebuildRunner: xcodebuildRunner, lldbRunner: lldbRunner,
            sessionManager: sessionManager,
        )
        let debugAttachSimTool = DebugAttachSimTool(
            lldbRunner: lldbRunner, simctlRunner: simctlRunner, sessionManager: sessionManager,
        )
        let debugDetachTool = DebugDetachTool(lldbRunner: lldbRunner)
        let debugBreakpointAddTool = DebugBreakpointAddTool(lldbRunner: lldbRunner)
        let debugBreakpointRemoveTool = DebugBreakpointRemoveTool(lldbRunner: lldbRunner)
        let debugContinueTool = DebugContinueTool(lldbRunner: lldbRunner)
        let debugStackTool = DebugStackTool(lldbRunner: lldbRunner)
        let debugVariablesTool = DebugVariablesTool(lldbRunner: lldbRunner)
        let debugLLDBCommandTool = DebugLLDBCommandTool(lldbRunner: lldbRunner)
        let debugEvaluateTool = DebugEvaluateTool(lldbRunner: lldbRunner)
        let debugThreadsTool = DebugThreadsTool(lldbRunner: lldbRunner)
        let debugWatchpointTool = DebugWatchpointTool(lldbRunner: lldbRunner)
        let debugStepTool = DebugStepTool(lldbRunner: lldbRunner)
        let debugMemoryTool = DebugMemoryTool(lldbRunner: lldbRunner)
        let debugSymbolLookupTool = DebugSymbolLookupTool(lldbRunner: lldbRunner)
        let debugViewHierarchyTool = DebugViewHierarchyTool(lldbRunner: lldbRunner)
        let debugViewBordersTool = DebugViewBordersTool(lldbRunner: lldbRunner)
        let debugProcessStatusTool = DebugProcessStatusTool(lldbRunner: lldbRunner)

        // Create UI automation tools
        let tapTool = TapTool(simctlRunner: simctlRunner, sessionManager: sessionManager)
        let longPressTool = LongPressTool(
            simctlRunner: simctlRunner, sessionManager: sessionManager,
        )
        let swipeTool = SwipeTool(simctlRunner: simctlRunner, sessionManager: sessionManager)
        let gestureTool = GestureTool(simctlRunner: simctlRunner, sessionManager: sessionManager)
        let typeTextTool = TypeTextTool(simctlRunner: simctlRunner, sessionManager: sessionManager)
        let keyPressTool = KeyPressTool(simctlRunner: simctlRunner, sessionManager: sessionManager)
        let buttonTool = ButtonTool(simctlRunner: simctlRunner, sessionManager: sessionManager)
        let screenshotTool = ScreenshotTool(
            simctlRunner: simctlRunner, sessionManager: sessionManager,
        )

        // Create Swift Package Manager tools
        let swiftRunner = SwiftRunner()
        let swiftPackageBuildTool = SwiftPackageBuildTool(
            swiftRunner: swiftRunner, sessionManager: sessionManager,
        )
        let swiftPackageTestTool = SwiftPackageTestTool(
            swiftRunner: swiftRunner, sessionManager: sessionManager,
        )
        let swiftPackageRunTool = SwiftPackageRunTool(
            swiftRunner: swiftRunner, sessionManager: sessionManager,
        )
        let swiftPackageCleanTool = SwiftPackageCleanTool(
            swiftRunner: swiftRunner, sessionManager: sessionManager,
        )
        let swiftPackageListTool = SwiftPackageListTool(
            swiftRunner: swiftRunner, sessionManager: sessionManager,
        )
        let swiftPackageStopTool = SwiftPackageStopTool(sessionManager: sessionManager)
        let swiftFormatTool = SwiftFormatTool(sessionManager: sessionManager)
        let swiftLintTool = SwiftLintTool(sessionManager: sessionManager)
        let swiftDiagnosticsTool = SwiftDiagnosticsTool(
            swiftRunner: swiftRunner, sessionManager: sessionManager,
        )

        // Create interact tools
        let interactRunner = InteractRunner()
        let interactUITreeTool = InteractUITreeTool(interactRunner: interactRunner)
        let interactClickTool = InteractClickTool(interactRunner: interactRunner)
        let interactSetValueTool = InteractSetValueTool(interactRunner: interactRunner)
        let interactGetValueTool = InteractGetValueTool(interactRunner: interactRunner)
        let interactMenuTool = InteractMenuTool(interactRunner: interactRunner)
        let interactFocusTool = InteractFocusTool(interactRunner: interactRunner)
        let interactKeyTool = InteractKeyTool(interactRunner: interactRunner)
        let interactFindTool = InteractFindTool(interactRunner: interactRunner)

        // Create instruments tools
        let xctraceRunner = XctraceRunner()
        let xctraceRecordTool = XctraceRecordTool(
            xctraceRunner: xctraceRunner, sessionManager: sessionManager,
        )
        let xctraceListTool = XctraceListTool(xctraceRunner: xctraceRunner)
        let xctraceExportTool = XctraceExportTool(xctraceRunner: xctraceRunner)

        // Create utility tools
        let cleanTool = CleanTool(
            xcodebuildRunner: xcodebuildRunner, sessionManager: sessionManager,
        )
        let doctorTool = DoctorTool(sessionManager: sessionManager)
        let scaffoldIOSTool = ScaffoldIOSProjectTool(pathUtility: pathUtility)
        let scaffoldMacOSTool = ScaffoldMacOSProjectTool(pathUtility: pathUtility)
        let searchCrashReportsTool = SearchCrashReportsTool()
        let diagnosticsTool = DiagnosticsTool(
            xcodebuildRunner: xcodebuildRunner, sessionManager: sessionManager,
        )

        // Build the complete tool registry: (ToolName, Tool) pairs
        let allTools: [(ToolName, Tool)] = [
            // Project tools
            (.createXcodeproj, createXcodeprojTool.tool()),
            (.listTargets, listTargetsTool.tool()),
            (.listBuildConfigurations, listBuildConfigurationsTool.tool()),
            (.listFiles, listFilesTool.tool()),
            (.getBuildSettings, getBuildSettingsTool.tool()),
            (.addFile, addFileTool.tool()),
            (.removeFile, removeFileTool.tool()),
            (.moveFile, moveFileTool.tool()),
            (.createGroup, createGroupTool.tool()),
            (.addTarget, addTargetTool.tool()),
            (.removeTarget, removeTargetTool.tool()),
            (.renameTarget, renameTargetTool.tool()),
            (.renameScheme, renameSchemeTool.tool()),
            (.createScheme, createSchemeTool.tool()),
            (.validateScheme, validateSchemeTool.tool()),
            (.createTestPlan, createTestPlanTool.tool()),
            (.addTargetToTestPlan, addTargetToTestPlanTool.tool()),
            (.removeTargetFromTestPlan, removeTargetFromTestPlanTool.tool()),
            (.setTestPlanTargetEnabled, setTestPlanTargetEnabledTool.tool()),
            (.addTestPlanToScheme, addTestPlanToSchemeTool.tool()),
            (.removeTestPlanFromScheme, removeTestPlanFromSchemeTool.tool()),
            (.listTestPlans, listTestPlansTool.tool()),
            (.setTestTargetApplication, setTestTargetApplicationTool.tool()),
            (.renameGroup, renameGroupTool.tool()),
            (.addDependency, addDependencyTool.tool()),
            (.setBuildSetting, setBuildSettingTool.tool()),
            (.addFramework, addFrameworkTool.tool()),
            (.addBuildPhase, addBuildPhaseTool.tool()),
            (.duplicateTarget, duplicateTargetTool.tool()),
            (.addSwiftPackage, addSwiftPackageTool.tool()),
            (.listSwiftPackages, listSwiftPackagesTool.tool()),
            (.removeSwiftPackage, removeSwiftPackageTool.tool()),
            (.listGroups, listGroupsTool.tool()),
            (.addSynchronizedFolder, addSynchronizedFolderTool.tool()),
            (.addTargetToSynchronizedFolder, addTargetToSynchronizedFolderTool.tool()),
            (.addSynchronizedFolderException, addSynchronizedFolderExceptionTool.tool()),
            (.addAppExtension, addAppExtensionTool.tool()),
            (.removeAppExtension, removeAppExtensionTool.tool()),
            (.listCopyFilesPhases, listCopyFilesPhases.tool()),
            (.addCopyFilesPhase, addCopyFilesPhase.tool()),
            (.addToCopyFilesPhase, addToCopyFilesPhase.tool()),
            (.removeCopyFilesPhase, removeCopyFilesPhase.tool()),
            (.listDocumentTypes, listDocumentTypesTool.tool()),
            (.manageDocumentType, manageDocumentTypeTool.tool()),
            (.listTypeIdentifiers, listTypeIdentifiersTool.tool()),
            (.manageTypeIdentifier, manageTypeIdentifierTool.tool()),
            (.listURLTypes, listURLTypesTool.tool()),
            (.manageURLType, manageURLTypeTool.tool()),
            // Session tools
            (.setSessionDefaults, setSessionDefaultsTool.tool()),
            (.showSessionDefaults, showSessionDefaultsTool.tool()),
            (.clearSessionDefaults, clearSessionDefaultsTool.tool()),
            (.syncXcodeDefaults, syncXcodeDefaultsTool.tool()),
            (.manageWorkflows, manageWorkflowsTool.tool()),
            // Simulator tools
            (.listSims, listSimsTool.tool()),
            (.bootSim, bootSimTool.tool()),
            (.openSim, openSimTool.tool()),
            (.buildSim, buildSimTool.tool()),
            (.buildRunSim, buildRunSimTool.tool()),
            (.installAppSim, installAppSimTool.tool()),
            (.launchAppSim, launchAppSimTool.tool()),
            (.stopAppSim, stopAppSimTool.tool()),
            (.getSimAppPath, getSimAppPathTool.tool()),
            (.testSim, testSimTool.tool()),
            (.recordSimVideo, recordSimVideoTool.tool()),
            (.launchAppLogsSim, launchAppLogsSimTool.tool()),
            (.previewCapture, previewCaptureTool.tool()),
            // Device tools
            (.listDevices, listDevicesTool.tool()),
            (.buildDevice, buildDeviceTool.tool()),
            (.installAppDevice, installAppDeviceTool.tool()),
            (.launchAppDevice, launchAppDeviceTool.tool()),
            (.stopAppDevice, stopAppDeviceTool.tool()),
            (.getDeviceAppPath, getDeviceAppPathTool.tool()),
            (.testDevice, testDeviceTool.tool()),
            // macOS tools
            (.buildMacOS, buildMacOSTool.tool()),
            (.buildRunMacOS, buildRunMacOSTool.tool()),
            (.launchMacApp, launchMacAppTool.tool()),
            (.stopMacApp, stopMacAppTool.tool()),
            (.getMacAppPath, getMacAppPathTool.tool()),
            (.testMacOS, testMacOSTool.tool()),
            (.startMacLogCap, startMacLogCapTool.tool()),
            (.stopMacLogCap, stopMacLogCapTool.tool()),
            (.screenshotMacWindow, screenshotMacWindowTool.tool()),
            // Discovery tools
            (.discoverProjs, discoverProjsTool.tool()),
            (.listSchemes, listSchemesTool.tool()),
            (.showBuildSettings, showBuildSettingsTool.tool()),
            (.getAppBundleId, getAppBundleIdTool.tool()),
            (.getMacBundleId, getMacBundleIdTool.tool()),
            (.listTestPlanTargets, listTestPlanTargetsTool.tool()),
            // Logging tools
            (.startSimLogCap, startSimLogCapTool.tool()),
            (.stopSimLogCap, stopSimLogCapTool.tool()),
            (.startDeviceLogCap, startDeviceLogCapTool.tool()),
            (.stopDeviceLogCap, stopDeviceLogCapTool.tool()),
            // Extended simulator tools
            (.eraseSims, eraseSimTool.tool()),
            (.setSimLocation, setSimLocationTool.tool()),
            (.resetSimLocation, resetSimLocationTool.tool()),
            (.setSimAppearance, setSimAppearanceTool.tool()),
            (.simStatusbar, simStatusBarTool.tool()),
            // Debug tools
            (.buildDebugMacOS, buildDebugMacOSTool.tool()),
            (.debugAttachSim, debugAttachSimTool.tool()),
            (.debugDetach, debugDetachTool.tool()),
            (.debugBreakpointAdd, debugBreakpointAddTool.tool()),
            (.debugBreakpointRemove, debugBreakpointRemoveTool.tool()),
            (.debugContinue, debugContinueTool.tool()),
            (.debugStack, debugStackTool.tool()),
            (.debugVariables, debugVariablesTool.tool()),
            (.debugLLDBCommand, debugLLDBCommandTool.tool()),
            (.debugEvaluate, debugEvaluateTool.tool()),
            (.debugThreads, debugThreadsTool.tool()),
            (.debugWatchpoint, debugWatchpointTool.tool()),
            (.debugStep, debugStepTool.tool()),
            (.debugMemory, debugMemoryTool.tool()),
            (.debugSymbolLookup, debugSymbolLookupTool.tool()),
            (.debugViewHierarchy, debugViewHierarchyTool.tool()),
            (.debugViewBorders, debugViewBordersTool.tool()),
            (.debugProcessStatus, debugProcessStatusTool.tool()),
            // UI Automation tools
            (.tap, tapTool.tool()),
            (.longPress, longPressTool.tool()),
            (.swipe, swipeTool.tool()),
            (.gesture, gestureTool.tool()),
            (.typeText, typeTextTool.tool()),
            (.keyPress, keyPressTool.tool()),
            (.button, buttonTool.tool()),
            (.screenshot, screenshotTool.tool()),
            // Swift Package Manager tools
            (.swiftPackageBuild, swiftPackageBuildTool.tool()),
            (.swiftPackageTest, swiftPackageTestTool.tool()),
            (.swiftPackageRun, swiftPackageRunTool.tool()),
            (.swiftPackageClean, swiftPackageCleanTool.tool()),
            (.swiftPackageList, swiftPackageListTool.tool()),
            (.swiftPackageStop, swiftPackageStopTool.tool()),
            (.swiftFormat, swiftFormatTool.tool()),
            (.swiftLint, swiftLintTool.tool()),
            (.swiftDiagnostics, swiftDiagnosticsTool.tool()),
            // Interact tools
            (.interactUITree, interactUITreeTool.tool()),
            (.interactClick, interactClickTool.tool()),
            (.interactSetValue, interactSetValueTool.tool()),
            (.interactGetValue, interactGetValueTool.tool()),
            (.interactMenu, interactMenuTool.tool()),
            (.interactFocus, interactFocusTool.tool()),
            (.interactKey, interactKeyTool.tool()),
            (.interactFind, interactFindTool.tool()),
            // Instruments tools
            (.xctraceRecord, xctraceRecordTool.tool()),
            (.xctraceList, xctraceListTool.tool()),
            (.xctraceExport, xctraceExportTool.tool()),
            // Utility tools
            (.clean, cleanTool.tool()),
            (.doctor, doctorTool.tool()),
            (.scaffoldIOS, scaffoldIOSTool.tool()),
            (.scaffoldMacOS, scaffoldMacOSTool.tool()),
            (.searchCrashReports, searchCrashReportsTool.tool()),
            (.diagnostics, diagnosticsTool.tool()),
        ]

        // Register tools/list handler — filters by enabled workflows
        await server.withMethodHandler(ListTools.self) { _ in
            var tools: [Tool] = []
            for (name, tool) in allTools {
                // manage_workflows is always visible
                if name == .manageWorkflows {
                    tools.append(tool)
                } else if await workflowManager.isEnabled(name.workflow) {
                    tools.append(tool)
                }
            }
            return ListTools.Result(tools: tools)
        }

        // Register tools/call handler
        await server.withMethodHandler(CallTool.self) { params in
            guard let toolName = ToolName(rawValue: params.name) else {
                throw MCPError.methodNotFound("Unknown tool: \(params.name)")
            }

            // Check workflow is enabled (manage_workflows is always allowed)
            if toolName != .manageWorkflows {
                let enabled = await workflowManager.isEnabled(toolName.workflow)
                if !enabled {
                    throw MCPError.invalidRequest(
                        "Tool '\(params.name)' is disabled. Its workflow '\(toolName.workflow.rawValue)' is currently disabled. Use manage_workflows to re-enable it.",
                    )
                }
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
                case .renameTarget:
                    return try renameTargetTool.execute(arguments: arguments)
                case .renameScheme:
                    return try renameSchemeTool.execute(arguments: arguments)
                case .createScheme:
                    return try createSchemeTool.execute(arguments: arguments)
                case .validateScheme:
                    return try validateSchemeTool.execute(arguments: arguments)
                case .createTestPlan:
                    return try createTestPlanTool.execute(arguments: arguments)
                case .addTargetToTestPlan:
                    return try addTargetToTestPlanTool.execute(arguments: arguments)
                case .removeTargetFromTestPlan:
                    return try removeTargetFromTestPlanTool.execute(arguments: arguments)
                case .setTestPlanTargetEnabled:
                    return try setTestPlanTargetEnabledTool.execute(arguments: arguments)
                case .addTestPlanToScheme:
                    return try addTestPlanToSchemeTool.execute(arguments: arguments)
                case .removeTestPlanFromScheme:
                    return try removeTestPlanFromSchemeTool.execute(arguments: arguments)
                case .listTestPlans:
                    return try listTestPlansTool.execute(arguments: arguments)
                case .setTestTargetApplication:
                    return try setTestTargetApplicationTool.execute(arguments: arguments)
                case .renameGroup:
                    return try renameGroupTool.execute(arguments: arguments)
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
                case .addTargetToSynchronizedFolder:
                    return try addTargetToSynchronizedFolderTool.execute(arguments: arguments)
                case .addSynchronizedFolderException:
                    return try addSynchronizedFolderExceptionTool.execute(arguments: arguments)
                case .addAppExtension:
                    return try addAppExtensionTool.execute(arguments: arguments)
                case .removeAppExtension:
                    return try removeAppExtensionTool.execute(arguments: arguments)
                case .listCopyFilesPhases:
                    return try listCopyFilesPhases.execute(arguments: arguments)
                case .addCopyFilesPhase:
                    return try addCopyFilesPhase.execute(arguments: arguments)
                case .addToCopyFilesPhase:
                    return try addToCopyFilesPhase.execute(arguments: arguments)
                case .removeCopyFilesPhase:
                    return try removeCopyFilesPhase.execute(arguments: arguments)
                case .listDocumentTypes:
                    return try listDocumentTypesTool.execute(arguments: arguments)
                case .manageDocumentType:
                    return try manageDocumentTypeTool.execute(arguments: arguments)
                case .listTypeIdentifiers:
                    return try listTypeIdentifiersTool.execute(arguments: arguments)
                case .manageTypeIdentifier:
                    return try manageTypeIdentifierTool.execute(arguments: arguments)
                case .listURLTypes:
                    return try listURLTypesTool.execute(arguments: arguments)
                case .manageURLType:
                    return try manageURLTypeTool.execute(arguments: arguments)
                // Session tools
                case .setSessionDefaults:
                    return try await setSessionDefaultsTool.execute(arguments: arguments)
                case .showSessionDefaults:
                    return try await showSessionDefaultsTool.execute(arguments: arguments)
                case .clearSessionDefaults:
                    return try await clearSessionDefaultsTool.execute(arguments: arguments)
                case .syncXcodeDefaults:
                    return try await syncXcodeDefaultsTool.execute(arguments: arguments)
                case .manageWorkflows:
                    let (result, changed) = try await manageWorkflowsTool.execute(
                        arguments: arguments,
                    )
                    if changed {
                        try await server.notify(
                            Message<ToolListChangedNotification>(
                                method: ToolListChangedNotification.name,
                                params: Empty(),
                            ),
                        )
                    }
                    return result
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
                case .previewCapture:
                    return try await previewCaptureTool.execute(arguments: arguments)
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
                case .startMacLogCap:
                    return try await startMacLogCapTool.execute(arguments: arguments)
                case .stopMacLogCap:
                    return try await stopMacLogCapTool.execute(arguments: arguments)
                case .screenshotMacWindow:
                    return try await screenshotMacWindowTool.execute(arguments: arguments)
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
                case .buildDebugMacOS:
                    return try await buildDebugMacOSTool.execute(arguments: arguments)
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
                case .debugEvaluate:
                    return try await debugEvaluateTool.execute(arguments: arguments)
                case .debugThreads:
                    return try await debugThreadsTool.execute(arguments: arguments)
                case .debugWatchpoint:
                    return try await debugWatchpointTool.execute(arguments: arguments)
                case .debugStep:
                    return try await debugStepTool.execute(arguments: arguments)
                case .debugMemory:
                    return try await debugMemoryTool.execute(arguments: arguments)
                case .debugSymbolLookup:
                    return try await debugSymbolLookupTool.execute(arguments: arguments)
                case .debugViewHierarchy:
                    return try await debugViewHierarchyTool.execute(arguments: arguments)
                case .debugViewBorders:
                    return try await debugViewBordersTool.execute(arguments: arguments)
                case .debugProcessStatus:
                    return try await debugProcessStatusTool.execute(arguments: arguments)
                // UI Automation tools
                case .tap:
                    return try await tapTool.execute(arguments: arguments)
                case .longPress:
                    return try await longPressTool.execute(arguments: arguments)
                case .swipe:
                    return try await swipeTool.execute(arguments: arguments)
                case .gesture:
                    return try await gestureTool.execute(arguments: arguments)
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
                case .swiftFormat:
                    return try await swiftFormatTool.execute(arguments: arguments)
                case .swiftLint:
                    return try await swiftLintTool.execute(arguments: arguments)
                case .swiftDiagnostics:
                    return try await swiftDiagnosticsTool.execute(arguments: arguments)
                // Interact tools
                case .interactUITree:
                    return try await interactUITreeTool.execute(arguments: arguments)
                case .interactClick:
                    return try await interactClickTool.execute(arguments: arguments)
                case .interactSetValue:
                    return try await interactSetValueTool.execute(arguments: arguments)
                case .interactGetValue:
                    return try await interactGetValueTool.execute(arguments: arguments)
                case .interactMenu:
                    return try interactMenuTool.execute(arguments: arguments)
                case .interactFocus:
                    return try await interactFocusTool.execute(arguments: arguments)
                case .interactKey:
                    return try interactKeyTool.execute(arguments: arguments)
                case .interactFind:
                    return try await interactFindTool.execute(arguments: arguments)
                // Instruments tools
                case .xctraceRecord:
                    return try await xctraceRecordTool.execute(arguments: arguments)
                case .xctraceList:
                    return try await xctraceListTool.execute(arguments: arguments)
                case .xctraceExport:
                    return try await xctraceExportTool.execute(arguments: arguments)
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
                case .diagnostics:
                    return try await diagnosticsTool.execute(arguments: arguments)
            }
        }

        // Use stdio transport
        let transport = StdioTransport(logger: logger)
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    }
}

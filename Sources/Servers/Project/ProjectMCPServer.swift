import Foundation
import Logging
import MCP
import XCMCPCore
import XCMCPTools

/// All available tool names exposed by the xc-project MCP server.
public enum ProjectToolName: String, CaseIterable, Sendable {
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
}

/// MCP server for Xcode project file manipulation.
///
/// This focused server provides tools for creating and modifying .xcodeproj files
/// using the XcodeProj library. It is stateless and does not require session management.
///
/// ## Token Efficiency
///
/// This server exposes 23 tools with approximately 5K token overhead, compared to
/// ~50K for the full monolithic xc-mcp server. Use this server when you only need
/// project manipulation capabilities.
///
/// ## Tools
///
/// - Project creation: `create_xcodeproj`
/// - Target management: `add_target`, `remove_target`, `duplicate_target`, `list_targets`
/// - File management: `add_file`, `remove_file`, `move_file`, `list_files`
/// - Group management: `create_group`, `list_groups`, `add_synchronized_folder`
/// - Build settings: `get_build_settings`, `set_build_setting`, `list_build_configurations`
/// - Dependencies: `add_dependency`, `add_framework`, `add_build_phase`
/// - Swift packages: `add_swift_package`, `list_swift_packages`, `remove_swift_package`
/// - App extensions: `add_app_extension`, `remove_app_extension`
public struct ProjectMCPServer: Sendable {
    private let basePath: String
    private let logger: Logger

    /// Creates a new project MCP server instance.
    ///
    /// - Parameters:
    ///   - basePath: The root directory for file operations.
    ///   - logger: Logger instance for diagnostic output.
    public init(basePath: String, logger: Logger) {
        self.basePath = basePath
        self.logger = logger
    }

    /// Starts the MCP server and begins processing requests.
    public func run() async throws {
        let server = Server(
            name: "xc-project",
            version: "1.0.0",
            capabilities: .init(tools: .init())
        )

        // Create path utility
        let pathUtility = PathUtility(basePath: basePath)

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

        // Register tools/list handler
        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: [
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
            ])
        }

        // Register tools/call handler
        await server.withMethodHandler(CallTool.self) { params in
            guard let toolName = ProjectToolName(rawValue: params.name) else {
                throw MCPError.methodNotFound("Unknown tool: \(params.name)")
            }

            let arguments = params.arguments ?? [:]

            switch toolName {
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
            }
        }

        // Use stdio transport
        let transport = StdioTransport(logger: logger)
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    }
}

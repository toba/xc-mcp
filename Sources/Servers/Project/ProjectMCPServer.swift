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
    case removeGroup = "remove_group"
    case addTarget = "add_target"
    case removeTarget = "remove_target"
    case renameTarget = "rename_target"
    case renameScheme = "rename_scheme"
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
    case removeSynchronizedFolder = "remove_synchronized_folder"
    case addAppExtension = "add_app_extension"
    case removeAppExtension = "remove_app_extension"
    case addTargetToSynchronizedFolder = "add_target_to_synchronized_folder"
    case removeTargetFromSynchronizedFolder = "remove_target_from_synchronized_folder"
    case addSynchronizedFolderException = "add_synchronized_folder_exception"
    case removeSynchronizedFolderException = "remove_synchronized_folder_exception"
    case listSynchronizedFolderExceptions = "list_synchronized_folder_exceptions"
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
}

/// MCP server for Xcode project file manipulation.
///
/// This focused server provides tools for creating and modifying .xcodeproj files
/// using the XcodeProj library. It is stateless and does not require session management.
///
/// ## Token Efficiency
///
/// This server exposes 29 tools with approximately 5K token overhead, compared to
/// ~50K for the full monolithic xc-mcp server. Use this server when you only need
/// project manipulation capabilities.
///
/// ## Tools
///
/// - Project creation: `create_xcodeproj`
/// - Target management: `add_target`, `remove_target`, `duplicate_target`, `list_targets`
/// - File management: `add_file`, `remove_file`, `move_file`, `list_files`
/// - Group management: `create_group`, `list_groups`, `add_synchronized_folder`,
///   `add_target_to_synchronized_folder`, `add_synchronized_folder_exception`,
///   `remove_synchronized_folder_exception`, `list_synchronized_folder_exceptions`
/// - Build settings: `get_build_settings`, `set_build_setting`, `list_build_configurations`
/// - Dependencies: `add_dependency`, `add_framework`, `add_build_phase`
/// - Copy files phases: `list_copy_files_phases`, `add_copy_files_phase`,
///   `add_to_copy_files_phase`, `remove_copy_files_phase`
/// - Swift packages: `add_swift_package`, `list_swift_packages`, `remove_swift_package`
/// - App extensions: `add_app_extension`, `remove_app_extension`
public struct ProjectMCPServer: Sendable {
    private let basePath: String
    private let sandboxEnabled: Bool
    private let logger: Logger

    /// Creates a new project MCP server instance.
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

    /// Starts the MCP server and begins processing requests.
    public func run() async throws {
        let server = Server(
            name: "xc-project",
            version: "1.0.0",
            capabilities: .init(tools: .init())
        )

        // Create path utility
        let pathUtility = PathUtility(basePath: basePath, sandboxEnabled: sandboxEnabled)

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
        let removeGroupTool = RemoveGroupTool(pathUtility: pathUtility)
        let addTargetTool = AddTargetTool(pathUtility: pathUtility)
        let removeTargetTool = RemoveTargetTool(pathUtility: pathUtility)
        let renameTargetTool = RenameTargetTool(pathUtility: pathUtility)
        let renameSchemeTool = RenameSchemeTool(pathUtility: pathUtility)
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
        let removeSynchronizedFolderTool = RemoveFolderTool(pathUtility: pathUtility)
        let addAppExtensionTool = AddAppExtensionTool(pathUtility: pathUtility)
        let removeAppExtensionTool = RemoveAppExtensionTool(pathUtility: pathUtility)
        let listDocumentTypesTool = ListDocumentTypesTool(pathUtility: pathUtility)
        let manageDocumentTypeTool = ManageDocumentTypeTool(pathUtility: pathUtility)
        let listTypeIdentifiersTool = ListTypeIdentifiersTool(pathUtility: pathUtility)
        let manageTypeIdentifierTool = ManageTypeIdentifierTool(pathUtility: pathUtility)
        let listURLTypesTool = ListURLTypesTool(pathUtility: pathUtility)
        let manageURLTypeTool = ManageURLTypeTool(pathUtility: pathUtility)
        let addTargetToSynchronizedFolderTool = AddTargetToSynchronizedFolderTool(
            pathUtility: pathUtility
        )
        let removeTargetFromSynchronizedFolderTool = RemoveTargetFromSynchronizedFolderTool(
            pathUtility: pathUtility
        )
        let addSynchronizedFolderExceptionTool = AddSynchronizedFolderExceptionTool(
            pathUtility: pathUtility
        )
        let removeSynchronizedFolderExceptionTool = RemoveSynchronizedFolderExceptionTool(
            pathUtility: pathUtility
        )
        let listSynchronizedFolderExceptionsTool = ListSynchronizedFolderExceptionsTool(
            pathUtility: pathUtility
        )
        let listCopyFilesPhases = ListCopyFilesPhases(pathUtility: pathUtility)
        let addCopyFilesPhase = AddCopyFilesPhase(pathUtility: pathUtility)
        let addToCopyFilesPhase = AddToCopyFilesPhase(pathUtility: pathUtility)
        let removeCopyFilesPhase = RemoveCopyFilesPhase(pathUtility: pathUtility)

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
                removeGroupTool.tool(),
                addTargetTool.tool(),
                removeTargetTool.tool(),
                renameTargetTool.tool(),
                renameSchemeTool.tool(),
                renameGroupTool.tool(),
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
                removeSynchronizedFolderTool.tool(),
                addAppExtensionTool.tool(),
                removeAppExtensionTool.tool(),
                listDocumentTypesTool.tool(),
                manageDocumentTypeTool.tool(),
                listTypeIdentifiersTool.tool(),
                manageTypeIdentifierTool.tool(),
                listURLTypesTool.tool(),
                manageURLTypeTool.tool(),
                addTargetToSynchronizedFolderTool.tool(),
                removeTargetFromSynchronizedFolderTool.tool(),
                addSynchronizedFolderExceptionTool.tool(),
                removeSynchronizedFolderExceptionTool.tool(),
                listSynchronizedFolderExceptionsTool.tool(),
                listCopyFilesPhases.tool(),
                addCopyFilesPhase.tool(),
                addToCopyFilesPhase.tool(),
                removeCopyFilesPhase.tool(),
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
            case .removeGroup:
                return try removeGroupTool.execute(arguments: arguments)
            case .addTarget:
                return try addTargetTool.execute(arguments: arguments)
            case .removeTarget:
                return try removeTargetTool.execute(arguments: arguments)
            case .renameTarget:
                return try renameTargetTool.execute(arguments: arguments)
            case .renameScheme:
                return try renameSchemeTool.execute(arguments: arguments)
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
            case .removeSynchronizedFolder:
                return try removeSynchronizedFolderTool.execute(arguments: arguments)
            case .addAppExtension:
                return try addAppExtensionTool.execute(arguments: arguments)
            case .removeAppExtension:
                return try removeAppExtensionTool.execute(arguments: arguments)
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
            case .addTargetToSynchronizedFolder:
                return try addTargetToSynchronizedFolderTool.execute(arguments: arguments)
            case .removeTargetFromSynchronizedFolder:
                return try removeTargetFromSynchronizedFolderTool.execute(arguments: arguments)
            case .addSynchronizedFolderException:
                return try addSynchronizedFolderExceptionTool.execute(arguments: arguments)
            case .removeSynchronizedFolderException:
                return try removeSynchronizedFolderExceptionTool.execute(arguments: arguments)
            case .listSynchronizedFolderExceptions:
                return try listSynchronizedFolderExceptionsTool.execute(arguments: arguments)
            case .listCopyFilesPhases:
                return try listCopyFilesPhases.execute(arguments: arguments)
            case .addCopyFilesPhase:
                return try addCopyFilesPhase.execute(arguments: arguments)
            case .addToCopyFilesPhase:
                return try addToCopyFilesPhase.execute(arguments: arguments)
            case .removeCopyFilesPhase:
                return try removeCopyFilesPhase.execute(arguments: arguments)
            }
        }

        // Use stdio transport
        let transport = StdioTransport(logger: logger)
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    }
}

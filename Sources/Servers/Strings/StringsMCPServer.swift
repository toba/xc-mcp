import Foundation
import Logging
import MCP
import XCMCPCore
import XCMCPTools

/// All available tool names exposed by the xc-strings MCP server.
public enum StringsToolName: String, CaseIterable, Sendable {
    case listKeys = "xcstrings_list_keys"
    case listLanguages = "xcstrings_list_languages"
    case listUntranslated = "xcstrings_list_untranslated"
    case getSourceLanguage = "xcstrings_get_source_language"
    case getKey = "xcstrings_get_key"
    case checkKey = "xcstrings_check_key"
    case statsCoverage = "xcstrings_stats_coverage"
    case statsProgress = "xcstrings_stats_progress"
    case batchStatsCoverage = "xcstrings_batch_stats_coverage"
    case createFile = "xcstrings_create_file"
    case addTranslation = "xcstrings_add_translation"
    case addTranslations = "xcstrings_add_translations"
    case updateTranslation = "xcstrings_update_translation"
    case updateTranslations = "xcstrings_update_translations"
    case renameKey = "xcstrings_rename_key"
    case deleteKey = "xcstrings_delete_key"
    case deleteTranslation = "xcstrings_delete_translation"
    case deleteTranslations = "xcstrings_delete_translations"
    case listStale = "xcstrings_list_stale"
    case batchListStale = "xcstrings_batch_list_stale"
    case batchCheckKeys = "xcstrings_batch_check_keys"
    case batchAddTranslations = "xcstrings_batch_add_translations"
    case batchUpdateTranslations = "xcstrings_batch_update_translations"
    case checkCoverage = "xcstrings_check_coverage"
}

/// MCP server for Xcode String Catalog (.xcstrings) file manipulation.
///
/// This focused server provides tools for reading and modifying .xcstrings files
/// used for localization in Xcode projects.
///
/// ## Token Efficiency
///
/// This server exposes 18 tools with approximately 6K token overhead. Use this server
/// when you need localization management capabilities.
///
/// ## Tools
///
/// - Read operations: `xcstrings_list_keys`, `xcstrings_list_languages`, `xcstrings_list_untranslated`,
///   `xcstrings_get_source_language`, `xcstrings_get_key`, `xcstrings_check_key`
/// - Statistics: `xcstrings_stats_coverage`, `xcstrings_stats_progress`, `xcstrings_batch_stats_coverage`
/// - Create: `xcstrings_create_file`
/// - Write operations: `xcstrings_add_translation`, `xcstrings_add_translations`,
///   `xcstrings_update_translation`, `xcstrings_update_translations`, `xcstrings_rename_key`
/// - Delete operations: `xcstrings_delete_key`, `xcstrings_delete_translation`, `xcstrings_delete_translations`
public struct StringsMCPServer: Sendable {
    private let basePath: String
    private let sandboxEnabled: Bool
    private let logger: Logger

    /// Creates a new strings MCP server instance.
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
            name: "xc-strings",
            version: "1.0.0",
            capabilities: .init(tools: .init())
        )

        // Create path utility
        let pathUtility = PathUtility(basePath: basePath, sandboxEnabled: sandboxEnabled)

        // Create tools
        let listKeysTool = XCStringsListKeysTool(pathUtility: pathUtility)
        let listLanguagesTool = XCStringsListLanguagesTool(pathUtility: pathUtility)
        let listUntranslatedTool = XCStringsListUntranslatedTool(pathUtility: pathUtility)
        let getSourceLanguageTool = XCStringsGetSourceLanguageTool(pathUtility: pathUtility)
        let getKeyTool = XCStringsGetKeyTool(pathUtility: pathUtility)
        let checkKeyTool = XCStringsCheckKeyTool(pathUtility: pathUtility)
        let statsCoverageTool = XCStringsStatsCoverageTool(pathUtility: pathUtility)
        let statsProgressTool = XCStringsStatsProgressTool(pathUtility: pathUtility)
        let batchStatsCoverageTool = XCStringsBatchStatsCoverageTool(pathUtility: pathUtility)
        let createFileTool = XCStringsCreateFileTool(pathUtility: pathUtility)
        let addTranslationTool = XCStringsAddTranslationTool(pathUtility: pathUtility)
        let addTranslationsTool = XCStringsAddTranslationsTool(pathUtility: pathUtility)
        let updateTranslationTool = XCStringsUpdateTranslationTool(pathUtility: pathUtility)
        let updateTranslationsTool = XCStringsUpdateTranslationsTool(pathUtility: pathUtility)
        let renameKeyTool = XCStringsRenameKeyTool(pathUtility: pathUtility)
        let deleteKeyTool = XCStringsDeleteKeyTool(pathUtility: pathUtility)
        let deleteTranslationTool = XCStringsDeleteTranslationTool(pathUtility: pathUtility)
        let deleteTranslationsTool = XCStringsDeleteTranslationsTool(pathUtility: pathUtility)
        let listStaleTool = XCStringsListStaleTool(pathUtility: pathUtility)
        let batchListStaleTool = XCStringsBatchListStaleTool(pathUtility: pathUtility)
        let batchCheckKeysTool = XCStringsBatchCheckKeysTool(pathUtility: pathUtility)
        let batchAddTranslationsTool = XCStringsBatchAddTranslationsTool(pathUtility: pathUtility)
        let batchUpdateTranslationsTool = XCStringsBatchUpdateTranslationsTool(
            pathUtility: pathUtility
        )
        let checkCoverageTool = XCStringsCheckCoverageTool(pathUtility: pathUtility)

        // Register tools/list handler
        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: [
                listKeysTool.tool(),
                listLanguagesTool.tool(),
                listUntranslatedTool.tool(),
                getSourceLanguageTool.tool(),
                getKeyTool.tool(),
                checkKeyTool.tool(),
                statsCoverageTool.tool(),
                statsProgressTool.tool(),
                batchStatsCoverageTool.tool(),
                createFileTool.tool(),
                addTranslationTool.tool(),
                addTranslationsTool.tool(),
                updateTranslationTool.tool(),
                updateTranslationsTool.tool(),
                renameKeyTool.tool(),
                deleteKeyTool.tool(),
                deleteTranslationTool.tool(),
                deleteTranslationsTool.tool(),
                listStaleTool.tool(),
                batchListStaleTool.tool(),
                batchCheckKeysTool.tool(),
                batchAddTranslationsTool.tool(),
                batchUpdateTranslationsTool.tool(),
                checkCoverageTool.tool(),
            ])
        }

        // Register tools/call handler
        await server.withMethodHandler(CallTool.self) { params in
            guard let toolName = StringsToolName(rawValue: params.name) else {
                throw MCPError.methodNotFound("Unknown tool: \(params.name)")
            }

            let arguments = params.arguments ?? [:]

            switch toolName {
            case .listKeys:
                return try await listKeysTool.execute(arguments: arguments)
            case .listLanguages:
                return try await listLanguagesTool.execute(arguments: arguments)
            case .listUntranslated:
                return try await listUntranslatedTool.execute(arguments: arguments)
            case .getSourceLanguage:
                return try await getSourceLanguageTool.execute(arguments: arguments)
            case .getKey:
                return try await getKeyTool.execute(arguments: arguments)
            case .checkKey:
                return try await checkKeyTool.execute(arguments: arguments)
            case .statsCoverage:
                return try await statsCoverageTool.execute(arguments: arguments)
            case .statsProgress:
                return try await statsProgressTool.execute(arguments: arguments)
            case .batchStatsCoverage:
                return try await batchStatsCoverageTool.execute(arguments: arguments)
            case .createFile:
                return try await createFileTool.execute(arguments: arguments)
            case .addTranslation:
                return try await addTranslationTool.execute(arguments: arguments)
            case .addTranslations:
                return try await addTranslationsTool.execute(arguments: arguments)
            case .updateTranslation:
                return try await updateTranslationTool.execute(arguments: arguments)
            case .updateTranslations:
                return try await updateTranslationsTool.execute(arguments: arguments)
            case .renameKey:
                return try await renameKeyTool.execute(arguments: arguments)
            case .deleteKey:
                return try await deleteKeyTool.execute(arguments: arguments)
            case .deleteTranslation:
                return try await deleteTranslationTool.execute(arguments: arguments)
            case .deleteTranslations:
                return try await deleteTranslationsTool.execute(arguments: arguments)
            case .listStale:
                return try await listStaleTool.execute(arguments: arguments)
            case .batchListStale:
                return try batchListStaleTool.execute(arguments: arguments)
            case .batchCheckKeys:
                return try await batchCheckKeysTool.execute(arguments: arguments)
            case .batchAddTranslations:
                return try await batchAddTranslationsTool.execute(arguments: arguments)
            case .batchUpdateTranslations:
                return try await batchUpdateTranslationsTool.execute(arguments: arguments)
            case .checkCoverage:
                return try await checkCoverageTool.execute(arguments: arguments)
            }
        }

        // Use stdio transport
        let transport = StdioTransport(logger: logger)
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    }
}

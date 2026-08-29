import MCP
import Logging
import XCMCPCore
import Foundation
import XCMCPTools

/// MCP server for Xcode String Catalog (.xcstrings) file manipulation.
///
/// This focused server provides tools for reading and modifying .xcstrings files used for
/// localization in Xcode projects.
///
/// ## Token Efficiency
///
/// This server exposes the tools `ToolRegistry` marks with `ServerSet.strings`. Selecting a focused
/// server trims the tool surface a client pays for.
///
/// ## Tools
///
/// - Read operations: `xcstrings_list_keys`, `xcstrings_list_languages`,
///   `xcstrings_list_untranslated`, `xcstrings_get_source_language`, `xcstrings_get_key`,
///   `xcstrings_check_key`
/// - Statistics: `xcstrings_stats_coverage`, `xcstrings_stats_progress`,
///   `xcstrings_batch_stats_coverage`
/// - Create: `xcstrings_create_file`
/// - Write operations: `xcstrings_add_translation`, `xcstrings_add_translations`,
///   `xcstrings_update_translation`, `xcstrings_update_translations`, `xcstrings_rename_key`
/// - Delete operations: `xcstrings_delete_key`, `xcstrings_delete_translation`,
///   `xcstrings_delete_translations`
public struct StringsMCPServer: Sendable {
    private let basePath: String
    private let sandboxEnabled: Bool
    private let logger: Logger

    /// Creates a new strings MCP server instance.
    ///
    /// - Parameters:
    ///   - basePath: The root directory for file operations.
    ///   - sandboxEnabled: Whether to enforce that paths stay within the base directory. Defaults
    ///     to `true`.
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
            capabilities: .init(tools: .init()),
        )

        await installRegistryToolHandlers(
            on: server, as: .strings,
            deps: ToolDeps(basePath: basePath, sandboxEnabled: sandboxEnabled))

        // Use stdio transport
        let transport = StdioTransport(logger: logger)
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    }
}

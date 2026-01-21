import ArgumentParser
import Foundation
import Logging

/// Command-line interface for the xc-project MCP server.
///
/// This focused server provides Xcode project manipulation tools with minimal
/// token overhead (~5K tokens vs ~50K for the full xc-mcp server).
///
/// ## Usage
///
/// ```bash
/// # Start with default settings (current directory)
/// xc-project
///
/// # Start with a specific base path
/// xc-project /path/to/project
///
/// # Enable verbose logging
/// xc-project --verbose
/// ```
@main
struct ProjectServerCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "xc-project",
        abstract: "MCP server for Xcode project file manipulation (23 tools, ~5K tokens)"
    )

    @Argument(help: "Base path for the server to operate in. Defaults to current directory.")
    var basePath: String?

    @Flag(name: .shortAndLong, help: "Enable verbose logging (debug level)")
    var verbose: Bool = false

    mutating func run() async throws {
        let logLevel: Logger.Level = verbose ? .debug : .info
        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardError(label: label)
            handler.logLevel = logLevel
            return handler
        }

        let logger = Logger(label: "com.toba.xc-project")

        let resolvedBasePath = basePath ?? FileManager.default.currentDirectoryPath

        let server = ProjectMCPServer(basePath: resolvedBasePath, logger: logger)
        try await server.run()
    }
}

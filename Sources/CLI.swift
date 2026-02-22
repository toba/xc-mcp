import Logging
import Foundation
import ArgumentParser

/// Command-line interface for the Xcode MCP server.
///
/// This is the main entry point for the xc-mcp executable. It parses command-line
/// arguments and starts the MCP server with the appropriate configuration.
///
/// ## Usage
///
/// ```bash
/// # Start with default settings (current directory)
/// xc-mcp
///
/// # Start with a specific base path
/// xc-mcp /path/to/project
///
/// # Enable verbose logging
/// xc-mcp --verbose
/// ```
@main
struct XcodeMCPServerCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "xc-mcp",
        abstract: "MCP server for Xcode project manipulation, building, and testing",
    )

    /// The base path for the server to operate in.
    ///
    /// All file operations are restricted to this directory and its subdirectories
    /// for security. If not specified, defaults to the current working directory.
    @Argument(help: "Base path for the server to operate in. Defaults to current directory.")
    var basePath: String?

    /// Enables verbose debug logging when set to true.
    @Flag(name: .shortAndLong, help: "Enable verbose logging (debug level)")
    var verbose: Bool = false

    /// Runs the MCP server.
    ///
    /// Initializes the logging system, creates the server instance, and starts
    /// listening for MCP requests over stdio transport.
    ///
    /// - Throws: An error if the server fails to start or encounters a fatal error.
    mutating func run() async throws {
        let logLevel: Logger.Level = verbose ? .debug : .info
        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardError(label: label)
            handler.logLevel = logLevel
            return handler
        }

        let logger = Logger(label: "com.toba.xc-mcp")

        let resolvedBasePath = basePath ?? FileManager.default.currentDirectoryPath

        let server = XcodeMCPServer(basePath: resolvedBasePath, logger: logger)
        try await server.run()
    }
}

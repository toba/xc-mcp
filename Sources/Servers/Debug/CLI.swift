import ArgumentParser
import Foundation
import Logging

/// Command-line interface for the xc-debug MCP server.
///
/// This focused server provides LLDB debugging tools with minimal
/// token overhead (~2K tokens vs ~50K for the full xc-mcp server).
///
/// ## Usage
///
/// ```bash
/// # Start with default settings (current directory)
/// xc-debug
///
/// # Start with a specific base path
/// xc-debug /path/to/project
///
/// # Enable verbose logging
/// xc-debug --verbose
/// ```
@main
struct DebugServerCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "xc-debug",
        abstract: "MCP server for LLDB debugging operations (8 tools, ~2K tokens)"
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

        let logger = Logger(label: "com.toba.xc-debug")

        let resolvedBasePath = basePath ?? FileManager.default.currentDirectoryPath

        let server = DebugMCPServer(basePath: resolvedBasePath, logger: logger)
        try await server.run()
    }
}

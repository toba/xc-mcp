import Logging
import Foundation
import ArgumentParser

/// Command-line interface for the xc-build MCP server.
///
/// This focused server provides macOS build, discovery, and utility tools
/// with moderate token overhead (~3K tokens vs ~50K for the full xc-mcp server).
///
/// ## Usage
///
/// ```bash
/// # Start with default settings (current directory)
/// xc-build
///
/// # Start with a specific base path
/// xc-build /path/to/project
///
/// # Enable verbose logging
/// xc-build --verbose
/// ```
@main
struct BuildServerCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "xc-build",
        abstract: "MCP server for macOS builds, discovery, and utilities (18 tools, ~3K tokens)",
    )

    @Argument(help: "Base path for the server to operate in. Defaults to current directory.")
    var basePath: String?

    @Flag(name: .shortAndLong, help: "Enable verbose logging (debug level)")
    var verbose: Bool = false

    @Flag(
        name: .long, help: "Disable path sandboxing (allow access to paths outside base directory)",
    )
    var noSandbox: Bool = false

    mutating func run() async throws {
        let logLevel: Logger.Level = verbose ? .debug : .info
        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardError(label: label)
            handler.logLevel = logLevel
            return handler
        }

        let logger = Logger(label: "com.toba.xc-build")

        let resolvedBasePath = basePath ?? FileManager.default.currentDirectoryPath

        let server = BuildMCPServer(
            basePath: resolvedBasePath,
            sandboxEnabled: !noSandbox,
            logger: logger,
        )
        try await server.run()
    }
}

import Logging
import Foundation
import ArgumentParser

/// Command-line interface for the xc-simulator MCP server.
///
/// This focused server provides iOS Simulator tools with moderate
/// token overhead (~6K tokens vs ~50K for the full xc-mcp server).
///
/// ## Usage
///
/// ```bash
/// # Start with default settings (current directory)
/// xc-simulator
///
/// # Start with a specific base path
/// xc-simulator /path/to/project
///
/// # Enable verbose logging
/// xc-simulator --verbose
/// ```
@main
struct SimulatorServerCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "xc-simulator",
        abstract: "MCP server for iOS Simulator operations (29 tools, ~6K tokens)",
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

        let logger = Logger(label: "com.toba.xc-simulator")

        let resolvedBasePath = basePath ?? FileManager.default.currentDirectoryPath

        let server = SimulatorMCPServer(basePath: resolvedBasePath, logger: logger)
        try await server.run()
    }
}

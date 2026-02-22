import Logging
import Foundation
import ArgumentParser

/// Command-line interface for the xc-device MCP server.
///
/// This focused server provides physical iOS device tools with minimal
/// token overhead (~2K tokens vs ~50K for the full xc-mcp server).
///
/// ## Usage
///
/// ```bash
/// # Start with default settings (current directory)
/// xc-device
///
/// # Start with a specific base path
/// xc-device /path/to/project
///
/// # Enable verbose logging
/// xc-device --verbose
/// ```
@main
struct DeviceServerCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "xc-device",
        abstract: "MCP server for physical iOS device operations (12 tools, ~2K tokens)",
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

        let logger = Logger(label: "com.toba.xc-device")

        let resolvedBasePath = basePath ?? FileManager.default.currentDirectoryPath

        let server = DeviceMCPServer(basePath: resolvedBasePath, logger: logger)
        try await server.run()
    }
}

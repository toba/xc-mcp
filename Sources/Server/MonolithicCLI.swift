import Logging
import Foundation
import ArgumentParser

/// Command-line interface for the monolithic Xcode MCP server.
struct XcodeMCPServerCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "xc-mcp",
        abstract: "MCP server for Xcode project manipulation, building, and testing",
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

        let logger = Logger(label: "com.toba.xc-mcp")

        let resolvedBasePath = basePath ?? FileManager.default.currentDirectoryPath

        let server = XcodeMCPServer(basePath: resolvedBasePath, logger: logger)
        try await server.run()
    }
}

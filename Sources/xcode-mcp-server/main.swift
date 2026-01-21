import ArgumentParser
import Foundation
import Logging
import XcodeMCP

@main
struct XcodeMCPServerCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "xcode-mcp-server",
        abstract: "MCP server for Xcode project manipulation, building, and testing"
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

        let logger = Logger(label: "com.toba.xcode-mcp-server")

        let resolvedBasePath = basePath ?? FileManager.default.currentDirectoryPath

        let server = XcodeMCPServer(basePath: resolvedBasePath, logger: logger)
        try await server.run()
    }
}

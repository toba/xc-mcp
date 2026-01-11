import ArgumentParser
import Foundation
import Logging
import XcodeProjectMCP

@main
struct XcodeprojMCPServer: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "xcodeproj-mcp-server",
        abstract: "MCP server for manipulating Xcode project files"
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

        let logger = Logger(label: "org.giginet.xcodeproj-mcp-server")

        let resolvedBasePath = basePath ?? FileManager.default.currentDirectoryPath

        let server = XcodeProjectMCPServer(basePath: resolvedBasePath, logger: logger)
        try await server.run()
    }
}

import ArgumentParser
import Foundation
import Logging

/// Command-line interface for the xc-strings MCP server.
///
/// This focused server provides Xcode String Catalog (.xcstrings) manipulation tools
/// with minimal token overhead (~6K tokens).
///
/// ## Usage
///
/// ```bash
/// # Start with default settings (current directory)
/// xc-strings
///
/// # Start with a specific base path
/// xc-strings /path/to/project
///
/// # Enable verbose logging
/// xc-strings --verbose
/// ```
@main
struct StringsServerCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "xc-strings",
        abstract:
            "MCP server for Xcode String Catalog (.xcstrings) file manipulation (18 tools, ~6K tokens)"
    )

    @Argument(help: "Base path for the server to operate in. Defaults to current directory.")
    var basePath: String?

    @Flag(name: .shortAndLong, help: "Enable verbose logging (debug level)")
    var verbose: Bool = false

    @Flag(
        name: .long, help: "Disable path sandboxing (allow access to paths outside base directory)")
    var noSandbox: Bool = false

    mutating func run() async throws {
        let logLevel: Logger.Level = verbose ? .debug : .info
        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardError(label: label)
            handler.logLevel = logLevel
            return handler
        }

        let logger = Logger(label: "com.toba.xc-strings")

        let resolvedBasePath = basePath ?? FileManager.default.currentDirectoryPath

        let server = StringsMCPServer(
            basePath: resolvedBasePath,
            sandboxEnabled: !noSandbox,
            logger: logger
        )
        try await server.run()
    }
}

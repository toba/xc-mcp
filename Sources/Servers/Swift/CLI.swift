import ArgumentParser
import Foundation
import Logging

/// Command-line interface for the xc-swift MCP server.
///
/// This focused server provides Swift Package Manager tools with minimal
/// token overhead (~1.5K tokens vs ~50K for the full xc-mcp server).
///
/// ## Usage
///
/// ```bash
/// # Start with default settings (current directory)
/// xc-swift
///
/// # Start with a specific base path
/// xc-swift /path/to/project
///
/// # Enable verbose logging
/// xc-swift --verbose
/// ```
@main
struct SwiftServerCLI: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "xc-swift",
    abstract: "MCP server for Swift Package Manager operations (6 tools, ~1.5K tokens)",
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

    let logger = Logger(label: "com.toba.xc-swift")

    let resolvedBasePath = basePath ?? FileManager.default.currentDirectoryPath

    let server = SwiftMCPServer(basePath: resolvedBasePath, logger: logger)
    try await server.run()
  }
}
